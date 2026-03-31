import Foundation

enum AppErrorSeverity: String, Sendable, Codable {
    case info
    case warning
    case error
}

struct AppError: Error, LocalizedError, Identifiable, Sendable, Equatable {
    let id: UUID
    let title: String
    let message: String
    let recoverySuggestion: String
    let severity: AppErrorSeverity

    init(
        id: UUID = UUID(),
        title: String,
        message: String,
        recoverySuggestion: String,
        severity: AppErrorSeverity = .error
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.recoverySuggestion = recoverySuggestion
        self.severity = severity
    }

    var errorDescription: String? {
        message
    }

    var failureReason: String? {
        title
    }

    var recoverySuggestionText: String? {
        recoverySuggestion
    }
}
