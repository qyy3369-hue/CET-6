import SwiftUI

struct DeepSeekSettingsDraft {
    var apiKey = ""
    var hasConfiguredKey = !(EnvLoader.load()[EnvLoader.apiKeyName] ?? "").isEmpty
    var model = EnvLoader.projectModel()
    var feedback: String?
    var saveFailed = false
}

struct DeepSeekSettingsView: View {
    @Binding var draft: DeepSeekSettingsDraft
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionStatus: String?
    @State private var connectionFailed = false

    private var hasUsableKey: Bool {
        draft.hasConfiguredKey || !draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("API 密钥")
                    .font(.headline)
                SecureField(draft.hasConfiguredKey ? "已配置，输入新密钥可替换" : "输入 DeepSeek API 密钥", text: $draft.apiKey)
                    .accessibilityLabel("DeepSeek API 密钥")
                    .goalsInput()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("模型")
                    .font(.headline)
                TextField(EnvLoader.defaultModel, text: $draft.model)
                    .accessibilityLabel("DeepSeek 模型")
                    .goalsInput()
                Text("留空时使用 \(EnvLoader.defaultModel)。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("设置保存在项目的 .env 文件中。启动环境提供的配置优先。")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let connectionStatus {
                Text(connectionStatus)
                    .font(.callout)
                    .foregroundStyle(connectionFailed ? StudyTheme.cinnabar : StudyTheme.quietGreen)
            }
            if let feedback = draft.feedback {
                Text(feedback)
                    .font(.callout)
                    .foregroundStyle(draft.saveFailed ? StudyTheme.cinnabar : StudyTheme.quietGreen)
            }

            HStack(spacing: 9) {
                Spacer()
                Button(connectionTask == nil ? "测试连接" : "测试中…", action: testConnection)
                    .buttonStyle(GoalsButtonStyle())
                    .disabled(connectionTask != nil || !hasUsableKey)
                Button("保存 DeepSeek 配置", action: save)
                    .buttonStyle(GoalsButtonStyle(.primary))
                    .disabled(connectionTask != nil || !hasUsableKey)
            }
        }
        .onChange(of: draft.apiKey) { _, newValue in
            if !newValue.isEmpty { draft.feedback = nil }
            resetConnectionTest()
        }
        .onChange(of: draft.model) { _, _ in
            draft.feedback = nil
            resetConnectionTest()
        }
        .onDisappear { resetConnectionTest() }
    }

    private func testConnection() {
        guard connectionTask == nil else { return }
        connectionStatus = nil
        var config = EnvLoader.load()
        let typedKey = draft.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedModel = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typedKey.isEmpty { config[EnvLoader.apiKeyName] = typedKey }
        config[EnvLoader.modelName] = typedModel.isEmpty ? EnvLoader.defaultModel : typedModel

        connectionTask = Task {
            do {
                try await DeepSeekPlanService(env: config).testConnection()
                guard !Task.isCancelled else { return }
                connectionFailed = false
                connectionStatus = "连接成功"
            } catch {
                guard !Task.isCancelled else { return }
                let message = error.localizedDescription
                let key = config[EnvLoader.apiKeyName] ?? ""
                let safeMessage = key.isEmpty ? message : message.replacingOccurrences(of: key, with: "•••")
                connectionFailed = true
                connectionStatus = "连接失败：\(safeMessage)"
            }
            connectionTask = nil
        }
    }

    private func resetConnectionTest() {
        connectionTask?.cancel()
        connectionTask = nil
        connectionStatus = nil
    }

    private func save() {
        do {
            try EnvLoader.saveDeepSeek(apiKey: draft.apiKey, model: draft.model)
            draft.apiKey = ""
            draft.hasConfiguredKey = !(EnvLoader.load()[EnvLoader.apiKeyName] ?? "").isEmpty
            draft.saveFailed = false
            draft.feedback = "已保存"
        } catch {
            draft.saveFailed = true
            draft.feedback = error.localizedDescription
        }
    }
}
