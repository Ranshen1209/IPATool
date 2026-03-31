import Foundation

protocol LoggingServicing: Sendable {
    func append(level: LogLevel, category: String, message: String) async
    func snapshot() async -> [LogEntry]
    func clear() async
}
