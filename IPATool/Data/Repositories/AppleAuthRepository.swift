import Foundation

struct AppleAuthRepository: AuthServicing {
    let gateway: AppleAuthenticationGateway
    let keychainStore: CredentialStoring
    let logger: LoggingServicing

    func signIn(appleID: String, password: String, code: String?) async throws -> AppSession {
        guard !appleID.isEmpty, !password.isEmpty else {
            throw AppError(
                title: "Credentials Required",
                message: "Apple ID and password are required before the login flow can begin.",
                recoverySuggestion: "Enter the Apple ID and password for the account you want to authenticate."
            )
        }

        do {
            let guid = try AppleDeviceGUIDProvider.currentGUID()
            let response = try await gateway.login(
                request: StoreLoginRequestDTO(
                    appleID: appleID,
                    password: password,
                    verificationCode: code,
                    guid: guid
                )
            )
            guard response.status != nil, !response.dsPersonID.isEmpty, !response.passwordToken.isEmpty else {
                throw AppError(
                    title: "Authentication Failed",
                    message: response.customerMessage ?? response.failureType ?? "The Apple authentication response did not contain a valid session.",
                    recoverySuggestion: "Check the Apple ID, password, verification code, and the private login protocol compatibility."
                )
            }
            let session = StoreDTOMapper.mapSession(from: response, guid: guid)
            let existingCredential = try await keychainStore.loadCredential()
            let persistedVerificationCode = code ?? existingCredential?.verificationCode
            try await keychainStore.saveCredential(
                .init(
                    appleID: appleID,
                    password: password,
                    verificationCode: persistedVerificationCode
                )
            )
            try await keychainStore.saveSession(
                .init(
                    session: session,
                    cookies: currentAppleCookies().map(KeychainCredentialStore.StoredSession.StoredCookie.init(cookie:))
                )
            )
            await logger.append(level: .info, category: "auth", message: "Stored credentials in Keychain and created a session for \(appleID).")
            let authCookieCount = HTTPCookieStorage.shared.cookies(for: URL(string: "https://auth.itunes.apple.com")!)?.count ?? 0
            let buyCookieCount = HTTPCookieStorage.shared.cookies(for: URL(string: "https://buy.itunes.apple.com")!)?.count ?? 0
            await logger.append(level: .info, category: "auth", message: "Current Apple web session cookie counts: auth=\(authCookieCount), buy=\(buyCookieCount).")
            return session
        } catch let error as ProtocolAdapterError {
            await logger.append(level: .notice, category: "auth", message: error.localizedDescription)
            throw AppError(
                title: "Protocol Adapter Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the private Apple login protocol mapping and account state before retrying."
            )
        } catch let error as AppleDeviceGUIDError {
            await logger.append(level: .error, category: "auth.guid", message: error.localizedDescription)
            throw AppError(
                title: "Device Identity Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Verify the Mac can enumerate a hardware network interface before retrying the Apple login flow."
            )
        } catch let error as HTTPClientError {
            await logger.append(level: .error, category: "auth.network", message: error.localizedDescription)
            switch error {
            case .hostNotFound(let host):
                throw AppError(
                    title: "Authentication Host Unreachable",
                    message: "A server with the specified hostname could not be found: \(host).",
                    recoverySuggestion: "If ipatool.js works on this Mac, rebuild and relaunch the signed app so the updated sandbox entitlement can take effect. Otherwise check DNS, proxy, or VPN rules and confirm that \(host) is reachable."
                )
            case .networkUnavailable:
                throw AppError(
                    title: "Network Unavailable",
                    message: error.localizedDescription,
                    recoverySuggestion: "Verify the Mac has internet access and that your current network allows Apple authentication traffic."
                )
            case .unacceptableStatusCode(let code, let data):
                let serverMessage = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                throw AppError(
                    title: "Authentication Request Rejected",
                    message: serverMessage?.isEmpty == false ? "HTTP \(code): \(serverMessage!)" : "HTTP \(code) was returned by the Apple authentication service.",
                    recoverySuggestion: "Verify the Apple ID, password, verification code, and private login protocol compatibility."
                )
            case .invalidResponse, .transport:
                throw AppError(
                    title: "Authentication Transport Failed",
                    message: error.localizedDescription,
                    recoverySuggestion: "If ipatool.js can reach Apple services on this Mac, verify that you are launching a rebuilt app bundle with the updated network entitlement. Otherwise check reachability to auth.itunes.apple.com before retrying."
                )
            }
        } catch {
            await logger.append(level: .error, category: "auth", message: error.localizedDescription)
            if let appError = error as? AppError {
                throw appError
            }
            throw AppError(
                title: "Authentication Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Verify Keychain access, Apple credentials, and private login protocol compatibility."
            )
        }
    }

    func signOut() async {
        do {
            try await keychainStore.clear()
            clearAppleCookies()
            await logger.append(level: .notice, category: "auth", message: "Removed the cached Apple ID credential from Keychain.")
        } catch {
            await logger.append(level: .error, category: "auth", message: "Failed to clear Keychain credential: \(error.localizedDescription)")
        }
    }
}

private func currentAppleCookies() -> [HTTPCookie] {
    let storage = HTTPCookieStorage.shared
    let urls = [
        URL(string: "https://auth.itunes.apple.com")!,
        URL(string: "https://buy.itunes.apple.com")!,
        URL(string: "https://p25-buy.itunes.apple.com")!,
    ]

    var cookiesByIdentity: [String: HTTPCookie] = [:]
    for url in urls {
        for cookie in storage.cookies(for: url) ?? [] {
            let key = "\(cookie.domain)|\(cookie.path)|\(cookie.name)"
            cookiesByIdentity[key] = cookie
        }
    }
    return Array(cookiesByIdentity.values)
}

private func clearAppleCookies() {
    let storage = HTTPCookieStorage.shared
    for cookie in currentAppleCookies() {
        storage.deleteCookie(cookie)
    }
}
