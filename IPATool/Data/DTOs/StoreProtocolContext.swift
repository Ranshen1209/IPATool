import Foundation

struct StoreProtocolContext: Sendable, Equatable {
    var guid: String
    var authHeaders: [String: String]

    init(guid: String, authHeaders: [String: String]) {
        self.guid = guid
        self.authHeaders = authHeaders
    }

    init(session: AppSession) {
        self.guid = session.guid
        self.authHeaders = session.authHeaders
    }
}
