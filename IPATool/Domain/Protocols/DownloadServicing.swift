import Foundation

protocol DownloadServicing: Sendable {
    func taskHistory() async -> [DownloadTaskRecord]
    func enqueueDownload(for version: AppVersion, session: AppSession, settings: AppSettingsSnapshot) async throws -> DownloadTaskRecord
    func cancelDownload(id: UUID) async
    func pauseDownload(id: UUID) async
    func pauseAuthenticatedDownloads() async -> Int
    func retryDownload(id: UUID, session: AppSession, settings: AppSettingsSnapshot) async throws
    func deleteDownload(id: UUID) async
}
