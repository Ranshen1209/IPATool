import Foundation

struct AppSession: Sendable, Equatable, Codable {
    var appleID: String
    var displayName: String
    var dsid: String
    var guid: String
    var storeFront: String?
    var authHeaders: [String: String]
}
