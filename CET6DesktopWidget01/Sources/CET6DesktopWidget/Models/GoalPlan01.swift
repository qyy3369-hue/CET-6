import Foundation

struct ScheduleBlock: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    let dateKey: String
    let timeLabel: String
    let title: String
    let note: String
    let category: String

    init(
        id: UUID = UUID(),
        dateKey: String,
        timeLabel: String,
        title: String,
        note: String,
        category: String
    ) {
        self.id = id
        self.dateKey = dateKey
        self.timeLabel = timeLabel
        self.title = title
        self.note = note
        self.category = category
    }

    var dateLabel: String {
        DateKey.displayLabel(for: dateKey)
    }

    func replacingDateKey(_ dateKey: String) -> ScheduleBlock {
        ScheduleBlock(
            id: id,
            dateKey: dateKey,
            timeLabel: timeLabel,
            title: title,
            note: note,
            category: category
        )
    }
}

struct GoalPlan: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var mode: String
    var focus: String
    var plans: [GoalPlanSheet]

    init(
        id: String = UUID().uuidString,
        title: String,
        mode: String,
        focus: String,
        plans: [GoalPlanSheet]
    ) {
        self.id = id
        self.title = title
        self.mode = mode
        self.focus = focus
        self.plans = plans
    }
}

struct GoalPlanSheet: Codable, Identifiable, Equatable {
    var id: String
    var title: String
    var planText: String
    var generatedSchedule: [ScheduleBlock]?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        title: String,
        planText: String,
        generatedSchedule: [ScheduleBlock]? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.planText = planText
        self.generatedSchedule = generatedSchedule
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
