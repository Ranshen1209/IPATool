import XCTest
@testable import IPATool

final class DownloadTaskStatusTests: XCTestCase {
    func testResumesAfterLaunchMatchesExpectedStatuses() {
        XCTAssertTrue(DownloadTaskStatus.queued.resumesAfterLaunch)
        XCTAssertTrue(DownloadTaskStatus.preparingDownload.resumesAfterLaunch)
        XCTAssertTrue(DownloadTaskStatus.downloading.resumesAfterLaunch)
        XCTAssertTrue(DownloadTaskStatus.verifying.resumesAfterLaunch)
        XCTAssertTrue(DownloadTaskStatus.rewritingIPA.resumesAfterLaunch)

        XCTAssertFalse(DownloadTaskStatus.resolvingLicense.resumesAfterLaunch)
        XCTAssertFalse(DownloadTaskStatus.completed.resumesAfterLaunch)
        XCTAssertFalse(DownloadTaskStatus.failed.resumesAfterLaunch)
        XCTAssertFalse(DownloadTaskStatus.cancelled.resumesAfterLaunch)
    }

    func testTerminalStatusMatchesExpectedStatuses() {
        XCTAssertTrue(DownloadTaskStatus.completed.isTerminal)
        XCTAssertTrue(DownloadTaskStatus.failed.isTerminal)
        XCTAssertTrue(DownloadTaskStatus.cancelled.isTerminal)
        XCTAssertFalse(DownloadTaskStatus.downloading.isTerminal)
    }
}
