import Foundation
import XCTest
@testable import IPATool

@MainActor
final class DownloadManagerRangeValidationTests: XCTestCase {
    private struct PersistedTaskEnvelope: Codable {
        var record: DownloadTaskRecord
        var version: AppVersion?
    }

    func testResumePendingTaskFailsWhenRangeResponseIsNotPartialContent() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("Cache", isDirectory: true)
        let persistenceURL = cacheRoot.appendingPathComponent("tasks.json")
        let outputURL = downloads.appendingPathComponent("Remote.ipa")
        let cacheDirectory = cacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let version = AppVersion(
            id: "remote-version",
            appID: "123456789",
            displayName: "Remote App",
            bundleIdentifier: "com.ipatool.remote",
            version: "1.0",
            externalVersionID: "1",
            expectedMD5: nil,
            metadataValues: [:],
            signaturePayload: Data("signature".utf8).base64EncodedString(),
            downloadURL: URL(string: "https://example.com/app.ipa")
        )

        let record = DownloadTaskRecord(
            id: UUID(),
            title: "Remote App",
            version: "1.0",
            status: .downloading,
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: 0,
            retryCount: 0,
            outputPath: outputURL.path,
            cachePath: cacheDirectory.path,
            detailMessage: "Recovering after relaunch.",
            createdAt: .now,
            updatedAt: .now
        )

        let payload = [PersistedTaskEnvelope(record: record, version: version)]
        try JSONEncoder().encode(payload).write(to: persistenceURL, options: .atomic)

        let logger = TestLogger()
        let credentials = InMemoryCredentialStore()
        try await credentials.saveCredential(.init(appleID: "tester@ipatool.local", password: "secret"))
        let processor = RecordingIPAProcessor()
        let session = AppSession(
            appleID: "tester@ipatool.local",
            displayName: "Tester",
            dsid: "1",
            guid: "GUID",
            storeFront: "143441",
            authHeaders: ["X-Token": "token"]
        )
        let httpClient = SequencedHTTPClient(
            responses: [
                HTTPResponse(
                    request: HTTPRequest(url: URL(string: "https://example.com/app.ipa")!, method: .head),
                    statusCode: 200,
                    headers: ["Content-Length": "8"],
                    body: Data()
                ),
                HTTPResponse(
                    request: HTTPRequest(url: URL(string: "https://example.com/app.ipa")!, method: .get),
                    statusCode: 200,
                    headers: ["Content-Length": "8"],
                    body: Data(repeating: 0xAB, count: 8)
                ),
            ]
        )

        let manager = ChunkedDownloadManager(
            persistenceURL: persistenceURL,
            httpClient: httpClient,
            logger: logger,
            credentialStore: credentials,
            ipaProcessor: processor,
            fileManager: fileManager
        )

        await manager.loadPersistedTasks()
        await manager.attachSessionIfNeeded(session)
        await manager.resumePendingTasks(
            settings: AppSettingsSnapshot(
                outputDirectoryPath: downloads.path,
                cacheDirectoryPath: cacheRoot.path,
                maximumConcurrentChunks: 1,
                chunkSizeInMegabytes: 1
            )
        )

        await waitUntil(timeout: 10) {
            let task = await manager.snapshot().first
            return await MainActor.run { task?.status == .failed }
        }

        let restored = await manager.snapshot().first
        let processed = await processor.snapshot()
        let restoredStatus = restored?.status
        let detailMessage = restored?.detailMessage
        XCTAssertEqual(restoredStatus, .failed)
        XCTAssertTrue(detailMessage?.contains("HTTP 206") == true)
        XCTAssertFalse(fileManager.fileExists(atPath: outputURL.path))
        XCTAssertTrue(processed.isEmpty)
    }
}
