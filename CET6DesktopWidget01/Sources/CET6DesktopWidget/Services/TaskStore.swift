import Foundation

@MainActor
final class TaskStore: ObservableObject {
    @Published private(set) var tasks: [StudyTask] = []

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

    func task(for block: ScheduleBlock) -> StudyTask? {
        tasks.first { $0.date == block.dateKey && $0.title == block.title }
    }

    func addTaskForToday(_ title: String) {
        addTask(title, date: DateKey.today())
    }

    func addTask(_ title: String, date: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }
        guard !tasks.contains(where: { $0.date == date && $0.title == trimmedTitle }) else { return }

        tasks.append(StudyTask(date: date, title: trimmedTitle))
        save()
    }

    func syncPlanTasks(_ blocks: [ScheduleBlock]) {
        var doneStateByKey: [String: Bool] = [:]
        for task in tasks where task.source == "plan" {
            doneStateByKey["\(task.date)|\(task.title)"] = task.isDone
        }

        tasks.removeAll { $0.source == "plan" }

        for block in blocks {
            let trimmedTitle = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else { continue }

            if !tasks.contains(where: { $0.date == block.dateKey && $0.title == trimmedTitle }) {
                let key = "\(block.dateKey)|\(trimmedTitle)"
                tasks.append(StudyTask(date: block.dateKey, title: trimmedTitle, isDone: doneStateByKey[key] ?? false, source: "plan"))
            }
        }

        save()
    }

    func toggleDone(for block: ScheduleBlock) {
        let trimmedTitle = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return }

        if let index = tasks.firstIndex(where: { $0.date == block.dateKey && $0.title == trimmedTitle }) {
            tasks[index].isDone.toggle()
        } else {
            tasks.append(StudyTask(date: block.dateKey, title: trimmedTitle, isDone: true, source: "plan"))
        }

        save()
    }

    func toggleDone(_ task: StudyTask) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        tasks[index].isDone.toggle()
        save()
    }

    func load() {
        do {
            try ensureDataFileExists()
            let data = try Data(contentsOf: fileURL)
            tasks = try decoder.decode([StudyTask].self, from: data)
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

        for index in tasks.indices where !tasks[index].isDone {
            while DateKey.isBeforeToday(tasks[index].date), let nextDate = DateKey.dayAfter(tasks[index].date) {
                tasks[index].date = nextDate
                didChange = true
            }
        }

        if didChange {
            save()
        }
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
