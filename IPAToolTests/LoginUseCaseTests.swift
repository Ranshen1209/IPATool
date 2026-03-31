import XCTest
@testable import IPATool

@MainActor
final class LoginUseCaseTests: XCTestCase {
    func testExecuteReturnsSessionAndWritesLogs() async throws {
        let logger = TestLogger()
        let expectedSession = AppSession(
            appleID: "tester@ipatool.local",
            displayName: "Tester",
            dsid: "1234567890",
            guid: "ABCDEF012345",
            storeFront: "143441",
            authHeaders: [
                "X-Dsid": "1234567890",
                "iCloud-DSID": "1234567890",
                "X-Token": "token-abc",
                "X-Apple-Store-Front": "143441",
            ]
        )
        let useCase = LoginUseCase(
            authService: TestAuthService(session: expectedSession, error: nil),
            logger: logger
        )

        let session = try await useCase.execute(
            appleID: "tester@ipatool.local",
            password: "secret",
            code: "000000"
        )

        XCTAssertEqual(session, expectedSession)

        let entries = await logger.snapshot()
        let firstCategory = entries.first?.category
        let lastLevel = entries.last?.level
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(firstCategory, "usecase.auth")
        XCTAssertEqual(lastLevel, .notice)
    }
}
