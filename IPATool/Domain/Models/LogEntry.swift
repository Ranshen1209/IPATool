import Foundation

enum LogLevel: String, Sendable, Codable, CaseIterable {
    case debug
    case info
    case notice
    case error
}

struct LogEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let category: String
    let message: String

    nonisolated init(
        id: UUID = UUID(),
        date: Date = .now,
        level: LogLevel,
        category: String,
        message: String
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }
}
