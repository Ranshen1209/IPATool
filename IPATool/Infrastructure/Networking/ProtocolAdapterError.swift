import Foundation

enum ProtocolAdapterError: LocalizedError, Sendable {
    case pendingRealAPIDetails(String)
    case privateProtocolRisk(String)
    case decodingFailure(String)

    var errorDescription: String? {
        switch self {
        case .pendingRealAPIDetails(let message):
            "Pending Real API Details: \(message)"
        case .privateProtocolRisk(let message):
            "Risky / Private / Compliance Sensitive: \(message)"
        case .decodingFailure(let message):
            "Protocol decoding failed: \(message)"
        }
    }
}
