import Foundation

struct LoginUseCase: Sendable {
    let authService: AuthServicing
    let logger: LoggingServicing

    func execute(
        appleID: String,
        password: String,
        code: String?
    ) async throws -> AppSession {
        await logger.append(level: .info, category: "usecase.auth", message: "Beginning login use case for \(appleID).")

        do {
            let session = try await authService.signIn(
                appleID: appleID,
                password: password,
                code: code
            )
            await logger.append(level: .notice, category: "usecase.auth", message: "Login use case completed for \(session.appleID).")
            return session
        } catch {
            await logger.append(level: .error, category: "usecase.auth", message: "Login use case failed: \(error.localizedDescription)")
            throw error
        }
    }
}
