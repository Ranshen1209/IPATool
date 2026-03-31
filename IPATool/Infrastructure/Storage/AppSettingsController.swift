import Foundation
import Observation

@Observable
@MainActor
final class AppSettingsController {
    var outputDirectoryPath: String
    var cacheDirectoryPath: String
    var maximumConcurrentChunks: Int
    var chunkSizeInMegabytes: Int

    private let store: AppSettingsStoring
    private let bookmarkStore: SandboxBookmarkStoring

    init(
        snapshot: AppSettingsSnapshot = .default,
        store: AppSettingsStoring,
        bookmarkStore: SandboxBookmarkStoring
    ) {
        self.outputDirectoryPath = snapshot.outputDirectoryPath
        self.cacheDirectoryPath = snapshot.cacheDirectoryPath
        self.maximumConcurrentChunks = snapshot.maximumConcurrentChunks
        self.chunkSizeInMegabytes = snapshot.chunkSizeInMegabytes
        self.store = store
        self.bookmarkStore = bookmarkStore
    }

    var snapshot: AppSettingsSnapshot {
        AppSettingsSnapshot(
            outputDirectoryPath: outputDirectoryPath,
            cacheDirectoryPath: cacheDirectoryPath,
            maximumConcurrentChunks: maximumConcurrentChunks,
            chunkSizeInMegabytes: chunkSizeInMegabytes
        )
    }

    func persist() throws {
        try store.save(snapshot)
    }

    func saveBookmark(for url: URL, key: String) throws {
        try bookmarkStore.saveBookmark(for: url, key: key)
    }

    func resolveBookmark(for key: String) throws -> URL? {
        try bookmarkStore.resolveBookmark(for: key)
    }
}
