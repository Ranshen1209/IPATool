import Foundation

final class DownloadRecoveryCatalog: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var versionsByTaskID: [UUID: AppVersion] = [:]

    nonisolated init() {}

    nonisolated func store(version: AppVersion, for taskID: UUID) {
        lock.lock()
        versionsByTaskID[taskID] = version
        lock.unlock()
    }

    nonisolated func version(for taskID: UUID) -> AppVersion? {
        lock.lock()
        defer { lock.unlock() }
        return versionsByTaskID[taskID]
    }

    nonisolated func removeVersion(for taskID: UUID) {
        lock.lock()
        versionsByTaskID.removeValue(forKey: taskID)
        lock.unlock()
    }
}
