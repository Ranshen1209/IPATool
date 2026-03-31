import Foundation

struct LoadCachedCredentialUseCase: Sendable {
    let keychainStore: CredentialStoring
    let logger: LoggingServicing

    func execute() async -> KeychainCredentialStore.StoredCredential? {
        do {
            let credential = try await keychainStore.loadCredential()
            if let credential {
                await logger.append(level: .info, category: "usecase.auth", message: "Loaded cached Apple ID \(credential.appleID).")
            } else {
                await logger.append(level: .debug, category: "usecase.auth", message: "No cached credential is available.")
            }
            return credential
        } catch {
            await logger.append(level: .error, category: "usecase.auth", message: "Failed to load cached credential: \(error.localizedDescription)")
            return nil
        }
    }
}
