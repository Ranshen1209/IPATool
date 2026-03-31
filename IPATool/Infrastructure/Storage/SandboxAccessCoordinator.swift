import Foundation

@MainActor
final class SandboxAccessCoordinator {
    private var activeURLs: [String: URL] = [:]

    func restoreAccess(using settings: AppSettingsController) throws -> [URL] {
        var restored: [URL] = []

        for key in [
            AppSettingsSnapshot.outputDirectoryBookmarkKey,
            AppSettingsSnapshot.cacheDirectoryBookmarkKey,
        ] {
            guard let url = try settings.resolveBookmark(for: key) else { continue }
            beginAccess(for: url)
            restored.append(url)
        }

        return restored
    }

    func replaceAccess(for key: String, with url: URL) {
        if let previous = activeURLs[key] {
            previous.stopAccessingSecurityScopedResource()
        }
        beginAccess(for: url, key: key)
    }

    deinit {
        for url in activeURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
    }

    private func beginAccess(for url: URL, key: String? = nil) {
        let started = url.startAccessingSecurityScopedResource()
        guard started else { return }
        activeURLs[key ?? url.path] = url
    }
}
