import Foundation
import XCTest
@testable import IPATool

@MainActor
final class AppModelBehaviorTests: XCTestCase {
    func testSignOutPausesAuthenticatedDownloadsBeforeClearingSession() async {
        let downloadService = RecordingDownloadService()
        await downloadService.setPauseAuthenticatedDownloadsResult(2)
        let authService = RecordingAuthService(session: .testSession)

        let model = AppModel(container: makeContainer(authService: authService, downloadService: downloadService))
        model.sessionState = AppModel.SessionState.signedIn(AppSession.testSession)

        await model.signOut()

        let pausedCallCount = await downloadService.recordedPauseAuthenticatedDownloadsCallCount()
        let signOutCallCount = await authService.recordedSignOutCallCount()
        XCTAssertEqual(pausedCallCount, 1)
        XCTAssertEqual(signOutCallCount, 1)
        if case .signedOut = model.sessionState {
        } else {
            XCTFail("Expected signedOut session state.")
        }
    }

    func testConcurrentVerificationRequestsRejectSecondPrompt() async throws {
        let credentialStore = InMemoryCredentialStore()
        try await credentialStore.saveCredential(.init(appleID: "tester@ipatool.local", password: "secret"))

        let authService = RecordingAuthService(
            session: .testSession,
            signInHandler: { appleID, _, code in
                if code == nil {
                    throw AppError(
                        title: "Verification Needed",
                        message: "Enter a fresh verification code.",
                        recoverySuggestion: ""
                    )
                }
                return AppSession(
                    appleID: appleID,
                    displayName: "Tester",
                    dsid: "1234567890",
                    guid: "GUID",
                    storeFront: "143441",
                    authHeaders: ["X-Token": "token-abc"]
                )
            }
        )

        let purchaseService = TestPurchaseService { _, _, _ in
            throw AppError(
                title: "Purchase Session Expired",
                message: "Apple asked the client to sign in again.",
                recoverySuggestion: ""
            )
        }

        let appVersion = AppVersion(
            id: "123-1",
            appID: "123",
            displayName: "Test App",
            bundleIdentifier: "com.test.app",
            version: "1.0",
            externalVersionID: "1",
            expectedMD5: nil,
            metadataValues: [:],
            signaturePayload: Data("signature".utf8).base64EncodedString(),
            downloadURL: URL(string: "file:///tmp/test.ipa")
        )

        let model = AppModel(
            container: makeContainer(
                authService: authService,
                purchaseService: purchaseService,
                credentialStore: credentialStore
            )
        )
        model.sessionState = AppModel.SessionState.signedIn(AppSession.testSession)
        model.versionResults = [appVersion]
        model.selectedVersionID = appVersion.id

        let first = Task { await model.requestSelectedVersionLicense() }
        await waitUntil {
            await MainActor.run { model.verificationPrompt != nil }
        }

        await model.requestSelectedVersionLicense()

        XCTAssertEqual(model.latestError?.title, "Verification Already In Progress")
        model.cancelVerificationPrompt()
        _ = await first.value
    }

    private func makeContainer(
        authService: AuthServicing,
        purchaseService: PurchaseServicing = TestPurchaseService { _, _, _ in
            PurchaseLicense(state: .licensed, message: "ok", failureType: nil)
        },
        downloadService: DownloadServicing = RecordingDownloadService(),
        credentialStore: CredentialStoring = InMemoryCredentialStore()
    ) -> AppContainer {
        let storageRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let settings = AppSettingsController(
            snapshot: .default,
            store: UserDefaultsAppSettingsStore(fileURL: storageRoot.appendingPathComponent("settings.json")),
            bookmarkStore: UserDefaultsSandboxBookmarkStore(fileURL: storageRoot.appendingPathComponent("bookmarks.plist"))
        )
        let keychainStore = KeychainCredentialStore()
        let logger = AppLogger()
        let httpClient = TestHTTPClient()
        let ipaProcessor = RecordingIPAProcessor()
        let downloadManager = ChunkedDownloadManager(
            persistenceURL: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json"),
            httpClient: httpClient,
            logger: logger,
            credentialStore: credentialStore,
            ipaProcessor: ipaProcessor
        )
        let loadCachedCredentialUseCase = LoadCachedCredentialUseCase(keychainStore: credentialStore, logger: logger)
        let loginUseCase = LoginUseCase(authService: authService, logger: logger)
        let searchUseCase = SearchAppUseCase(catalogService: TestCatalogService(), logger: logger)
        let requestLicenseUseCase = RequestLicenseUseCase(purchaseService: purchaseService, logger: logger)
        let createDownloadTaskUseCase = CreateDownloadTaskUseCase(downloadService: downloadService, logger: logger)

        return AppContainer(
            settings: settings,
            keychainStore: keychainStore,
            httpClient: httpClient,
            authService: authService,
            catalogService: TestCatalogService(),
            purchaseService: purchaseService,
            downloadService: downloadService,
            logStore: logger,
            downloadManager: downloadManager,
            ipaProcessor: ipaProcessor,
            sandboxAccessCoordinator: SandboxAccessCoordinator(),
            loadCachedCredentialUseCase: loadCachedCredentialUseCase,
            loginUseCase: loginUseCase,
            searchAppUseCase: searchUseCase,
            requestLicenseUseCase: requestLicenseUseCase,
            createDownloadTaskUseCase: createDownloadTaskUseCase
        )
    }
}
