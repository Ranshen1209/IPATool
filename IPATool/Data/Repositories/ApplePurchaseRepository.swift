import Foundation

struct ApplePurchaseRepository: PurchaseServicing {
    let gateway: ApplePurchaseGateway
    let logger: LoggingServicing

    func requestLicense(appID: String, versionID: String?, session: AppSession) async throws -> PurchaseLicense {
        guard !appID.isEmpty else {
            throw AppError(
                title: "App ID Required",
                message: "Choose an app before requesting its download license.",
                recoverySuggestion: "Search for an app and select a version first."
            )
        }

        do {
            let response = try await gateway.purchase(
                request: StorePurchaseRequestDTO(appID: appID, versionID: versionID, guid: session.guid),
                context: StoreProtocolContext(session: session)
            )
            await logger.append(
                level: .info,
                category: "purchase",
                message: "Apple purchase response for \(appID) version \(versionID ?? "latest"): status=\(response.status.map(String.init) ?? "nil"), failureType=\(response.failureType ?? "nil"), message=\(response.customerMessage ?? "nil")"
            )

            if response.isSuccessfulLicenseResponse {
                let state: PurchaseLicenseState = response.failureType == "5002" || response.failureType == "2040" ? .alreadyOwned : .licensed
                let normalizedMessage: String
                if response.failureType == "5002" || response.failureType == "2040" {
                    normalizedMessage = "The app is already available in the current Apple account library."
                } else if let customerMessage = response.customerMessage, !customerMessage.isEmpty {
                    normalizedMessage = customerMessage
                } else {
                    normalizedMessage = "License request succeeded."
                }
                return PurchaseLicense(
                    state: state,
                    message: normalizedMessage,
                    failureType: response.failureType
                )
            }

            if response.failureType == "2034" {
                throw AppError(
                    title: "Purchase Session Expired",
                    message: response.customerMessage ?? "Apple asked the client to sign in to the iTunes Store again before requesting the license.",
                    recoverySuggestion: "Sign in again to refresh the private purchase session, then retry the version-specific license request."
                )
            }

            throw AppError(
                title: "License Request Failed",
                message: response.customerMessage ?? "The purchase gateway rejected the request.",
                recoverySuggestion: "Review the account state and private protocol mapping before retrying."
            )
        } catch let error as ProtocolAdapterError {
            await logger.append(level: .notice, category: "purchase", message: error.localizedDescription)
            throw AppError(
                title: "Protocol Adapter Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the private purchase protocol mapping and account state before retrying."
            )
        } catch {
            await logger.append(level: .error, category: "purchase", message: error.localizedDescription)
            throw error
        }
    }
}
