import Foundation
import XCTest
@testable import IPATool

actor TestLogger: LoggingServicing {
    private var entries: [LogEntry] = []

    func append(level: LogLevel, category: String, message: String) async {
        entries.append(LogEntry(level: level, category: category, message: message))
    }

    func snapshot() async -> [LogEntry] {
        entries
    }

    func clear() async {
        entries.removeAll()
    }
}

struct TestAuthService: AuthServicing {
    var session: AppSession
    var error: Error?

    func signIn(appleID: String, password: String, code: String?) async throws -> AppSession {
        _ = appleID
        _ = password
        _ = code
        if let error {
            throw error
        }
        return session
    }

    func signOut() async {}
}

actor RecordingAuthService: AuthServicing {
    private(set) var signInCalls: [(appleID: String, password: String, code: String?)] = []
    private(set) var signOutCallCount = 0
    var session: AppSession
    var signInHandler: (@Sendable (String, String, String?) async throws -> AppSession)?

    init(session: AppSession, signInHandler: (@Sendable (String, String, String?) async throws -> AppSession)? = nil) {
        self.session = session
        self.signInHandler = signInHandler
    }

    func signIn(appleID: String, password: String, code: String?) async throws -> AppSession {
        signInCalls.append((appleID, password, code))
        if let signInHandler {
            return try await signInHandler(appleID, password, code)
        }
        return session
    }

    func signOut() async {
        signOutCallCount += 1
    }

    func recordedSignOutCallCount() -> Int {
        signOutCallCount
    }
}

struct TestHTTPClient: HTTPClient {
    var response: HTTPResponse?
    var error: Error?

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if let error {
            throw error
        }
        if let response {
            return response
        }
        return HTTPResponse(request: request, statusCode: 200, headers: [:], body: Data())
    }
}

actor SequencedHTTPClient: HTTPClient {
    private var responses: [HTTPResponse]
    private var errors: [Error]

    init(responses: [HTTPResponse] = [], errors: [Error] = []) {
        self.responses = responses
        self.errors = errors
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        if errors.isEmpty == false {
            throw errors.removeFirst()
        }
        if responses.isEmpty == false {
            return responses.removeFirst()
        }
        return HTTPResponse(request: request, statusCode: 200, headers: [:], body: Data())
    }
}

actor InMemoryCredentialStore: CredentialStoring {
    var credential: KeychainCredentialStore.StoredCredential?
    var session: KeychainCredentialStore.StoredSession?

    func loadCredential() async throws -> KeychainCredentialStore.StoredCredential? {
        credential
    }

    func saveCredential(_ credential: KeychainCredentialStore.StoredCredential) async throws {
        self.credential = credential
    }

    func loadSession() async throws -> KeychainCredentialStore.StoredSession? {
        session
    }

    func saveSession(_ session: KeychainCredentialStore.StoredSession) async throws {
        self.session = session
    }

    func clear() async throws {
        credential = nil
        session = nil
    }
}

actor RecordingIPAProcessor: IPAProcessingServicing {
    private(set) var processedURLs: [URL] = []

    func processDownloadedIPA(at ipaURL: URL, version: AppVersion, appleID: String) async throws {
        _ = version
        _ = appleID
        processedURLs.append(ipaURL)
    }

    func snapshot() -> [URL] {
        processedURLs
    }
}

actor RecordingDownloadService: DownloadServicing {
    private(set) var tasks: [DownloadTaskRecord] = []
    private(set) var pauseAuthenticatedDownloadsCallCount = 0
    var pauseAuthenticatedDownloadsResult = 0

    func setPauseAuthenticatedDownloadsResult(_ value: Int) {
        pauseAuthenticatedDownloadsResult = value
    }

    func recordedPauseAuthenticatedDownloadsCallCount() -> Int {
        pauseAuthenticatedDownloadsCallCount
    }

    func taskHistory() async -> [DownloadTaskRecord] {
        tasks
    }

    func enqueueDownload(for version: AppVersion, session: AppSession, settings: AppSettingsSnapshot) async throws -> DownloadTaskRecord {
        let displayName = await MainActor.run { version.displayName }
        let versionString = await MainActor.run { version.version }
        let outputPath = await MainActor.run { settings.outputDirectoryPath }
        let cachePath = await MainActor.run { settings.cacheDirectoryPath }
        let task = await MainActor.run {
            DownloadTaskRecord(
                id: UUID(),
                title: displayName,
                version: versionString,
                status: .queued,
                progress: 0,
                bytesDownloaded: 0,
                totalBytes: 0,
                retryCount: 0,
                outputPath: outputPath,
                cachePath: cachePath,
                detailMessage: "queued",
                createdAt: .now,
                updatedAt: .now
            )
        }
        tasks.append(task)
        return task
    }

    func cancelDownload(id: UUID) async {}

    func pauseDownload(id: UUID) async {}

    func pauseAuthenticatedDownloads() async -> Int {
        pauseAuthenticatedDownloadsCallCount += 1
        return pauseAuthenticatedDownloadsResult
    }

    func retryDownload(id: UUID, session: AppSession, settings: AppSettingsSnapshot) async throws {}

    func deleteDownload(id: UUID) async {}
}

struct TestPurchaseService: PurchaseServicing {
    var handler: @Sendable (String, String?, AppSession) async throws -> PurchaseLicense

    func requestLicense(appID: String, versionID: String?, session: AppSession) async throws -> PurchaseLicense {
        try await handler(appID, versionID, session)
    }
}

struct TestCatalogService: AppCatalogServicing {
    var versions: [AppVersion] = []

    func search(appID: String, session: AppSession) async throws -> [AppVersion] {
        versions
    }

    func loadVersion(appID: String, versionID: String, session: AppSession) async throws -> AppVersion {
        versions.first ?? AppVersion(
            id: "\(appID)-\(versionID)",
            appID: appID,
            displayName: "App",
            bundleIdentifier: "com.test.app",
            version: "1.0",
            externalVersionID: versionID,
            expectedMD5: nil,
            metadataValues: [:],
            signaturePayload: nil,
            downloadURL: nil
        )
    }

    func loadDownloadableVersion(appID: String, session: AppSession) async throws -> AppVersion {
        try await loadVersion(appID: appID, versionID: versions.first?.externalVersionID ?? "1", session: session)
    }
}

extension AppSession {
    static let testSession = AppSession(
        appleID: "tester@ipatool.local",
        displayName: "Tester",
        dsid: "1234567890",
        guid: "GUID",
        storeFront: "143441",
        authHeaders: [
            "X-Dsid": "1234567890",
            "iCloud-DSID": "1234567890",
            "X-Token": "token-abc",
            "X-Apple-Store-Front": "143441",
        ]
    )
}

extension XCTestCase {
    func waitUntil(
        timeout: TimeInterval = 5,
        pollInterval: Duration = .milliseconds(100),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @Sendable () async -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() {
                return
            }
            try? await Task.sleep(for: pollInterval)
        }

        XCTFail("Condition not satisfied before timeout.", file: file, line: line)
    }
}
