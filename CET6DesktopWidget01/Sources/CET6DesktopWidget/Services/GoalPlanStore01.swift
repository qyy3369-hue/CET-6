import Foundation

enum GoalPlanStore01 {
    static let defaultGoalID = "cet6-default-goal"
    static let defaultGoalTitle = "CET-6 备考"
    private static let selectedGoalKey = "CET6DesktopWidget.selectedGoalID"
    private static let selectedPlanKey = "CET6DesktopWidget.selectedPlanID"

    static func load(defaultPlanText: String) -> [GoalPlan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let goals = seedGoals(defaultPlanText: defaultPlanText)
            try? save(goals)
            return goals
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let goals = try decoder.decode([GoalPlan].self, from: data)
            if goals.isEmpty {
                let seededGoals = seedGoals(defaultPlanText: defaultPlanText)
                try? save(seededGoals)
                return seededGoals
            }
            let normalizedGoals = ensureEveryGoalHasPlan(goals, defaultPlanText: defaultPlanText)
            if normalizedGoals != goals {
                try? save(normalizedGoals)
            }
            return normalizedGoals
        } catch {
            let goals = seedGoals(defaultPlanText: defaultPlanText)
            try? save(goals)
            return goals
        }
    }

    static func save(_ goals: [GoalPlan]) throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        let data = try encoder.encode(goals)
        try data.write(to: fileURL, options: .atomic)
    }

    static func loadSelectedGoalID() -> String? {
        UserDefaults.standard.string(forKey: selectedGoalKey)
    }

    static func saveSelectedGoalID(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedGoalKey)
        NotificationCenter.default.post(name: .goalSelectionDidChange, object: nil, userInfo: ["goalID": id])
    }

    static func loadSelectedPlanID() -> String? {
        UserDefaults.standard.string(forKey: selectedPlanKey)
    }

    static func saveSelectedPlanID(_ id: String) {
        UserDefaults.standard.set(id, forKey: selectedPlanKey)
    }

    private static func seedGoals(defaultPlanText: String) -> [GoalPlan] {
        let legacyPlan = PlanStore.load() ?? defaultPlanText
        return [
            GoalPlan(
                id: defaultGoalID,
                title: defaultGoalTitle,
                mode: "考试冲刺",
                focus: "保留原来的 CET-6 备考能力，也可以继续拆分词汇、听力、阅读、写作计划。",
                plans: [
                    GoalPlanSheet(
                        id: "cet6-default-plan",
                        title: "计划表01",
                        planText: legacyPlan
                    )
                ]
            ),
            GoalPlan(
                title: "身体与作息",
                mode: "生活习惯",
                focus: "把运动、睡眠、饮食和精力恢复拆成每天能执行的小任务。",
                plans: [
                    GoalPlanSheet(
                        title: "计划表01",
                        planText: """
                        第1天 07:40-08:10 快走或拉伸 30 分钟
                        第1天 23:20-23:40 睡前整理，关闭电子屏幕
                        第2天 18:30-19:10 力量训练 3 组，记录感受
                        第3天 21:30-21:50 复盘作息，调整明天起床时间
                        """
                    )
                ]
            ),
            GoalPlan(
                title: "个人成长",
                mode: "长期项目",
                focus: "适合读书、技能练习、作品集、证书、职业准备等非考试目标。",
                plans: [
                    GoalPlanSheet(
                        title: "计划表01",
                        planText: """
                        第1天 20:00-20:40 阅读或学习一个核心概念
                        第2天 20:00-20:45 做一份输出笔记
                        第3天 20:00-21:00 完成一个小作品或练习
                        """
                    )
                ]
            )
        ]
    }

    static func ensureEveryGoalHasPlan(_ goals: [GoalPlan], defaultPlanText: String) -> [GoalPlan] {
        goals.map { goal in
            guard goal.plans.isEmpty else { return goal }

            var repairedGoal = goal
            repairedGoal.plans = [
                GoalPlanSheet(
                    title: "计划表01",
                    planText: defaultPlanText
                )
            ]
            return repairedGoal
        }
    }

    private static var fileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
            .appendingPathComponent("goal_plans01.json")
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}

extension Notification.Name {
    static let goalSelectionDidChange = Notification.Name("GoalPlanStore01.goalSelectionDidChange")
}
