import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [StudyTask] = []

    private static let lastPlanDateAdvanceKey = "CET6DesktopWidget.lastPlanDateAdvance"
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL = TaskStore.defaultFileURL()) {
        self.fileURL = fileURL
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        load()
    }

    var todayTasks: [StudyTask] {
        let today = DateKey.today()
        return tasks.filter { $0.date == today }
    }

    func todayTasks(for goalID: String) -> [StudyTask] {
        todayTasks.filter { $0.goalID == goalID }
    }

    func task(for block: ScheduleBlock, goalID: String, planID: String?) -> StudyTask? {
        let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return tasks.first(where: {
            $0.date == block.dateKey &&
            $0.title == title &&
            $0.goalID == goalID &&
            $0.planID == planID
        })
    }

    func resolvedPlanBlocks(_ blocks: [ScheduleBlock], goalID: String, planID: String?) -> [ScheduleBlock] {
        var taskQueuesByTitle: [String: [StudyTask]] = [:]
        for task in tasks where task.source == "plan" && task.goalID == goalID && task.planID == planID {
            taskQueuesByTitle[normalizedTitle(task.title), default: []].append(task)
        }

        for key in taskQueuesByTitle.keys {
            taskQueuesByTitle[key]?.sort { lhs, rhs in
                if lhs.date == rhs.date { return lhs.title < rhs.title }
                return lhs.date < rhs.date
            }
        }

        return blocks.map { block in
            let key = normalizedTitle(block.title)
            guard var queue = taskQueuesByTitle[key], !queue.isEmpty else {
                return block
            }

            let task: StudyTask
            if let exactDateIndex = queue.firstIndex(where: { $0.date == block.dateKey }) {
                task = queue.remove(at: exactDateIndex)
            } else {
                task = queue.removeFirst()
            }
            taskQueuesByTitle[key] = queue
            return block.replacingDateKey(task.date)
        }
    }

    func addTaskForToday(
        _ title: String,
        goalID: String = GoalPlanStore01.defaultGoalID,
        goalTitle: String = GoalPlanStore01.defaultGoalTitle
    ) {
        addTask(title, date: DateKey.today(), goalID: goalID, goalTitle: goalTitle)
    }

    func addTask(
        _ title: String,
        date: String,
        goalID: String = GoalPlanStore01.defaultGoalID,
        goalTitle: String = GoalPlanStore01.defaultGoalTitle,
        planID: String? = nil
    ) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard !tasks.contains(where: { $0.date == date && $0.title == trimmedTitle && $0.goalID == goalID && $0.planID == planID }) else { return }

        tasks.append(StudyTask(date: date, title: trimmedTitle, goalID: goalID, goalTitle: goalTitle, planID: planID))
        save()
    }

    func syncPlanTasks(_ blocks: [ScheduleBlock], goal: GoalPlan, plan: GoalPlanSheet) {
        var existingTasksByTitle: [String: [StudyTask]] = [:]

        for task in tasks where task.source == "plan" && task.goalID == goal.id && task.planID == plan.id {
            existingTasksByTitle[normalizedTitle(task.title), default: []].append(task)
        }

        for key in existingTasksByTitle.keys {
            existingTasksByTitle[key]?.sort { lhs, rhs in
                if lhs.date == rhs.date { return lhs.title < rhs.title }
                return lhs.date < rhs.date
            }
        }

        tasks.removeAll { $0.source == "plan" && $0.goalID == goal.id && $0.planID == plan.id }

        for block in blocks {
            let trimmedTitle = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }

            let titleKey = normalizedTitle(trimmedTitle)
            let existing = popFirstTask(from: &existingTasksByTitle, key: titleKey)
            let targetDate = targetDate(forPlannedDate: block.dateKey, existing: existing)

            if !tasks.contains(where: { $0.date == targetDate && $0.title == trimmedTitle && $0.goalID == goal.id && $0.planID == plan.id }) {
                tasks.append(
                    StudyTask(
                        id: existing?.id ?? UUID(),
                        date: targetDate,
                        title: trimmedTitle,
                        isDone: existing?.isDone ?? false,
                        source: "plan",
                        goalID: goal.id,
                        goalTitle: goal.title,
                        planID: plan.id,
                        completedAt: existing?.completedAt
                    )
                )
            }
        }

        save()
    }

    func refreshPlanTasks(from goals: [GoalPlan], scheduleProvider: (GoalPlanSheet) -> [ScheduleBlock]) {
        for goal in goals {
            for plan in goal.plans {
                syncPlanTasks(scheduleProvider(plan), goal: goal, plan: plan)
            }
        }
    }

    func advancePlanDatesIfNeeded(from goals: [GoalPlan]) {
        let today = DateKey.today()
        let lastAdvancedDate = UserDefaults.standard.string(forKey: Self.lastPlanDateAdvanceKey)

        guard lastAdvancedDate != today else { return }

        var didChange = false
        for goal in goals {
            for plan in goal.plans {
                didChange = carryOverduePlanTasksToToday(goal: goal, plan: plan) || didChange
            }
        }

        UserDefaults.standard.set(today, forKey: Self.lastPlanDateAdvanceKey)
        if didChange {
            save()
        }
    }

    func toggleDone(for block: ScheduleBlock, goal: GoalPlan, plan: GoalPlanSheet) {
        let trimmedTitle = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let task = task(for: block, goalID: goal.id, planID: plan.id),
           let index = tasks.firstIndex(where: { $0.id == task.id }) {
            tasks[index].isDone.toggle()
            tasks[index].completedAt = tasks[index].isDone ? DateKey.today() : nil
        } else {
            tasks.append(
                StudyTask(
                    date: block.dateKey,
                    title: trimmedTitle,
                    isDone: true,
                    source: "plan",
                    goalID: goal.id,
                    goalTitle: goal.title,
                    planID: plan.id,
                    completedAt: DateKey.today()
                )
            )
        }

        save()
    }

    func toggleDone(_ task: StudyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
        tasks[index].completedAt = tasks[index].isDone ? DateKey.today() : nil
        save()
    }

    func removeTasks(for goalID: String) {
        tasks.removeAll { $0.goalID == goalID }
        save()
    }

    func load() {
        do {
            try ensureDataFileExists()
            let data = try Data(contentsOf: fileURL)
            tasks = try decoder.decode([StudyTask].self, from: data)
            migrateLegacyGoalFields()
            migrateCompletedDates()
            migrateOverdueTasks()
        } catch {
            tasks = TaskStore.seedTasks()
            save()
        }
    }

    private func save() {
        do {
            let data = try encoder.encode(tasks)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("Failed to save tasks: \(error.localizedDescription)")
        }
    }

    private func ensureDataFileExists() throws {
        let folderURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        guard !FileManager.default.fileExists(atPath: fileURL.path) else { return }
        tasks = TaskStore.seedTasks()
        save()
    }

    private func migrateOverdueTasks() {
        var didChange = false

        for index in tasks.indices where !tasks[index].isDone && tasks[index].source != "plan" {
            while DateKey.isBeforeToday(tasks[index].date), let nextDate = DateKey.dayAfter(tasks[index].date) {
                tasks[index].date = nextDate
                didChange = true
            }
        }

        if didChange {
            save()
        }
    }

    private func migrateLegacyGoalFields() {
        var didChange = false

        for index in tasks.indices {
            if tasks[index].goalID.isEmpty {
                tasks[index].goalID = GoalPlanStore01.defaultGoalID
                didChange = true
            }
            if tasks[index].goalTitle.isEmpty {
                tasks[index].goalTitle = GoalPlanStore01.defaultGoalTitle
                didChange = true
            }
        }

        if didChange {
            save()
        }
    }

    private func migrateCompletedDates() {
        var didChange = false
        let today = DateKey.today()

        for index in tasks.indices where tasks[index].isDone && tasks[index].completedAt == nil {
            tasks[index].completedAt = DateKey.isBeforeToday(tasks[index].date) ? tasks[index].date : today
            didChange = true
        }

        if didChange {
            save()
        }
    }

    private func carryOverduePlanTasksToToday(goal: GoalPlan, plan: GoalPlanSheet) -> Bool {
        var didChange = false
        let today = DateKey.today()

        for index in tasks.indices where tasks[index].source == "plan" && tasks[index].goalID == goal.id && tasks[index].planID == plan.id {
            if tasks[index].isDone {
                if let completedAt = tasks[index].completedAt, tasks[index].date != completedAt {
                    tasks[index].date = completedAt
                    didChange = true
                }
            } else if DateKey.isBeforeToday(tasks[index].date), tasks[index].date != today {
                tasks[index].date = today
                didChange = true
            }
        }

        return didChange
    }

    private func targetDate(forPlannedDate plannedDate: String, existing: StudyTask?) -> String {
        if existing?.isDone == true {
            return existing?.completedAt ?? existing?.date ?? plannedDate
        }

        return DateKey.isBeforeToday(plannedDate) ? DateKey.today() : plannedDate
    }

    private func normalizedTitle(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func popFirstTask(from dictionary: inout [String: [StudyTask]], key: String) -> StudyTask? {
        guard var queue = dictionary[key], !queue.isEmpty else { return nil }
        let task = queue.removeFirst()
        dictionary[key] = queue
        return task
    }

    private static func defaultFileURL() -> URL {
        let folderURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("CET-6", isDirectory: true)
            .appendingPathComponent("CET6DesktopWidget01", isDirectory: true)
            .appendingPathComponent("Data", isDirectory: true)
        return folderURL.appendingPathComponent("study_tasks.json")
    }

    private static func seedTasks() -> [StudyTask] {
        []
    }
}
