import Foundation

protocol IPAProcessingServicing: Sendable {
    func processDownloadedIPA(at ipaURL: URL, version: AppVersion, appleID: String) async throws
}
