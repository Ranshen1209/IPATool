import Foundation

protocol PurchaseServicing: Sendable {
    func requestLicense(appID: String, versionID: String?, session: AppSession) async throws -> PurchaseLicense
}
