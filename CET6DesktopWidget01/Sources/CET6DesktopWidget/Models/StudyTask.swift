import Foundation

struct StudyTask: Codable, Identifiable, Equatable {
    var id: UUID
    var date: String
    var title: String
    var isDone: Bool
    var source: String

    init(id: UUID = UUID(), date: String, title: String, isDone: Bool = false, source: String = "manual") {
        self.id = id
        self.date = date
        self.title = title
        self.isDone = isDone
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.date = try container.decode(String.self, forKey: .date)
        self.title = try container.decode(String.self, forKey: .title)
        self.isDone = try container.decode(Bool.self, forKey: .isDone)
        self.source = try container.decodeIfPresent(String.self, forKey: .source) ?? "manual"
    }
}
