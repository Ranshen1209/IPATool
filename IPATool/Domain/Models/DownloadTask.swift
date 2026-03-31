import Foundation

enum DownloadTaskStatus: String, Sendable, Codable, CaseIterable {
    case queued
    case resolvingLicense
    case preparingDownload
    case downloading
    case paused
    case verifying
    case rewritingIPA
    case completed
    case failed
    case cancelled

    nonisolated var displayTitle: String {
        switch self {
        case .queued:
            "Queued"
        case .resolvingLicense:
            "License"
        case .preparingDownload:
            "Preparing"
        case .downloading:
            "Downloading"
        case .paused:
            "Paused"
        case .verifying:
            "Verifying"
        case .rewritingIPA:
            "Rewriting"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    nonisolated var resumesAfterLaunch: Bool {
        switch self {
        case .queued, .preparingDownload, .downloading, .verifying, .rewritingIPA:
            true
        case .paused, .resolvingLicense, .completed, .failed, .cancelled:
            false
        }
    }

    nonisolated var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .queued, .resolvingLicense, .preparingDownload, .downloading, .paused, .verifying, .rewritingIPA:
            false
        }
    }
}

struct DownloadTaskRecord: Identifiable, Sendable, Equatable, Codable {
    let id: UUID
    var title: String
    var version: String
    var status: DownloadTaskStatus
    var progress: Double
    var bytesDownloaded: Int64
    var totalBytes: Int64
    var retryCount: Int
    var outputPath: String
    var cachePath: String
    var detailMessage: String
    var createdAt: Date
    var updatedAt: Date
}
