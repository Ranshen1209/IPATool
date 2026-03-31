import Foundation

enum OperationalRiskLevel: String, Sendable, Codable, CaseIterable {
    case stable = "Stable"
    case pendingRealAPIDetails = "Pending Real API Details"
    case riskyPrivateComplianceSensitive = "Risky / Private / Compliance Sensitive"
}

struct OperationalRisk: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let level: OperationalRiskLevel
    let summary: String
    let impact: String
    let recommendation: String
}

enum OperationalRiskCatalog {
    static let items: [OperationalRisk] = [
        OperationalRisk(
            id: "local-download-pipeline",
            title: "Chunked local download pipeline",
            level: .stable,
            summary: "Range planning, retries, merge, cache cleanup, and task persistence are implemented in the native downloader.",
            impact: "This path is suitable for local verification, task history, and desktop-task orchestration.",
            recommendation: "Keep validating with fixture downloads and grow coverage around resume and failure cases."
        ),
        OperationalRisk(
            id: "sandbox-folder-access",
            title: "Sandbox-aware folder access",
            level: .stable,
            summary: "User-selected output and cache directories are persisted with security-scoped bookmarks and restored during app bootstrap.",
            impact: "The app can keep writing to previously approved locations across launches in the current sandbox design.",
            recommendation: "Use explicit folder selection instead of hard-coded paths when preparing a signed distribution."
        ),
        OperationalRisk(
            id: "cold-start-resume-context",
            title: "Cold-start download resume context",
            level: .pendingRealAPIDetails,
            summary: "Resume metadata is now persisted with each task, but real Apple protocol sessions and expiring authorization state are still not restorable from public APIs.",
            impact: "Local fixture downloads can recover cleanly. Real network resume remains dependent on unpublished server behavior.",
            recommendation: "Treat resume for Apple-hosted assets as best-effort until a verified, legal protocol contract exists."
        ),
        OperationalRisk(
            id: "apple-login-protocol",
            title: "Apple ID authentication protocol",
            level: .pendingRealAPIDetails,
            summary: "ipatool.js depends on plist bodies, cookies, and response fields that are not exposed as a stable public SDK for macOS apps.",
            impact: "A production login implementation cannot be claimed complete without live protocol validation and legal review.",
            recommendation: "Keep the gateway isolated behind protocol adapters. Do not present it as a stable end-user feature."
        ),
        OperationalRisk(
            id: "private-storefront-protocol",
            title: "Storefront lookup and purchase APIs",
            level: .riskyPrivateComplianceSensitive,
            summary: "Lookup, license acquisition, and download authorization appear to rely on private or unpublished Apple service contracts.",
            impact: "These capabilities may break without notice, risk account safety, and are likely incompatible with App Store review expectations.",
            recommendation: "Position the app as an internal or developer-distributed tool unless these flows are replaced with public APIs."
        ),
        OperationalRisk(
            id: "ipa-signature-rewrite",
            title: "IPA metadata and signature rewriting",
            level: .riskyPrivateComplianceSensitive,
            summary: "Writing `SC_Info`, `sinf`, and store metadata mirrors behavior from tooling that operates outside standard App Store distribution paths.",
            impact: "This is policy-sensitive and should be treated as a developer utility capability rather than a general consumer feature.",
            recommendation: "Gate this workflow with explicit operator acknowledgement and distribute outside the Mac App Store."
        ),
    ]
}
