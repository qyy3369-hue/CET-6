import SwiftUI

enum GoalsSettingsPane: String, CaseIterable, Identifiable {
    case general
    case deepSeek
    case speech

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "通用"
        case .deepSeek: "DeepSeek"
        case .speech: "朗读"
        }
    }
}

struct GoalsSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var display: WidgetVisibilityController
    @ObservedObject var speech: VocabularySpeechService01
    @State private var pane: GoalsSettingsPane
    @State private var deepSeekDraft = DeepSeekSettingsDraft()

    init(display: WidgetVisibilityController, speech: VocabularySpeechService01, initialPane: GoalsSettingsPane) {
        self.display = display
        self.speech = speech
        self._pane = State(initialValue: initialPane)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("设置")
                .font(.title2.weight(.semibold))
                .accessibilityAddTraits(.isHeader)

            GoalsSegmentedControl(
                title: "设置分类",
                selection: $pane,
                options: GoalsSettingsPane.allCases.map { ($0, $0.title) }
            )

            ZStack(alignment: .topLeading) {
                Group {
                    switch pane {
                    case .general: general
                    case .deepSeek: DeepSeekSettingsView(draft: $deepSeekDraft)
                    case .speech: speechSettings
                    }
                }
                .id(pane)
                .transition(reduceMotion ? .identity : .opacity)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: pane)
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 231, alignment: .topLeading)
            .background(StudyTheme.paper, in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(StudyTheme.hairline) }

            HStack {
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(GoalsButtonStyle())
            }
        }
        .padding(24)
        .frame(width: 505)
        .background(StudyTheme.windowBase)
        .foregroundStyle(StudyTheme.ink)
        .tint(StudyTheme.command)
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 16) {
            GoalsSegmentedControl(
                title: "外观",
                selection: $display.appearance,
                options: GoalsAppearance.allCases.map { ($0, $0.title) }
            )

            Divider()

            Toggle("显示桌面悬浮窗", isOn: $display.isVisible)
                .toggleStyle(.switch)
            Text("在桌面查看和勾选今日任务。")
                .font(.callout)
                .foregroundStyle(StudyTheme.secondaryInk)
        }
    }

    private var speechSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle("闪卡自动朗读", isOn: $speech.isAutoPlayEnabled)
                .toggleStyle(.switch)

            GoalsSegmentedControl(
                title: "发音",
                selection: $speech.accent,
                options: VocabularySpeechAccent01.allCases.map { ($0, $0.title) }
            )

            Slider(value: $speech.rate, in: VocabularySpeechService01.minimumRate...VocabularySpeechService01.maximumRate) {
                Text("语速")
            } minimumValueLabel: {
                Image(systemName: "tortoise")
            } maximumValueLabel: {
                Image(systemName: "hare")
            }

            Button {
                speech.speak("Good morning. Let's get started.")
            } label: {
                Label("试听发音", systemImage: "speaker.wave.2")
            }
            .buttonStyle(GoalsButtonStyle())
        }
    }
}
