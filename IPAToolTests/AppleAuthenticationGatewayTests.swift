import Foundation
import XCTest
@testable import IPATool

@MainActor
final class AppleAuthenticationGatewayTests: XCTestCase {
    func testLoginBuildsExpectedSessionFromPropertyListResponse() async throws {
        let payload: [String: Any] = [
            "status": 0,
            "dsPersonId": "1234567890",
            "passwordToken": "token-abc",
            "accountInfo": [
                "appleId": "tester@ipatool.local",
                "address": [
                    "firstName": "Ariel",
                    "lastName": "Tester",
                ],
            ],
        ]
        let responseData = try ApplePropertyListCodec.encode(payload)
        let requestURL = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast?guid=GUID")!
        let httpResponse = HTTPResponse(
            request: HTTPRequest(url: requestURL),
            statusCode: 200,
            headers: ["x-set-apple-store-front": "143441-1,29"],
            body: responseData
        )
        let gateway = PendingAppleAuthenticationGateway(httpClient: TestHTTPClient(response: httpResponse, error: nil))

        let result = try await gateway.login(
            request: StoreLoginRequestDTO(
                appleID: "tester@ipatool.local",
                password: "secret",
                verificationCode: "123456",
                guid: "GUID"
            )
        )

        let status = result.status
        let dsPersonID = result.dsPersonID
        let passwordToken = result.passwordToken
        let appleID = result.accountInfo.appleID
        let firstName = result.accountInfo.address.firstName
        let storeFront = result.storeFront
        let authHeader = result.authHeaders["X-Token"]

        XCTAssertEqual(status, 0)
        XCTAssertEqual(dsPersonID, "1234567890")
        XCTAssertEqual(passwordToken, "token-abc")
        XCTAssertEqual(appleID, "tester@ipatool.local")
        XCTAssertEqual(firstName, "Ariel")
        XCTAssertEqual(storeFront, "143441")
        XCTAssertEqual(authHeader, "token-abc")
    }
}
