import Foundation
import Security

protocol CredentialStoring: Sendable {
    func loadCredential() async throws -> KeychainCredentialStore.StoredCredential?
    func saveCredential(_ credential: KeychainCredentialStore.StoredCredential) async throws
    func loadSession() async throws -> KeychainCredentialStore.StoredSession?
    func saveSession(_ session: KeychainCredentialStore.StoredSession) async throws
    func clear() async throws
}

actor KeychainCredentialStore: CredentialStoring {
    struct StoredCredential: Sendable, Equatable {
        var appleID: String
        var password: String
        var verificationCode: String?
    }

    struct StoredSession: Sendable, Codable {
        struct StoredCookie: Sendable, Codable {
            var name: String
            var value: String
            var domain: String
            var path: String
            var expiresDate: Date?
            var isSecure: Bool
            var isHTTPOnly: Bool

            init(cookie: HTTPCookie) {
                self.name = cookie.name
                self.value = cookie.value
                self.domain = cookie.domain
                self.path = cookie.path
                self.expiresDate = cookie.expiresDate
                self.isSecure = cookie.isSecure
                self.isHTTPOnly = cookie.isHTTPOnly
            }

            var httpCookie: HTTPCookie? {
                var properties: [HTTPCookiePropertyKey: Any] = [
                    .name: name,
                    .value: value,
                    .domain: domain,
                    .path: path,
                    .secure: isSecure ? "TRUE" : "FALSE",
                ]
                if let expiresDate {
                    properties[.expires] = expiresDate
                }
                if isHTTPOnly {
                    properties[HTTPCookiePropertyKey("HttpOnly")] = "TRUE"
                }
                return HTTPCookie(properties: properties)
            }
        }

        var session: AppSession
        var cookies: [StoredCookie]
    }

    enum KeychainError: LocalizedError {
        case invalidPasswordEncoding
        case unexpectedData
        case unhandledStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidPasswordEncoding:
                "The password could not be encoded for secure storage."
            case .unexpectedData:
                "Keychain returned an unexpected credential payload."
            case .unhandledStatus(let status):
                SecCopyErrorMessageString(status, nil) as String? ?? "Keychain failed with status \(status)."
            }
        }
    }

    private let credentialService = "com.ranshen.IPATool.appleid"
    private let sessionService = "com.ranshen.IPATool.appleid.session"

    private struct StoredCredentialPayload: Codable {
        var password: String
        var verificationCode: String?
    }

    func loadCredential() throws -> StoredCredential? {
        guard let item = try loadItem(service: credentialService) else { return nil }
        guard
            let account = item[kSecAttrAccount as String] as? String,
            let data = item[kSecValueData as String] as? Data
        else {
            throw KeychainError.unexpectedData
        }

        if let payload = try? JSONDecoder().decode(StoredCredentialPayload.self, from: data) {
            return StoredCredential(
                appleID: account,
                password: payload.password,
                verificationCode: payload.verificationCode
            )
        }

        if let password = String(data: data, encoding: .utf8) {
            return StoredCredential(appleID: account, password: password, verificationCode: nil)
        }

        throw KeychainError.unexpectedData
    }

    func saveCredential(_ credential: StoredCredential) throws {
        guard credential.password.data(using: .utf8) != nil else {
            throw KeychainError.invalidPasswordEncoding
        }

        let payloadData = try JSONEncoder().encode(
            StoredCredentialPayload(
                password: credential.password,
                verificationCode: credential.verificationCode
            )
        )

        let attributes: [String: Any] = [
            kSecAttrAccount as String: credential.appleID,
            kSecValueData as String: payloadData,
        ]
        try saveItem(service: credentialService, account: credential.appleID, attributes: attributes)
    }

    func loadSession() throws -> StoredSession? {
        guard let item = try loadItem(service: sessionService) else { return nil }
        guard let data = item[kSecValueData as String] as? Data else {
            throw KeychainError.unexpectedData
        }
        do {
            return try JSONDecoder().decode(StoredSession.self, from: data)
        } catch {
            throw KeychainError.unexpectedData
        }
    }

    func saveSession(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let account = session.session.appleID.isEmpty ? "session" : session.session.appleID
        let attributes: [String: Any] = [
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
        ]
        try saveItem(service: sessionService, account: account, attributes: attributes)
    }

    func clear() throws {
        for service in [credentialService, sessionService] {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
            ]

            let status = SecItemDelete(query as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.unhandledStatus(status)
            }
        }
    }

    private func loadItem(service: String) throws -> [String: Any]? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let dictionary = item as? [String: Any] else {
                throw KeychainError.unexpectedData
            }
            return dictionary
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    private func saveItem(service: String, account: String, attributes: [String: Any]) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecAttrAccount as String] = account
            attributes.forEach { addQuery[$0.key] = $0.value }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainError.unhandledStatus(updateStatus)
        }
    }
}
