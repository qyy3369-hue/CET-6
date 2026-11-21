import Foundation

enum GoalPlanStore01 {
    static let defaultGoalID = "cet6-default-goal"
    static let defaultGoalTitle = "CET-6 备考"
    private static let selectedGoalKey = "CET6DesktopWidget.selectedGoalID"
    private static let selectedPlanKey = "CET6DesktopWidget.selectedPlanID"

    static func load(defaultPlanText: String) -> [GoalPlan] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            let goals = loadLegacyGoals()
            if !goals.isEmpty { try? save(goals) }
            return goals
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let goals = try decoder.decode([GoalPlan].self, from: data)
            let normalizedGoals = ensureEveryGoalHasPlan(goals, defaultPlanText: defaultPlanText)
            if normalizedGoals != goals {
                try? save(normalizedGoals)
            }
            return normalizedGoals
        } catch {
            let goals = loadLegacyGoals()
            if !goals.isEmpty { try? save(goals) }
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

    private static func loadLegacyGoals() -> [GoalPlan] {
        guard let planText = PlanStore.load(),
              !planText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        return [
            GoalPlan(
                id: defaultGoalID,
                title: defaultGoalTitle,
                mode: "考试冲刺",
                focus: "",
                plans: [GoalPlanSheet(id: "cet6-default-plan", title: "计划表01", planText: planText)]
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
