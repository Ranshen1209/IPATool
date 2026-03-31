import Foundation

struct ChunkedDownloadRepository: DownloadServicing {
    let manager: ChunkedDownloadManager

    func taskHistory() async -> [DownloadTaskRecord] {
        await manager.snapshot()
    }

    func enqueueDownload(for version: AppVersion, session: AppSession, settings: AppSettingsSnapshot) async throws -> DownloadTaskRecord {
        try await manager.enqueue(version: version, session: session, settings: settings)
    }

    func cancelDownload(id: UUID) async {
        await manager.cancel(id: id)
    }

    func pauseDownload(id: UUID) async {
        await manager.pause(id: id)
    }

    func pauseAuthenticatedDownloads() async -> Int {
        await manager.pauseAuthenticatedDownloads()
    }

    func retryDownload(id: UUID, session: AppSession, settings: AppSettingsSnapshot) async throws {
        try await manager.retry(id: id, session: session, settings: settings)
    }

    func deleteDownload(id: UUID) async {
        await manager.delete(id: id)
    }
}
