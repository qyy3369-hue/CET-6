import Darwin
import Foundation

enum EnvLoader {
    static let apiKeyName = "DEEPSEEK_API_KEY"
    static let modelName = "DEEPSEEK_MODEL"
    static let defaultModel = "deepseek-v4-flash"

    private enum ConfigurationError: LocalizedError {
        case invalidValue
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .invalidValue:
                return "密钥或模型包含无效字符。请检查是否误贴了空格、引号或多行文本。"
            case .writeFailed:
                return "无法保存 DeepSeek 设置。请检查项目目录的写入权限。"
            }
        }
    }

    static func load() -> [String: String] {
        var values = ProcessInfo.processInfo.environment

        for fileURL in candidateFileURLs() where FileManager.default.fileExists(atPath: fileURL.path) {
            guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else { continue }
            parse(content).forEach { key, value in
                if values[key]?.isEmpty ?? true {
                    values[key] = value
                }
            }
        }

        return values
    }

    static func projectModel() -> String {
        guard let content = try? String(contentsOf: projectFileURL, encoding: .utf8) else { return "" }
        return parse(content)[modelName] ?? ""
    }

    static func saveDeepSeek(apiKey: String, model: String, to fileURL: URL = projectFileURL) throws {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.range(of: #"[^A-Za-z0-9._-]"#, options: .regularExpression) == nil,
              model.range(of: #"[^A-Za-z0-9._:/-]"#, options: .regularExpression) == nil else {
            throw ConfigurationError.invalidValue
        }

        let fileManager = FileManager.default
        let content = fileManager.fileExists(atPath: fileURL.path)
            ? try String(contentsOf: fileURL, encoding: .utf8)
            : ""
        var lines = content.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        if content.last?.isNewline == true {
            lines.removeLast()
        }

        lines.removeAll { line in
            guard let name = assignment(in: line)?.name else { return false }
            return name == modelName || (name == apiKeyName && !key.isEmpty)
        }
        if !key.isEmpty { lines.append("\(apiKeyName)=\(key)") }
        if !model.isEmpty { lines.append("\(modelName)=\(model)") }

        let directory = fileURL.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? fileManager.removeItem(at: directory) }

        let staged = directory.appendingPathComponent(".env")
        let output = lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
        guard fileManager.createFile(
            atPath: staged.path,
            contents: Data(output.utf8),
            attributes: [.posixPermissions: 0o600]
        ), rename(staged.path, fileURL.path) == 0 else {
            throw ConfigurationError.writeFailed
        }
    }

    private static var projectFileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent(".env")
    }

    private static func candidateFileURLs() -> [URL] {
        let workingDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".env")

        return [workingDirectoryURL, projectFileURL]
    }

    private static func parse(_ content: String) -> [String: String] {
        var values: [String: String] = [:]

        for rawLine in content.components(separatedBy: .newlines) {
            guard let (name, rawValue) = assignment(in: rawLine) else { continue }
            var value = rawValue

            if value.count >= 2,
               let first = value.first,
               let last = value.last,
               (first == "\"" && last == "\"") || (first == "'" && last == "'") {
                value.removeFirst()
                value.removeLast()
            }

            values[name] = value
        }

        return values
    }

    private static func assignment(in rawLine: String) -> (name: String, value: String)? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else { return nil }
        let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        return (name, value)
    }
}
