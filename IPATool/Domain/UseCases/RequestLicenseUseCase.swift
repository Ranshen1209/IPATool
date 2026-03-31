import Foundation

struct RequestLicenseUseCase: Sendable {
    let purchaseService: PurchaseServicing
    let logger: LoggingServicing

    func execute(appID: String, versionID: String?, session: AppSession) async throws -> PurchaseLicense {
        await logger.append(level: .info, category: "usecase.purchase", message: "Requesting license for \(appID) version \(versionID ?? "latest").")

        do {
            let license = try await purchaseService.requestLicense(appID: appID, versionID: versionID, session: session)
            await logger.append(level: .notice, category: "usecase.purchase", message: "License state: \(license.state.displayTitle).")
            return license
        } catch {
            await logger.append(level: .error, category: "usecase.purchase", message: "License request failed: \(error.localizedDescription)")
            throw error
        }
    }
}
