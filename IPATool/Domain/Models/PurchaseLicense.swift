import Foundation

enum PurchaseLicenseState: String, Sendable, Codable {
    case notRequested
    case requesting
    case licensed
    case alreadyOwned
    case failed

    var displayTitle: String {
        switch self {
        case .notRequested:
            "Not Requested"
        case .requesting:
            "Requesting"
        case .licensed:
            "Licensed"
        case .alreadyOwned:
            "Already Owned"
        case .failed:
            "Failed"
        }
    }
}

struct PurchaseLicense: Sendable, Equatable {
    var state: PurchaseLicenseState
    var message: String
    var failureType: String?

    static let idle = PurchaseLicense(
        state: .notRequested,
        message: "No license request has been sent yet.",
        failureType: nil
    )
}
