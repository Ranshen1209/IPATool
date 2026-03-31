import Foundation

struct AppSettingsSnapshot: Codable, Sendable, Equatable {
    var outputDirectoryPath: String
    var cacheDirectoryPath: String
    var maximumConcurrentChunks: Int
    var chunkSizeInMegabytes: Int

    nonisolated static let `default` = AppSettingsSnapshot(
        outputDirectoryPath: "~/Downloads",
        cacheDirectoryPath: "~/Library/Caches/IPATool",
        maximumConcurrentChunks: 6,
        chunkSizeInMegabytes: 5
    )

    nonisolated static let outputDirectoryBookmarkKey = "outputDirectory"
    nonisolated static let cacheDirectoryBookmarkKey = "cacheDirectory"
}

protocol AppSettingsStoring: Sendable {
    func load() -> AppSettingsSnapshot
    func save(_ snapshot: AppSettingsSnapshot) throws
}

enum AppStorageLocations {
    static let directoryName = "IPATool"

    static func applicationSupportDirectory(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func settingsFileURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("settings.json", isDirectory: false)
    }

    static func bookmarksFileURL(fileManager: FileManager = .default) -> URL {
        applicationSupportDirectory(fileManager: fileManager)
            .appendingPathComponent("bookmarks.plist", isDirectory: false)
    }
}

final class UserDefaultsAppSettingsStore: AppSettingsStoring, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        fileURL: URL = AppStorageLocations.settingsFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func load() -> AppSettingsSnapshot {
        guard let data = try? Data(contentsOf: fileURL) else {
            return .default
        }

        if let snapshot = try? decoder.decode(AppSettingsSnapshot.self, from: data) {
            return snapshot
        }

        if let legacySnapshot = try? decoder.decode(LegacyAppSettingsSnapshot.self, from: data) {
            return AppSettingsSnapshot(
                outputDirectoryPath: legacySnapshot.outputDirectoryPath,
                cacheDirectoryPath: legacySnapshot.cacheDirectoryPath,
                maximumConcurrentChunks: legacySnapshot.maximumConcurrentChunks,
                chunkSizeInMegabytes: legacySnapshot.chunkSizeInMegabytes
            )
        }

        return .default
    }

    func save(_ snapshot: AppSettingsSnapshot) throws {
        try ensureParentDirectoryExists()
        let data = try encoder.encode(snapshot)
        try data.write(to: fileURL, options: [.atomic])
    }

    private func ensureParentDirectoryExists() throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}

private struct LegacyAppSettingsSnapshot: Codable {
    var outputDirectoryPath: String
    var cacheDirectoryPath: String
    var maximumConcurrentChunks: Int
    var chunkSizeInMegabytes: Int
    var shouldKeepVerboseLogs: Bool
}
