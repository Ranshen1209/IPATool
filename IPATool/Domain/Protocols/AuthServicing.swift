import Foundation

protocol AuthServicing: Sendable {
    func signIn(appleID: String, password: String, code: String?) async throws -> AppSession
    func signOut() async
}
