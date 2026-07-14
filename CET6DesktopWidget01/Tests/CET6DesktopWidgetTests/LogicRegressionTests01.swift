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
}
