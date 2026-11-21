import Foundation

struct BanishedVocabularyRecord01: Codable, Equatable, Identifiable {
    let key: String
    let word: VocabularyWord
    let customSnapshots: [VocabularyWord]
    let originalWordIDs: [String]
    let previousProgress: [FlashcardReviewProgress01]
    let favoriteWordIDs: [String]
    let dismissedWordIDs: [String]
    let banishedAt: Date
    let isLegacyFallback: Bool

    var id: String { key }

    init(
        key: String,
        word: VocabularyWord,
        customSnapshots: [VocabularyWord],
        originalWordIDs: [String],
        previousProgress: [FlashcardReviewProgress01],
        favoriteWordIDs: [String],
        dismissedWordIDs: [String],
        banishedAt: Date = Date(),
        isLegacyFallback: Bool = false
    ) {
        self.key = key
        self.word = word
        self.customSnapshots = customSnapshots
        self.originalWordIDs = originalWordIDs.sorted()
        self.previousProgress = previousProgress.sorted { $0.wordID < $1.wordID }
        self.favoriteWordIDs = favoriteWordIDs.sorted()
        self.dismissedWordIDs = dismissedWordIDs.sorted()
        self.banishedAt = banishedAt
        self.isLegacyFallback = isLegacyFallback
    }
}

enum BanishedVocabularyStore01 {
    static func load(fileURL: URL = defaultFileURL) -> [BanishedVocabularyRecord01] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? decoder.decode([BanishedVocabularyRecord01].self, from: data) else {
            return []
        }
        return normalized(records)
    }

    static func save(_ records: [BanishedVocabularyRecord01], fileURL: URL = defaultFileURL) throws {
        let data = try encoder.encode(normalized(records))
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    static func migratingLegacyKeys(
        existingRecords: [BanishedVocabularyRecord01],
        legacyKeys: Set<String>,
        customCatalog: [VocabularyWord],
        standardCatalog: [VocabularyWord]
    ) -> [BanishedVocabularyRecord01] {
        var recordsByKey = Dictionary(uniqueKeysWithValues: normalized(existingRecords).map { ($0.key, $0) })
        let customCatalogByKey = Dictionary(
            customCatalog.map { (VocabularyBanishment01.key(for: $0.word), $0) },
            uniquingKeysWith: { preferred, _ in preferred }
        )
        let standardCatalogByKey = Dictionary(
            standardCatalog.map { (VocabularyBanishment01.key(for: $0.word), $0) },
            uniquingKeysWith: { preferred, _ in preferred }
        )

        for key in legacyKeys where recordsByKey[key] == nil {
            let snapshot = customCatalogByKey[key] ?? standardCatalogByKey[key] ?? legacyFallbackWord(for: key)
            let matchingCustomWords = customCatalog.filter { VocabularyBanishment01.key(for: $0.word) == key }
            let matchingStandardWords = standardCatalog.filter { VocabularyBanishment01.key(for: $0.word) == key }
            recordsByKey[key] = BanishedVocabularyRecord01(
                key: key,
                word: snapshot,
                customSnapshots: matchingCustomWords,
                originalWordIDs: (matchingCustomWords + matchingStandardWords).map(\.id),
                previousProgress: [],
                favoriteWordIDs: [],
                dismissedWordIDs: [],
                isLegacyFallback: matchingCustomWords.isEmpty && matchingStandardWords.isEmpty
            )
        }

        return normalized(Array(recordsByKey.values))
    }

    static func legacyFallbackWord(for key: String) -> VocabularyWord {
        VocabularyWord(
            id: "custom-\(key)",
            word: key,
            phonetic: "",
            partOfSpeech: "未标注",
            meaning: VocabularyWord.restoredPendingMeaning,
            example: "",
            tag: "已恢复",
            difficulty: 3
        )
    }

    private static func normalized(_ records: [BanishedVocabularyRecord01]) -> [BanishedVocabularyRecord01] {
        var recordsByKey: [String: BanishedVocabularyRecord01] = [:]
        for record in records where !record.key.isEmpty {
            let existing = recordsByKey[record.key]
            if existing == nil || record.banishedAt > existing!.banishedAt {
                recordsByKey[record.key] = record
            }
        }
        return recordsByKey.values.sorted {
            if $0.banishedAt == $1.banishedAt { return $0.key < $1.key }
            return $0.banishedAt > $1.banishedAt
        }
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let defaultFileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("CET-6", isDirectory: true)
        .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
        .appendingPathComponent("Data", isDirectory: true)
        .appendingPathComponent("banished_words01.json")
}
