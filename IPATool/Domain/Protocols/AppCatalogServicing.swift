import Foundation

protocol AppCatalogServicing: Sendable {
    func search(appID: String, session: AppSession) async throws -> [AppVersion]
    func loadVersion(appID: String, versionID: String, session: AppSession) async throws -> AppVersion
    func loadDownloadableVersion(appID: String, session: AppSession) async throws -> AppVersion
}
