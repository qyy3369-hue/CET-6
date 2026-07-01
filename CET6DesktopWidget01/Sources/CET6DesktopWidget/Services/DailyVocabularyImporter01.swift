import Foundation

@MainActor
final class DailyVocabularyImporter01 {
    private let store: TaskStore
    private var timer: Timer?
    private var isImporting = false

    private let dailyHour = 7
    private let dailyMinute = 30
    private let dailyCount = 20

    init(store: TaskStore) {
        self.store = store
    }

    func start() {
        scheduleNextImport()
        Task { await importIfDue() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleNextImport() {
        timer?.invalidate()

        let now = Date()
        let nextDate = nextImportDate(after: now)
        timer = Timer(fireAt: nextDate, interval: 0, target: self, selector: #selector(handleTimer), userInfo: nil, repeats: false)
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    @objc private func handleTimer() {
        Task {
            await importIfDue(skipTimeCheck: true)
            scheduleNextImport()
        }
    }

    private func importIfDue(skipTimeCheck: Bool = false) async {
        guard !isImporting else { return }
        guard shouldImportToday(skipTimeCheck: skipTimeCheck) else { return }

        isImporting = true
        defer { isImporting = false }

        do {
            let result = try await importDailyWords()
            guard !result.addedWords.isEmpty else { return }

            let title = "闪卡复习：今日新增 \(result.addedWords.count) 个词（\(result.addedWords.prefix(5).joined(separator: ", ")) 等）"
            store.addTask(title, date: DateKey.today())
            NotificationCenter.default.post(name: .dailyVocabularyDidImport, object: nil)
        } catch {
            print("Daily vocabulary import failed: \(error.localizedDescription)")
        }
    }

    private func shouldImportToday(skipTimeCheck: Bool = false, calendar: Calendar = .current) -> Bool {
        let state = loadState()
        guard state.lastImportDate != DateKey.today(calendar: calendar) else { return false }
        guard !skipTimeCheck else { return true }

        let now = Date()
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)
        let isAfterDailyTime = hour > dailyHour || (hour == dailyHour && minute >= dailyMinute)
        return isAfterDailyTime
    }

    private func importDailyWords() async throws -> ImportResult {
        let service = try DeepSeekPlanService()
        let sourceWords = try loadSourceWords()
        var state = loadState()
        var existingWords = loadStoredWords()

        let existingKeys = Set(existingWords.map { $0.word.lowercased() })
        let importedKeys = Set(state.importedWords.map { $0.lowercased() })
        let candidates = sourceWords.filter { !existingKeys.contains($0) && !importedKeys.contains($0) }
        guard !candidates.isEmpty else {
            state.lastImportDate = DateKey.today()
            saveState(state)
            return ImportResult(addedWords: [])
        }

        let selectedWords = Array(candidates.shuffled().prefix(dailyCount))
        var addedEntries: [StoredVocabularyWord01] = []
        var failedWords: [String] = []

        for word in selectedWords {
            do {
                let lookup = try await service.completeVocabularyWord(word)
                addedEntries.append(StoredVocabularyWord01(lookup: lookup, fallbackWord: word))
            } catch {
                failedWords.append(word)
            }
        }

        guard !addedEntries.isEmpty else {
            appendHistory(to: &state, requested: selectedWords, added: [], failed: failedWords)
            saveState(state)
            return ImportResult(addedWords: [])
        }

        existingWords = mergeWords(addedEntries + existingWords)
        saveStoredWords(existingWords)

        let addedWords = addedEntries.map(\.word)
        state.importedWords = Array(Set(state.importedWords + addedWords)).sorted()
        state.lastImportDate = DateKey.today()
        appendHistory(to: &state, requested: selectedWords, added: addedWords, failed: failedWords)
        saveState(state)

        return ImportResult(addedWords: addedWords)
    }

    private func appendHistory(to state: inout ImportState01, requested: [String], added: [String], failed: [String]) {
        state.history.append(
            ImportHistory01(
                date: DateKey.today(),
                requested: requested,
                added: added,
                failed: failed
            )
        )
    }

    private func loadSourceWords() throws -> [String] {
        let text = try String(contentsOf: Self.vocabFileURL, encoding: .utf8)
        let tokens = text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        var seen: Set<String> = []
        var words: [String] = []
        let pattern = #"^[A-Za-z][A-Za-z'-]*$"#

        for token in tokens {
            let word = token.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard word.range(of: pattern, options: .regularExpression) != nil else { continue }
            guard !seen.contains(word) else { continue }
            seen.insert(word)
            words.append(word)
        }

        return words
    }

    private func loadStoredWords() -> [StoredVocabularyWord01] {
        guard let data = try? Data(contentsOf: Self.customWordsFileURL),
              let words = try? JSONDecoder().decode([StoredVocabularyWord01].self, from: data) else {
            return []
        }
        return words
    }

    private func saveStoredWords(_ words: [StoredVocabularyWord01]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(words) else { return }
        try? FileManager.default.createDirectory(at: Self.dataFolderURL, withIntermediateDirectories: true)
        try? data.write(to: Self.customWordsFileURL, options: .atomic)
    }

    private func loadState() -> ImportState01 {
        guard let data = try? Data(contentsOf: Self.stateFileURL),
              let state = try? JSONDecoder().decode(ImportState01.self, from: data) else {
            return ImportState01()
        }
        return state
    }

    private func saveState(_ state: ImportState01) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(state) else { return }
        try? FileManager.default.createDirectory(at: Self.dataFolderURL, withIntermediateDirectories: true)
        try? data.write(to: Self.stateFileURL, options: .atomic)
    }

    private func mergeWords(_ words: [StoredVocabularyWord01]) -> [StoredVocabularyWord01] {
        var seen: Set<String> = []
        var merged: [StoredVocabularyWord01] = []

        for word in words {
            let key = word.word.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            merged.append(word)
        }

        return merged
    }

    private func nextImportDate(after date: Date, calendar: Calendar = .current) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        components.hour = dailyHour
        components.minute = dailyMinute
        components.second = 0

        let todayImportDate = calendar.date(from: components) ?? date
        if todayImportDate > date {
            return todayImportDate
        }

        return calendar.date(byAdding: .day, value: 1, to: todayImportDate) ?? date.addingTimeInterval(24 * 60 * 60)
    }

    private static let workspaceURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("CET-6", isDirectory: true)

    private static let projectURL = workspaceURL
        .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)

    private static let dataFolderURL = projectURL
        .appendingPathComponent("Data", isDirectory: true)

    private static let vocabFileURL = workspaceURL
        .appendingPathComponent("词汇.txt")

    private static var customWordsFileURL: URL {
        let existing = (try? FileManager.default.contentsOfDirectory(
            at: dataFolderURL,
            includingPropertiesForKeys: nil
        )) ?? []

        if let latest = existing
            .filter({ $0.lastPathComponent.range(of: #"^custom_words\d+\.json$"#, options: .regularExpression) != nil })
            .sorted(by: { $0.lastPathComponent > $1.lastPathComponent })
            .first {
            return latest
        }

        return dataFolderURL.appendingPathComponent("custom_words01.json")
    }

    private static let stateFileURL = dataFolderURL
        .appendingPathComponent("word_import_state01.json")
}

private struct ImportResult {
    let addedWords: [String]
}

private struct StoredVocabularyWord01: Codable {
    let id: String
    let word: String
    let phonetic: String
    let partOfSpeech: String
    let meaning: String
    let example: String
    let exampleTranslation: String
    let phrases: [String]
    let phraseTranslations: [String]
    let mnemonic: String
    let tag: String
    let difficulty: Int

    private enum CodingKeys: String, CodingKey {
        case id
        case word
        case phonetic
        case partOfSpeech
        case meaning
        case example
        case exampleTranslation
        case phrases
        case phraseTranslations
        case mnemonic
        case tag
        case difficulty
    }

    init(lookup: WordLookupResult, fallbackWord: String) {
        let normalized = lookup.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackWord.lowercased()
            : lookup.word.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        self.id = "custom-\(normalized)"
        self.word = normalized
        self.phonetic = lookup.phonetic
        self.partOfSpeech = lookup.partOfSpeech
        self.meaning = lookup.meaning
        self.example = lookup.example
        self.exampleTranslation = lookup.exampleTranslation
        self.phrases = lookup.phrases
        self.phraseTranslations = lookup.phraseTranslations
        self.mnemonic = lookup.mnemonic
        self.tag = lookup.tag
        self.difficulty = lookup.difficulty
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.word = try container.decode(String.self, forKey: .word)
        self.phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic) ?? ""
        self.partOfSpeech = try container.decodeIfPresent(String.self, forKey: .partOfSpeech) ?? "未标注"
        self.meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        self.example = try container.decodeIfPresent(String.self, forKey: .example) ?? ""
        self.exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation) ?? ""
        self.phrases = try container.decodeIfPresent([String].self, forKey: .phrases) ?? []
        self.phraseTranslations = try container.decodeIfPresent([String].self, forKey: .phraseTranslations) ?? []
        self.mnemonic = try container.decodeIfPresent(String.self, forKey: .mnemonic) ?? ""
        self.tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? "自定义"
        self.difficulty = try container.decodeIfPresent(Int.self, forKey: .difficulty) ?? 3
    }
}

private struct ImportState01: Codable {
    var lastImportDate: String?
    var importedWords: [String] = []
    var history: [ImportHistory01] = []
}

private struct ImportHistory01: Codable {
    let date: String
    let requested: [String]
    let added: [String]
    let failed: [String]
}

extension Notification.Name {
    static let dailyVocabularyDidImport = Notification.Name("CET6DailyVocabularyDidImport")
}
