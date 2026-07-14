import Foundation

struct StudyTask: Codable, Identifiable, Equatable {
    var id: UUID
    var date: String
    var title: String
    var isDone: Bool
    var source: String
    var goalID: String
    var goalTitle: String
    var planID: String?
    var completedAt: String?

    init(
        id: UUID = UUID(),
        date: String,
        title: String,
        isDone: Bool = false,
        source: String = "manual",
        goalID: String = GoalPlanStore01.defaultGoalID,
        goalTitle: String = GoalPlanStore01.defaultGoalTitle,
        planID: String? = nil,
        completedAt: String? = nil
    ) {
        self.id = id
        self.date = date
        self.title = title
        self.isDone = isDone
        self.source = source
        self.goalID = goalID
        self.goalTitle = goalTitle
        self.planID = planID
        self.completedAt = completedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(String.self, forKey: .date)
        self.title = try container.decode(String.self, forKey: .title)
        self.isDone = try container.decode(Bool.self, forKey: .isDone)
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "manual"
        self.goalID = try container.decodeIfPresent(String.self, forKey: .goalID) ?? GoalPlanStore01.defaultGoalID
        self.goalTitle = try container.decodeIfPresent(String.self, forKey: .goalTitle) ?? GoalPlanStore01.defaultGoalTitle
        self.planID = try container.decodeIfPresent(String.self, forKey: .planID)
        self.completedAt = try container.decodeIfPresent(String.self, forKey: .completedAt)
    }
}
