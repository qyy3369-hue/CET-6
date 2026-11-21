import Foundation
import XCTest
@testable import CET6DesktopWidget

@MainActor
final class LogicRegressionTests01: XCTestCase {
    private struct Record: Identifiable, Equatable {
        let id: UUID
        let value: String
    }

    func testRelativeDaysUseStableAnchorDate() {
        let blocks = StudyWindowView.generateSchedule(
            from: """
            第1天 08:00 词汇背诵
            第2天 09:00 阅读训练
            """,
            anchorDateKey: "2026-01-10"
        )

        XCTAssertEqual(blocks.map(\.dateKey), ["2026-01-10", "2026-01-11"])
    }

    func testSingleChineseDigitsAreParsedAsMonthAndDay() {
        let blocks = StudyWindowView.generateSchedule(
            from: "三月五日 08:00 词汇背诵",
            anchorDateKey: "2026-01-10"
        )

        XCTAssertEqual(blocks.first?.dateKey, "2026-03-05")
    }

    func testTaskLookupDoesNotFallbackToSameTitleOnAnotherDate() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("study_tasks01.json")
        try Data("[]".utf8).write(to: fileURL)
        let store = TaskStore(fileURL: fileURL)
        store.addTask(
            "词汇背诵",
            date: "2026-07-01",
            goalID: "goal",
            goalTitle: "目标",
            planID: "plan"
        )

        let differentDateBlock = ScheduleBlock(
            dateKey: "2026-07-03",
            timeLabel: "08:00",
            title: "词汇背诵",
            note: "",
            category: "词汇"
        )

        XCTAssertNil(store.task(for: differentDateBlock, goalID: "goal", planID: "plan"))
    }

    func testDuplicateTitlesKeepTheirExactDatesWhenBlocksAreReordered() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let fileURL = directory.appendingPathComponent("study_tasks01.json")
        let tasks = [
            StudyTask(date: "2026-07-01", title: "词汇背诵", source: "plan", goalID: "goal", goalTitle: "目标", planID: "plan"),
            StudyTask(date: "2026-07-03", title: "词汇背诵", source: "plan", goalID: "goal", goalTitle: "目标", planID: "plan")
        ]
        try JSONEncoder().encode(tasks).write(to: fileURL)
        let store = TaskStore(fileURL: fileURL)
        let reorderedBlocks = [
            ScheduleBlock(dateKey: "2026-07-03", timeLabel: "08:00", title: "词汇背诵", note: "", category: "词汇"),
            ScheduleBlock(dateKey: "2026-07-01", timeLabel: "08:00", title: "词汇背诵", note: "", category: "词汇")
        ]

        let resolved = store.resolvedPlanBlocks(reorderedBlocks, goalID: "goal", planID: "plan")

        XCTAssertEqual(resolved.map(\.dateKey), ["2026-07-03", "2026-07-01"])
    }

    func testDayHeadingSummaryOnlyTakesOneLineAfterImportantHeading() {
        let blocks = StudyWindowView.generateSchedule(
            from: """
            # Day 1: 阅读训练
            今日任务
            完成两篇阅读
            这行不应继续收集
            这行也不应继续收集
            """,
            anchorDateKey: "2026-01-10"
        )

        XCTAssertEqual(blocks.first?.note, "今日任务；完成两篇阅读")
    }

    func testEmptyGoalReceivesFallbackPlan() {
        let goal = GoalPlan(title: "测试目标", mode: "测试", focus: "测试", plans: [])

        let normalized = GoalPlanStore01.ensureEveryGoalHasPlan([goal], defaultPlanText: "第1天 测试")

        XCTAssertEqual(normalized.first?.plans.count, 1)
        XCTAssertEqual(normalized.first?.plans.first?.planText, "第1天 测试")
    }

    func testLegacyPlanWithoutSavedScheduleStillDecodes() throws {
        let legacyJSON = """
        {
          "id": "legacy-plan",
          "title": "计划表01",
          "planText": "第1天 测试",
          "createdAt": 0,
          "updatedAt": 0
        }
        """

        let decoded = try JSONDecoder().decode(GoalPlanSheet.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(decoded.id, "legacy-plan")
        XCTAssertNil(decoded.generatedSchedule)
    }

    func testRecordsFromFileAndDefaultsAreMergedByID() {
        let sharedID = UUID()
        let fileRecord = Record(id: sharedID, value: "文件版本")
        let defaultsDuplicate = Record(id: sharedID, value: "默认存储版本")
        let defaultsOnly = Record(id: UUID(), value: "仅默认存储")

        let merged = StudyWindowView.mergeRecords(
            preferred: [fileRecord],
            fallback: [defaultsDuplicate, defaultsOnly]
        )

        XCTAssertEqual(merged, [fileRecord, defaultsOnly])
    }

    func testNumberedFilesSortByNumericSuffix() {
        let file9 = URL(fileURLWithPath: "/tmp/custom_words9.json")
        let file10 = URL(fileURLWithPath: "/tmp/custom_words10.json")

        XCTAssertEqual([file9, file10].sorted(by: StudyWindowView.numberedFileSort), [file10, file9])
    }

    func testFlashcardCorrectAnswersFollowSRSIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        var progress: FlashcardReviewProgress01?
        let expectedIntervals: [TimeInterval] = [
            30 * 60,
            12 * 60 * 60,
            3 * 24 * 60 * 60,
            7 * 24 * 60 * 60,
            15 * 24 * 60 * 60
        ]

        for (index, interval) in expectedIntervals.enumerated() {
            progress = FlashcardReviewScheduler01.record(
                wordID: "allocate",
                existing: progress,
                isCorrect: true,
                now: start
            )
            XCTAssertEqual(progress?.level, index + 1)
            XCTAssertEqual(try XCTUnwrap(progress?.nextReview).timeIntervalSince(start), interval, accuracy: 0.1)
        }
    }

    func testFlashcardWrongAnswerResetsLevelAndIsDueImmediately() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let learned = FlashcardReviewProgress01(
            wordID: "allocate",
            level: 4,
            nextReview: now.addingTimeInterval(86_400),
            correctCount: 4
        )

        let reset = FlashcardReviewScheduler01.record(
            wordID: learned.wordID,
            existing: learned,
            isCorrect: false,
            now: now
        )

        XCTAssertEqual(reset.level, 0)
        XCTAssertEqual(reset.incorrectCount, 1)
        XCTAssertTrue(FlashcardReviewScheduler01.isDue(reset, now: now))
    }

    func testCancelledFavoriteIsRemovedFromDueReviewForEveryWord() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let wrongProgress = FlashcardReviewProgress01(
            wordID: "custom-prevent",
            level: 0,
            lastReview: now,
            nextReview: now,
            correctCount: 1,
            incorrectCount: 1
        )

        XCTAssertFalse(
            FlashcardReviewQueue01.isEligibleForDueReview(
                progress: wrongProgress,
                isDismissed: true,
                now: now
            )
        )
        XCTAssertTrue(
            FlashcardReviewQueue01.isEligibleForDueReview(
                progress: wrongProgress,
                isDismissed: false,
                now: now
            )
        )
        XCTAssertEqual(
            FlashcardReviewQueue01.inferredDismissedWordIDs(
                progressByWordID: [wrongProgress.wordID: wrongProgress],
                favoriteWordIDs: []
            ),
            Set([wrongProgress.wordID])
        )
        XCTAssertTrue(
            FlashcardReviewQueue01.inferredDismissedWordIDs(
                progressByWordID: [wrongProgress.wordID: wrongProgress],
                favoriteWordIDs: [wrongProgress.wordID]
            ).isEmpty
        )
    }

    func testBanishedVocabularyMatchesTheWordAcrossEverySourceID() {
        let banishedKeys: Set<String> = [VocabularyBanishment01.key(for: "prevent")]

        XCTAssertEqual(VocabularyBanishment01.key(for: "  PREVENT  "), "prevent")
        XCTAssertTrue(VocabularyBanishment01.isBanished("prevent", banishedKeys: banishedKeys))
        XCTAssertTrue(VocabularyBanishment01.isBanished("Prevent", banishedKeys: banishedKeys))
        XCTAssertFalse(VocabularyBanishment01.isBanished("prevention", banishedKeys: banishedKeys))
    }

    func testBanishedVocabularyRecordPersistsRecoveryState() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let word = VocabularyWord(
            id: "custom-prevent",
            word: "prevent",
            phonetic: "/prɪˈvent/",
            partOfSpeech: "v.",
            meaning: "阻止；预防",
            example: "Regular exercise can help prevent disease.",
            tag: "阅读高频",
            difficulty: 4
        )
        let progress = FlashcardReviewProgress01(
            wordID: word.id,
            level: 2,
            lastReview: Date(timeIntervalSince1970: 1_700_000_000),
            nextReview: Date(timeIntervalSince1970: 1_700_086_400),
            correctCount: 2,
            incorrectCount: 1
        )
        let record = BanishedVocabularyRecord01(
            key: "prevent",
            word: word,
            customSnapshots: [word],
            originalWordIDs: [word.id],
            previousProgress: [progress],
            favoriteWordIDs: [word.id],
            dismissedWordIDs: [],
            banishedAt: Date(timeIntervalSince1970: 1_700_000_100)
        )
        let fileURL = directory.appendingPathComponent("banished_words01.json")

        try BanishedVocabularyStore01.save([record], fileURL: fileURL)

        XCTAssertEqual(BanishedVocabularyStore01.load(fileURL: fileURL), [record])
    }

    func testLegacyBanishedKeyMigratesToRecoverableRecord() {
        let customWord = VocabularyWord(
            id: "custom-urgency",
            word: "urgency",
            phonetic: "/ˈɜːrdʒənsi/",
            partOfSpeech: "n.",
            meaning: "紧急；紧迫",
            example: "The issue requires urgency.",
            tag: "自定义",
            difficulty: 3
        )

        let migrated = BanishedVocabularyStore01.migratingLegacyKeys(
            existingRecords: [],
            legacyKeys: ["urgency", "unknownword"],
            customCatalog: [customWord],
            standardCatalog: []
        )

        XCTAssertEqual(migrated.map(\.key).sorted(), ["unknownword", "urgency"])
        XCTAssertEqual(migrated.first(where: { $0.key == "urgency" })?.word, customWord)
        XCTAssertEqual(migrated.first(where: { $0.key == "urgency" })?.customSnapshots, [customWord])
        XCTAssertFalse(migrated.first(where: { $0.key == "urgency" })?.isLegacyFallback ?? true)
        XCTAssertTrue(migrated.first(where: { $0.key == "unknownword" })?.isLegacyFallback ?? false)
    }

    func testLocalVocabularyAnswerAcceptsAnyCoreMeaning() {
        XCTAssertTrue(
            StudyWindowView.localVocabularyAnswerMatches("实质", expectedMeaning: "大量的；实质性的")
        )
        XCTAssertTrue(
            StudyWindowView.localVocabularyAnswerMatches("分配时间", expectedMeaning: "分配；拨出")
        )
        XCTAssertFalse(
            StudyWindowView.localVocabularyAnswerMatches("取消", expectedMeaning: "分配；拨出")
        )
    }

    func testFlashcardAdvanceFlowUsesOneActionForButtonsAndKeys() {
        XCTAssertEqual(
            FlashcardReviewFlow01.advanceAction(
                isBusy: false,
                hasJudgment: false,
                isCorrect: nil,
                hasCompletedCorrection: false,
                answer: "混乱",
                correction: ""
            ),
            .submitAnswer
        )
        XCTAssertEqual(
            FlashcardReviewFlow01.advanceAction(
                isBusy: false,
                hasJudgment: true,
                isCorrect: false,
                hasCompletedCorrection: false,
                answer: "",
                correction: "混乱"
            ),
            .confirmCorrection
        )
        XCTAssertEqual(
            FlashcardReviewFlow01.advanceAction(
                isBusy: false,
                hasJudgment: true,
                isCorrect: true,
                hasCompletedCorrection: true,
                answer: "",
                correction: ""
            ),
            .nextCard
        )
    }

    func testFlashcardAdvanceFlowSkipsEmptyAnswerButBlocksBusySteps() {
        XCTAssertEqual(
            FlashcardReviewFlow01.advanceAction(
                isBusy: false,
                hasJudgment: false,
                isCorrect: nil,
                hasCompletedCorrection: false,
                answer: "  ",
                correction: ""
            ),
            .skipCard
        )
        XCTAssertEqual(
            FlashcardReviewFlow01.advanceAction(
                isBusy: true,
                hasJudgment: true,
                isCorrect: true,
                hasCompletedCorrection: true,
                answer: "",
                correction: ""
            ),
            .none
        )
    }

    func testEnumerationCommaAloneMarksWordAsUnknown() {
        XCTAssertTrue(FlashcardReviewFlow01.isUnknownAnswer("、"))
        XCTAssertTrue(FlashcardReviewFlow01.isUnknownAnswer("  、  "))
        XCTAssertFalse(FlashcardReviewFlow01.isUnknownAnswer("/"))
        XCTAssertFalse(FlashcardReviewFlow01.isUnknownAnswer("、、"))
        XCTAssertFalse(FlashcardReviewFlow01.isUnknownAnswer("混乱、混沌"))
    }

    func testVocabularySpeechUsesExpectedEnglishVoicesAndSafeRates() {
        XCTAssertEqual(VocabularySpeechAccent01.british.languageCode, "en-GB")
        XCTAssertEqual(VocabularySpeechAccent01.british.preferredVoiceName, "Daniel")
        XCTAssertEqual(VocabularySpeechAccent01.american.languageCode, "en-US")
        XCTAssertEqual(VocabularySpeechAccent01.american.preferredVoiceName, "Samantha")
        XCTAssertEqual(
            VocabularySpeechService01.normalizedRate(0),
            VocabularySpeechService01.minimumRate
        )
        XCTAssertEqual(
            VocabularySpeechService01.normalizedRate(1),
            VocabularySpeechService01.maximumRate
        )
    }

    func testVocabularyAutoSpeechOnlyRunsOnceForCurrentWord() {
        XCTAssertTrue(
            VocabularyAutoSpeechGate01.shouldSpeak(
                wordID: "chaos",
                lastSpokenWordID: nil,
                isEnabled: true
            )
        )
        XCTAssertFalse(
            VocabularyAutoSpeechGate01.shouldSpeak(
                wordID: "chaos",
                lastSpokenWordID: "chaos",
                isEnabled: true
            )
        )
        XCTAssertFalse(
            VocabularyAutoSpeechGate01.shouldSpeak(
                wordID: "referee",
                lastSpokenWordID: "chaos",
                isEnabled: false
            )
        )
    }
}
