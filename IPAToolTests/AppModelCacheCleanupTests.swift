import Foundation
import XCTest
@testable import IPATool

@MainActor
final class AppModelCacheCleanupTests: XCTestCase {
    func testClearCacheDirectoryPreservesPersistedTaskFile() throws {
        let container = AppContainer()
        let model = AppModel(container: container)

        let fileManager = FileManager.default
        let cacheRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tasksFile = cacheRoot.appendingPathComponent("tasks.json")
        let chunkDirectory = cacheRoot.appendingPathComponent("chunk-cache", isDirectory: true)
        let stagedIPA = cacheRoot.appendingPathComponent("staged.ipa")

        try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: chunkDirectory, withIntermediateDirectories: true)
        try Data("persisted".utf8).write(to: tasksFile, options: .atomic)
        try Data("chunk".utf8).write(to: chunkDirectory.appendingPathComponent("part_0"), options: .atomic)
        try Data("ipa".utf8).write(to: stagedIPA, options: .atomic)

        container.settings.cacheDirectoryPath = cacheRoot.path

        model.clearCacheDirectory()

        XCTAssertTrue(fileManager.fileExists(atPath: tasksFile.path))
        XCTAssertFalse(fileManager.fileExists(atPath: chunkDirectory.path))
        XCTAssertFalse(fileManager.fileExists(atPath: stagedIPA.path))
    }
}
