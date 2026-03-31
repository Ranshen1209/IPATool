import Foundation

enum SandboxBookmarkError: LocalizedError {
    case encodingFailed
    case resolutionFailed

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            "The selected folder could not be saved as a security-scoped bookmark."
        case .resolutionFailed:
            "The saved folder bookmark could not be resolved."
        }
    }
}

protocol SandboxBookmarkStoring: Sendable {
    func saveBookmark(for url: URL, key: String) throws
    func resolveBookmark(for key: String) throws -> URL?
    func removeBookmark(for key: String)
}

final class UserDefaultsSandboxBookmarkStore: SandboxBookmarkStoring, @unchecked Sendable {
    private let fileURL: URL
    private let fileManager: FileManager
    private let encoder = PropertyListEncoder()
    private let decoder = PropertyListDecoder()

    init(
        fileURL: URL = AppStorageLocations.bookmarksFileURL(),
        fileManager: FileManager = .default
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
    }

    func saveBookmark(for url: URL, key: String) throws {
        let data: Data
        do {
            data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        } catch {
            throw SandboxBookmarkError.encodingFailed
        }

        var bookmarks = loadBookmarks()
        bookmarks[key] = data
        try persistBookmarks(bookmarks)
    }

    func resolveBookmark(for key: String) throws -> URL? {
        guard let data = loadBookmarks()[key] else {
            return nil
        }

        var isStale = false
        do {
            let resolvedURL = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                try? saveBookmark(for: resolvedURL, key: key)
            }
            return resolvedURL
        } catch {
            throw SandboxBookmarkError.resolutionFailed
        }
    }

    func removeBookmark(for key: String) {
        var bookmarks = loadBookmarks()
        bookmarks.removeValue(forKey: key)
        try? persistBookmarks(bookmarks)
    }

    private func loadBookmarks() -> [String: Data] {
        guard let data = try? Data(contentsOf: fileURL) else {
            return [:]
        }
        return (try? decoder.decode([String: Data].self, from: data)) ?? [:]
    }

    private func persistBookmarks(_ bookmarks: [String: Data]) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try encoder.encode(bookmarks)
        try data.write(to: fileURL, options: [.atomic])
    }
}
