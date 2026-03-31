import Foundation
import XCTest
@testable import IPATool

@MainActor
final class ChunkedDownloadManagerTests: XCTestCase {
    private struct PersistedTaskEnvelope: Codable {
        var record: DownloadTaskRecord
        var version: AppVersion?
    }

    func testResumePendingTaskRestoresPersistedVersionContext() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let downloads = root.appendingPathComponent("Downloads", isDirectory: true)
        let cacheRoot = root.appendingPathComponent("Cache", isDirectory: true)
        let persistenceURL = cacheRoot.appendingPathComponent("tasks.json")
        let sourceURL = root.appendingPathComponent("fixture.ipa")
        let outputURL = downloads.appendingPathComponent("Recovered.ipa")
        let cacheDirectory = cacheRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)

        try fileManager.createDirectory(at: downloads, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: 512 * 1024).write(to: sourceURL)

        let version = AppVersion(
            id: "resume-version",
            appID: "123456789",
            displayName: "Recovered App",
            bundleIdentifier: "com.ipatool.recovered",
            version: "1.0",
            externalVersionID: "1",
            expectedMD5: nil,
            metadataValues: [:],
            signaturePayload: Data("signature".utf8).base64EncodedString(),
            downloadURL: sourceURL
        )

        let record = DownloadTaskRecord(
            id: UUID(),
            title: "Recovered App",
            version: "1.0",
            status: .downloading,
            progress: 0.2,
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
        let data = try JSONEncoder().encode(payload)
        try data.write(to: persistenceURL, options: .atomic)

        let logger = TestLogger()
        let credentials = InMemoryCredentialStore()
        try await credentials.saveCredential(.init(appleID: "tester@ipatool.local", password: "secret"))
        let processor = RecordingIPAProcessor()

        let manager = ChunkedDownloadManager(
            persistenceURL: persistenceURL,
            httpClient: TestHTTPClient(),
            logger: logger,
            credentialStore: credentials,
            ipaProcessor: processor,
            fileManager: fileManager
        )

        await manager.loadPersistedTasks()
        await manager.resumePendingTasks(
            settings: AppSettingsSnapshot(
                outputDirectoryPath: downloads.path,
                cacheDirectoryPath: cacheRoot.path,
                maximumConcurrentChunks: 2,
                chunkSizeInMegabytes: 1
            )
        )

        await waitUntil(timeout: 10) {
            let task = await manager.snapshot().first
            return await MainActor.run { task?.status == .completed }
        }

        let restored = await manager.snapshot().first
        let restoredStatus = restored?.status
        XCTAssertEqual(restoredStatus, .completed)
        XCTAssertTrue(fileManager.fileExists(atPath: outputURL.path))

        let processed = await processor.snapshot()
        XCTAssertEqual(processed, [outputURL])
    }
}
