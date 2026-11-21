import Foundation

struct FlashcardReviewProgress01: Codable, Equatable, Identifiable {
    var id: String { wordID }

    let wordID: String
    var level: Int
    var lastReview: Date?
    var nextReview: Date?
    var correctCount: Int
    var incorrectCount: Int

    init(
        wordID: String,
        level: Int = 0,
        lastReview: Date? = nil,
        nextReview: Date? = nil,
        correctCount: Int = 0,
        incorrectCount: Int = 0
    ) {
        self.wordID = wordID
        self.level = min(max(level, 0), 5)
        self.lastReview = lastReview
        self.nextReview = nextReview
        self.correctCount = max(correctCount, 0)
        self.incorrectCount = max(incorrectCount, 0)
    }
}

enum FlashcardReviewScheduler01 {
    private static let correctIntervals: [TimeInterval] = [
        30 * 60,
        12 * 60 * 60,
        3 * 24 * 60 * 60,
        7 * 24 * 60 * 60,
        15 * 24 * 60 * 60
    ]

    static func record(
        wordID: String,
        existing: FlashcardReviewProgress01?,
        isCorrect: Bool,
        now: Date = Date()
    ) -> FlashcardReviewProgress01 {
        var progress = existing ?? FlashcardReviewProgress01(wordID: wordID)
        progress.lastReview = now

        if isCorrect {
            let newLevel = min(progress.level + 1, 5)
            progress.level = newLevel
            progress.correctCount += 1
            progress.nextReview = now.addingTimeInterval(correctIntervals[newLevel - 1])
        } else {
            progress.level = 0
            progress.incorrectCount += 1
            progress.nextReview = now
        }

        return progress
    }

    static func isDue(_ progress: FlashcardReviewProgress01?, now: Date = Date()) -> Bool {
        guard let progress, let nextReview = progress.nextReview else { return true }
        return nextReview <= now
    }
}

enum FlashcardReviewQueue01 {
    static func isEligibleForDueReview(
        progress: FlashcardReviewProgress01?,
        isDismissed: Bool,
        now: Date = Date()
    ) -> Bool {
        guard !isDismissed else { return false }
        return progress == nil || FlashcardReviewScheduler01.isDue(progress, now: now)
    }

    static func inferredDismissedWordIDs(
        progressByWordID: [String: FlashcardReviewProgress01],
        favoriteWordIDs: Set<String>
    ) -> Set<String> {
        Set(progressByWordID.values.compactMap { progress in
            guard progress.level == 0,
                  progress.incorrectCount > 0,
                  !favoriteWordIDs.contains(progress.wordID) else { return nil }
            return progress.wordID
        })
    }
}

enum VocabularyBanishment01 {
    static func key(for rawWord: String) -> String {
        rawWord
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func isBanished(_ rawWord: String, banishedKeys: Set<String>) -> Bool {
        banishedKeys.contains(key(for: rawWord))
    }
}

enum FlashcardReviewAdvanceAction01: Equatable {
    case none
    case skipCard
    case submitAnswer
    case confirmCorrection
    case nextCard
}

enum FlashcardReviewFlow01 {
    static func isUnknownAnswer(_ answer: String) -> Bool {
        answer.trimmingCharacters(in: .whitespacesAndNewlines) == "、"
    }

    static func advanceAction(
        isBusy: Bool,
        hasJudgment: Bool,
        isCorrect: Bool?,
        hasCompletedCorrection: Bool,
        answer: String,
        correction: String
    ) -> FlashcardReviewAdvanceAction01 {
        guard !isBusy else { return .none }

        if !hasJudgment {
            return answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .skipCard : .submitAnswer
        }

        if isCorrect == false, !hasCompletedCorrection {
            return correction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .none : .confirmCorrection
        }

        return .nextCard
    }
}

enum FlashcardReviewStore01 {
    static func load() -> [String: FlashcardReviewProgress01] {
        guard let data = try? Data(contentsOf: fileURL),
              let entries = try? decoder.decode([FlashcardReviewProgress01].self, from: data) else {
            return [:]
        }
        return Dictionary(entries.map { ($0.wordID, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    static func save(_ progressByWordID: [String: FlashcardReviewProgress01]) throws {
        let entries = progressByWordID.values.sorted { $0.wordID < $1.wordID }
        let data = try encoder.encode(entries)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
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

    private static let fileURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents", isDirectory: true)
        .appendingPathComponent("CET-6", isDirectory: true)
        .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
        .appendingPathComponent("Data", isDirectory: true)
        .appendingPathComponent("flashcard_progress01.json")
}
