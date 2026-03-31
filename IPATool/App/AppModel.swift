import Foundation
import Observation
import AppKit

@Observable
@MainActor
final class AppModel {
    struct VerificationPrompt: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var message: String
        var appleID: String
    }

    enum SessionState: Equatable {
        case signedOut
        case signingIn
        case signedIn(AppSession)
        case failed(AppError)
    }

    var selectedRoute: AppRoute? = .search
    var sessionState: SessionState = .signedOut
    var searchState: SearchWorkflowState = .idle
    var purchaseState: PurchaseLicense = .idle
    var appIDQuery = ""
    var requestedVersionID = ""
    var versionResults: [AppVersion] = []
    var selectedVersionID: AppVersion.ID?
    var cachedAppleID = ""
    var taskHistory: [DownloadTaskRecord] = []
    var logs: [LogEntry] = []
    var operationalRisks: [OperationalRisk] = OperationalRiskCatalog.items
    var latestError: AppError?
    var verificationPrompt: VerificationPrompt?
    private var taskRefreshLoop: Task<Void, Never>?
    private var verificationCodeContinuation: CheckedContinuation<String?, Never>?
    private var isVerificationPromptActive = false

    let container: AppContainer

    init(container: AppContainer) {
        self.container = container
    }

    func bootstrap() async {
        await restoreSandboxAccess()
        await container.downloadManager.loadPersistedTasks()
        await restoreCachedCredential()
        await container.downloadManager.attachSessionIfNeeded(currentSession)
        await refreshLogs()
        await refreshTaskHistory()
        await container.downloadManager.resumePendingTasks(settings: container.settings.snapshot)
        await refreshTaskHistory()
        startTaskRefreshLoop()
    }

    func signIn(appleID: String, password: String, code: String) async {
        sessionState = .signingIn
        do {
            let session = try await container.loginUseCase.execute(
                appleID: appleID,
                password: password,
                code: code.isEmpty ? nil : code
            )
            sessionState = .signedIn(session)
        } catch let error as AppError {
            latestError = error
            sessionState = .failed(error)
        } catch {
            let appError = AppError(
                title: "Sign-In Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the login use case and private Apple protocol wiring before retrying."
            )
            latestError = appError
            sessionState = .failed(appError)
        }
        await refreshLogs()
    }

    func signOut() async {
        let pausedTaskCount = await container.downloadService.pauseAuthenticatedDownloads()
        await container.authService.signOut()
        sessionState = .signedOut
        purchaseState = .idle
        await container.downloadManager.attachSessionIfNeeded(nil)
        if isVerificationPromptActive {
            cancelVerificationPrompt()
        }
        if pausedTaskCount > 0 {
            await refreshTaskHistory()
        }
        await container.logStore.append(level: .notice, category: "auth", message: "Signed out of the current Apple account session.")
        await refreshLogs()
    }

    func search() async {
        guard case .signedIn(let session) = sessionState else {
            let error = AppError(
                title: "Sign-In Required",
                message: "Search now uses the authenticated Apple catalog session, so you need to sign in first.",
                recoverySuggestion: "Complete Apple ID sign-in, then retry the app lookup."
            )
            latestError = error
            searchState = .failed(error)
            return
        }

        let trimmedAppID = appIDQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedVersionID = requestedVersionID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedAppID.isEmpty, trimmedAppID.allSatisfy(\.isNumber) else {
            let error = AppError(
                title: "Invalid App ID",
                message: "The App ID must be a numeric value.",
                recoverySuggestion: "Enter a numeric App ID from the App Store before loading versions."
            )
            latestError = error
            searchState = .failed(error)
            return
        }

        if !trimmedVersionID.isEmpty {
            guard trimmedVersionID.allSatisfy(\.isNumber) else {
                let error = AppError(
                    title: "Invalid Version ID",
                    message: "The Version ID must contain digits only.",
                    recoverySuggestion: "Clear the Version ID field or enter a numeric external version identifier."
                )
                latestError = error
                searchState = .failed(error)
                return
            }

            guard trimmedVersionID != trimmedAppID else {
                let error = AppError(
                    title: "Version ID Looks Incorrect",
                    message: "The Version ID matches the App ID, which usually means the wrong value was pasted into the version field.",
                    recoverySuggestion: "Leave Version ID empty for the latest build, or enter the numeric external version identifier for a specific build."
                )
                latestError = error
                searchState = .failed(error)
                return
            }
        }

        searchState = .searching
        purchaseState = .idle
        do {
            let versions: [AppVersion]
            if trimmedVersionID.isEmpty {
                versions = try await container.searchAppUseCase.execute(appID: trimmedAppID, session: session)
            } else {
                let version = try await container.searchAppUseCase.loadVersion(
                    appID: trimmedAppID,
                    versionID: trimmedVersionID,
                    session: session
                )
                versions = [version]
            }
            versionResults = versions
            selectedVersionID = versionResults.first?.id
            appIDQuery = trimmedAppID
            requestedVersionID = trimmedVersionID
            searchState = .loaded(appID: trimmedAppID, versions: versions)
        } catch let error as AppError {
            latestError = error
            searchState = .failed(error)
        } catch {
            let appError = AppError(
                title: "Search Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the app lookup use case and repository wiring."
            )
            latestError = appError
            searchState = .failed(appError)
        }
        await refreshLogs()
    }

    func selectVersion(id: AppVersion.ID?) {
        selectedVersionID = id
        purchaseState = .idle
    }

    func requestSelectedVersionLicense() async {
        guard case .signedIn(let session) = sessionState else {
            let error = AppError(
                title: "Sign-In Required",
                message: "License requests require the authenticated Apple account session.",
                recoverySuggestion: "Sign in again, then request the license for the selected version."
            )
            latestError = error
            purchaseState = PurchaseLicense(state: .failed, message: error.message, failureType: error.title)
            return
        }

        guard let selectedVersion else {
            let error = AppError(
                title: "Version Required",
                message: "Select a version before requesting a license.",
                recoverySuggestion: "Choose one of the loaded versions, then try again."
            )
            latestError = error
            purchaseState = PurchaseLicense(state: .failed, message: error.message, failureType: nil)
            return
        }

        purchaseState = PurchaseLicense(
            state: .requesting,
            message: "Requesting purchase or library state for \(selectedVersion.displayName) \(selectedVersion.version)...",
            failureType: nil
        )

        do {
            let license = try await requestLicenseWithRecovery(
                appID: selectedVersion.appID,
                versionID: selectedVersion.externalVersionID.isEmpty ? nil : selectedVersion.externalVersionID,
                session: session
            )
            purchaseState = license
            if license.state == .licensed || license.state == .alreadyOwned {
                if selectedVersion.externalVersionID.isEmpty || selectedVersion.externalVersionID == "0" {
                    await container.logStore.append(
                        level: .info,
                        category: "purchase",
                        message: "Skipping post-purchase version refresh for \(selectedVersion.appID) because the catalog returned versionID \(selectedVersion.externalVersionID.isEmpty ? "<empty>" : selectedVersion.externalVersionID), which behaves like the latest-version sentinel in Apple's private API."
                    )
                } else {
                    do {
                        let refreshedVersion = try await container.searchAppUseCase.loadVersion(
                            appID: selectedVersion.appID,
                            versionID: selectedVersion.externalVersionID,
                            session: session
                        )
                        replaceVersion(refreshedVersion)
                        await container.logStore.append(
                            level: .notice,
                            category: "purchase",
                            message: "Refreshed catalog details for \(refreshedVersion.displayName) \(refreshedVersion.version) after license confirmation."
                        )
                    } catch {
                        await container.logStore.append(
                            level: .notice,
                            category: "purchase",
                            message: "Post-purchase version refresh failed for \(selectedVersion.appID), but the current version payload will still be used for download task creation: \(error.localizedDescription)"
                        )
                    }
                }
            }
        } catch let error as AppError {
            latestError = error
            purchaseState = PurchaseLicense(state: .failed, message: error.message, failureType: error.title)
        } catch {
            let appError = AppError(
                title: "License Request Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the purchase use case wiring before enabling the download pipeline."
            )
            latestError = appError
            purchaseState = PurchaseLicense(state: .failed, message: appError.message, failureType: nil)
        }
        await refreshLogs()
    }

    private func requestLicenseWithRecovery(appID: String, versionID: String?, session: AppSession) async throws -> PurchaseLicense {
        do {
            return try await container.requestLicenseUseCase.execute(
                appID: appID,
                versionID: versionID,
                session: session
            )
        } catch let error as AppError where error.title == "Purchase Session Expired" {
            await container.logStore.append(
                level: .notice,
                category: "purchase",
                message: "Purchase session expired for \(appID). Attempting Apple session refresh before retrying."
            )

            guard let credential = await container.loadCachedCredentialUseCase.execute() else {
                throw error
            }

            let refreshedSession: AppSession
            if let cachedVerificationCode = credential.verificationCode, !cachedVerificationCode.isEmpty {
                do {
                    await container.logStore.append(
                        level: .info,
                        category: "purchase",
                        message: "Trying the cached Apple verification code for \(credential.appleID) before prompting again."
                    )
                    refreshedSession = try await container.loginUseCase.execute(
                        appleID: credential.appleID,
                        password: credential.password,
                        code: cachedVerificationCode
                    )
                } catch {
                    await container.logStore.append(
                        level: .notice,
                        category: "purchase",
                        message: "The cached Apple verification code was rejected. Triggering a fresh verification challenge."
                    )
                    refreshedSession = try await refreshSessionWithPrompt(
                        credential: credential,
                        initialMessage: error.localizedDescription
                    )
                }
            } else {
                refreshedSession = try await refreshSessionWithPrompt(
                    credential: credential,
                    initialMessage: error.message
                )
            }
            sessionState = .signedIn(refreshedSession)

            await container.logStore.append(
                level: .notice,
                category: "purchase",
                message: "Apple session refresh completed for \(credential.appleID). Retrying purchase request once."
            )

            return try await container.requestLicenseUseCase.execute(
                appID: appID,
                versionID: versionID,
                session: refreshedSession
            )
        }
    }

    private func refreshSessionWithPrompt(
        credential: KeychainCredentialStore.StoredCredential,
        initialMessage: String
    ) async throws -> AppSession {
        do {
            _ = try await container.loginUseCase.execute(
                appleID: credential.appleID,
                password: credential.password,
                code: nil
            )
        } catch {
            await container.logStore.append(
                level: .notice,
                category: "purchase",
                message: "Apple verification challenge should now be available for \(credential.appleID). Waiting for a fresh code."
            )
        }

        let verificationCode = try await promptForVerificationCode(
            appleID: credential.appleID,
            message: initialMessage
        )
        guard let verificationCode, !verificationCode.isEmpty else {
            throw AppError(
                title: "Verification Cancelled",
                message: "The purchase session refresh was cancelled before an Apple verification code was provided.",
                recoverySuggestion: "Retry the license request and enter the verification code when prompted."
            )
        }

        return try await container.loginUseCase.execute(
            appleID: credential.appleID,
            password: credential.password,
            code: verificationCode
        )
    }

    func submitVerificationCode(_ code: String) {
        verificationPrompt = nil
        isVerificationPromptActive = false
        verificationCodeContinuation?.resume(returning: code.trimmingCharacters(in: .whitespacesAndNewlines))
        verificationCodeContinuation = nil
    }

    func cancelVerificationPrompt() {
        verificationPrompt = nil
        isVerificationPromptActive = false
        verificationCodeContinuation?.resume(returning: nil)
        verificationCodeContinuation = nil
    }

    private func promptForVerificationCode(appleID: String, message: String) async throws -> String? {
        guard isVerificationPromptActive == false, verificationCodeContinuation == nil else {
            throw AppError(
                title: "Verification Already In Progress",
                message: "Another Apple verification request is already waiting for a code.",
                recoverySuggestion: "Finish or cancel the current verification prompt before retrying the session refresh."
            )
        }

        isVerificationPromptActive = true
        verificationPrompt = VerificationPrompt(
            title: "Apple Verification Required",
            message: message,
            appleID: appleID
        )

        return await withCheckedContinuation { continuation in
            verificationCodeContinuation = continuation
        }
    }

    func dismissError() {
        latestError = nil
    }

    func refreshLogs() async {
        logs = await container.logStore.snapshot()
    }

    func refreshTaskHistory() async {
        taskHistory = await container.downloadService.taskHistory()
    }

    func createDownloadTaskForSelectedVersion() async {
        guard case .signedIn(let session) = sessionState else {
            let error = AppError(
                title: "Sign-In Required",
                message: "Download creation requires the authenticated Apple account session.",
                recoverySuggestion: "Sign in again, then create the download task."
            )
            latestError = error
            return
        }

        guard await ensureOutputDirectoryAccess() else {
            return
        }

        guard let selectedVersion else {
            let error = AppError(
                title: "Version Required",
                message: "Select a version before creating a download task.",
                recoverySuggestion: "Choose a loaded version and request a license first."
            )
            latestError = error
            return
        }

        guard purchaseState.state == .licensed || purchaseState.state == .alreadyOwned else {
            let error = AppError(
                title: "License Required",
                message: "A download task can only be created after the license request succeeds.",
                recoverySuggestion: "Request the license for the selected version first."
            )
            latestError = error
            return
        }

        do {
            let resolvedVersion: AppVersion
            if selectedVersion.downloadURL == nil || selectedVersion.signaturePayload == nil {
                resolvedVersion = try await container.searchAppUseCase.loadDownloadableVersion(
                    appID: selectedVersion.appID,
                    session: session
                )
                replaceVersion(resolvedVersion)
                await container.logStore.append(
                    level: .notice,
                    category: "download",
                    message: "Resolved a downloadable catalog version \(resolvedVersion.externalVersionID) for \(resolvedVersion.displayName) before task creation."
                )
            } else {
                resolvedVersion = selectedVersion
            }

            _ = try await container.createDownloadTaskUseCase.execute(
                version: resolvedVersion,
                session: session,
                settings: container.settings.snapshot
            )
            selectedRoute = .tasks
            await refreshTaskHistory()
            await refreshLogs()
        } catch let error as AppError {
            latestError = error
        } catch {
            latestError = AppError(
                title: "Task Creation Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the downloader configuration and cache directory settings."
            )
        }
    }

    func cancelTask(id: UUID) async {
        await container.downloadService.cancelDownload(id: id)
        await refreshTaskHistory()
        await refreshLogs()
    }

    func pauseTask(id: UUID) async {
        await container.downloadService.pauseDownload(id: id)
        await refreshTaskHistory()
        await refreshLogs()
    }

    func retryTask(id: UUID) async {
        guard case .signedIn(let session) = sessionState else {
            latestError = AppError(
                title: "Sign-In Required",
                message: "Retrying a download task requires an active Apple account session.",
                recoverySuggestion: "Sign in again, then retry the task."
            )
            return
        }

        guard await ensureOutputDirectoryAccess() else {
            return
        }

        do {
            try await container.downloadService.retryDownload(id: id, session: session, settings: container.settings.snapshot)
            await refreshTaskHistory()
            await refreshLogs()
        } catch let error as AppError {
            latestError = error
        } catch {
            latestError = AppError(
                title: "Retry Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the task logs and current Apple session, then try again."
            )
        }
    }

    func deleteTask(id: UUID) async {
        await container.downloadService.deleteDownload(id: id)
        await refreshTaskHistory()
        await refreshLogs()
    }

    func revealInFinder(path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedPath)])
    }

    func copyToPasteboard(_ value: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
    }

    func sanitizeAppIDInput(_ value: String) {
        appIDQuery = value.filter(\.isNumber)
    }

    func sanitizeVersionIDInput(_ value: String) {
        requestedVersionID = value.filter(\.isNumber)
    }

    func clearLogs() async {
        await container.logStore.clear()
        await refreshLogs()
    }

    func persistSettings() {
        do {
            try container.settings.persist()
        } catch {
            latestError = AppError(
                title: "Settings Save Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Check UserDefaults persistence and try saving the configuration again."
            )
        }
    }

    func persistBookmark(for url: URL, key: String) {
        do {
            try container.settings.saveBookmark(for: url, key: key)
            container.sandboxAccessCoordinator.replaceAccess(for: key, with: url)
        } catch {
            latestError = AppError(
                title: "Folder Access Save Failed",
                message: error.localizedDescription,
                recoverySuggestion: "The plain path is still stored, but sandbox-friendly bookmark persistence was not saved."
            )
        }
    }

    func clearCacheDirectory() {
        guard !hasCacheDependentTasks else {
            latestError = AppError(
                title: "Cache In Use",
                message: "The cache directory is still backing active or resumable download tasks.",
                recoverySuggestion: "Wait for active tasks to finish, or cancel/delete paused and in-progress tasks before clearing the cache directory."
            )
            return
        }

        let cachePath = (container.settings.cacheDirectoryPath as NSString).expandingTildeInPath
        let cacheURL = URL(fileURLWithPath: cachePath, isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: cacheURL.path) {
                let contents = try FileManager.default.contentsOfDirectory(
                    at: cacheURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
                for itemURL in contents where itemURL.lastPathComponent != "tasks.json" {
                    try FileManager.default.removeItem(at: itemURL)
                }
            } else {
                try FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
            }
            Task {
                await container.logStore.append(level: .notice, category: "settings.cache", message: "Cleared cache directory at \(cachePath).")
                await refreshLogs()
            }
        } catch {
            latestError = AppError(
                title: "Cache Cleanup Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Close any process using the cache directory, then try again."
            )
        }
    }

    private func ensureOutputDirectoryAccess() async -> Bool {
        let bookmarkKey = AppSettingsSnapshot.outputDirectoryBookmarkKey

        if (try? container.settings.resolveBookmark(for: bookmarkKey)) != nil {
            return true
        }

        let currentPath = (container.settings.outputDirectoryPath as NSString).expandingTildeInPath
        let panel = NSOpenPanel()
        panel.title = "Authorize Output Directory"
        panel.message = "Choose the folder where IPATool should export finished IPA files."
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Allow Access"
        panel.directoryURL = URL(fileURLWithPath: currentPath, isDirectory: true)

        let selectedURL = await presentOutputDirectoryAuthorizationPanel(panel)
        guard let selectedURL else {
            latestError = AppError(
                title: "Output Directory Access Required",
                message: "IPATool needs permission to write the finished IPA into the selected output directory.",
                recoverySuggestion: "Choose an output folder when prompted, or open Settings and grant folder access manually."
            )
            return false
        }

        container.settings.outputDirectoryPath = selectedURL.path
        persistSettings()
        persistBookmark(for: selectedURL, key: bookmarkKey)
        return true
    }

    private func presentOutputDirectoryAuthorizationPanel(_ panel: NSOpenPanel) async -> URL? {
        await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    private func restoreCachedCredential() async {
        let credential = await container.loadCachedCredentialUseCase.execute()
        if let credential {
            cachedAppleID = credential.appleID
        }

        do {
            if let storedSession = try await container.keychainStore.loadSession() {
                await restoreCookies(from: storedSession)
                sessionState = .signedIn(storedSession.session)
                await container.logStore.append(
                    level: .notice,
                    category: "auth",
                    message: "Restored Apple account session from Keychain without replaying login for \(storedSession.session.appleID)."
                )
                return
            }
        } catch {
            await container.logStore.append(
                level: .notice,
                category: "auth",
                message: "Stored session restoration failed: \(error.localizedDescription)"
            )
        }

        if let credential {
            await container.logStore.append(
                level: .info,
                category: "auth",
                message: "Cached credentials are available for \(credential.appleID), but automatic password replay is disabled to avoid repeated Apple two-factor challenges."
            )
        }
    }

    private func restoreCookies(from storedSession: KeychainCredentialStore.StoredSession) async {
        let cookies = storedSession.cookies.compactMap(\.httpCookie)
        await Task.detached(priority: .utility) {
            let storage = HTTPCookieStorage.shared
            for cookie in cookies {
                storage.setCookie(cookie)
            }
        }.value
    }

    private func restoreSandboxAccess() async {
        do {
            let restored = try container.sandboxAccessCoordinator.restoreAccess(using: container.settings)
            if !restored.isEmpty {
                await container.logStore.append(
                    level: .notice,
                    category: "sandbox",
                    message: "Restored security-scoped access for \(restored.count) persisted location(s)."
                )
            }
        } catch {
            latestError = AppError(
                title: "Folder Access Restore Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Re-select the output and cache directories in Settings to renew sandbox access."
            )
        }
    }

    var selectedVersion: AppVersion? {
        versionResults.first(where: { $0.id == selectedVersionID })
    }

    private var currentSession: AppSession? {
        guard case .signedIn(let session) = sessionState else {
            return nil
        }
        return session
    }

    var activeTaskCount: Int {
        taskHistory.filter { task in
            switch task.status {
            case .queued, .resolvingLicense, .preparingDownload, .downloading, .verifying, .rewritingIPA:
                true
            case .paused, .completed, .failed, .cancelled:
                false
            }
        }.count
    }

    var failedTaskCount: Int {
        taskHistory.filter { $0.status == .failed }.count
    }

    var completedTaskCount: Int {
        taskHistory.filter { $0.status == .completed }.count
    }

    var hasCacheDependentTasks: Bool {
        taskHistory.contains { task in
            switch task.status {
            case .queued, .preparingDownload, .downloading, .paused, .verifying, .rewritingIPA:
                true
            case .resolvingLicense, .completed, .failed, .cancelled:
                false
            }
        }
    }

    private func replaceVersion(_ refreshedVersion: AppVersion) {
        if let index = versionResults.firstIndex(where: { $0.externalVersionID == refreshedVersion.externalVersionID && $0.appID == refreshedVersion.appID }) {
            versionResults[index] = refreshedVersion
        } else {
            versionResults.insert(refreshedVersion, at: 0)
        }
        selectedVersionID = refreshedVersion.id
    }

    private func startTaskRefreshLoop() {
        taskRefreshLoop?.cancel()
        taskRefreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshTaskHistory()
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}
