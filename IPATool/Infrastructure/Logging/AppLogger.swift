import Foundation
import OSLog

actor AppLogger: LoggingServicing {
    private let osLogger: Logger
    private let maximumEntryCount: Int
    private var entries: [LogEntry]
    private var includesDebugEntries: Bool

    init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.ranshen.IPATool",
        category: String = "app",
        maximumEntryCount: Int = 500,
        seedEntries: [LogEntry] = [],
        includesDebugEntries: Bool = true
    ) {
        self.osLogger = Logger(subsystem: subsystem, category: category)
        self.maximumEntryCount = maximumEntryCount
        self.entries = seedEntries
        self.includesDebugEntries = includesDebugEntries
    }

    func append(level: LogLevel, category: String, message: String) {
        guard includesDebugEntries || level != .debug else { return }

        let entry = LogEntry(level: level, category: category, message: message)
        entries.insert(entry, at: 0)
        if entries.count > maximumEntryCount {
            entries.removeLast(entries.count - maximumEntryCount)
        }

        switch level {
        case .debug:
            osLogger.debug("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .info:
            osLogger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .notice:
            osLogger.notice("[\(category, privacy: .public)] \(message, privacy: .public)")
        case .error:
            osLogger.error("[\(category, privacy: .public)] \(message, privacy: .public)")
        }
    }

    func snapshot() -> [LogEntry] {
        entries
    }

    func clear() {
        entries.removeAll(keepingCapacity: true)
        osLogger.notice("[logs] Cleared in-memory log entries.")
    }

    func setDebugLoggingEnabled(_ isEnabled: Bool) {
        includesDebugEntries = isEnabled
        if !isEnabled {
            entries.removeAll { $0.level == .debug }
        }
    }
}
