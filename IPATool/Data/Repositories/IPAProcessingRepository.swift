import Foundation

enum IPAProcessingError: LocalizedError {
    case missingAppleID
    case missingSignaturePayload

    var errorDescription: String? {
        switch self {
        case .missingAppleID:
            "The IPA rewrite step requires a signed-in Apple ID."
        case .missingSignaturePayload:
            "The selected app version does not include signature payload data."
        }
    }
}

struct IPAProcessingRepository: IPAProcessingServicing {
    let verifier: FileIntegrityVerifier
    let archiveRewriter: IPAArchiveRewriter
    let logger: LoggingServicing

    func processDownloadedIPA(at ipaURL: URL, version: AppVersion, appleID: String) async throws {
        let expectedMD5 = version.expectedMD5
        let signaturePayload = version.signaturePayload
        let metadata = buildMetadata(for: version, appleID: appleID)

        await logger.append(
            level: .info,
            category: "ipa.rewrite",
            message: "Preparing IPA processing for \(ipaURL.lastPathComponent). hasMD5=\(version.expectedMD5 != nil) hasSINF=\(version.signaturePayload != nil) metadataKeys=\(version.metadataValues.count)"
        )

        guard let signaturePayload else {
            await logger.append(level: .error, category: "ipa.rewrite", message: "Missing `sinf` payload for \(ipaURL.lastPathComponent).")
            throw IPAProcessingError.missingSignaturePayload
        }

        try await Task.detached(priority: .utility) {
            if let expectedMD5 {
                try verifier.verifyMD5(of: ipaURL, expectedHex: expectedMD5)
            }

            try archiveRewriter.rewriteIPA(
                at: ipaURL,
                metadata: metadata,
                signaturePayload: signaturePayload
            )
        }.value

        if expectedMD5 != nil {
            await logger.append(level: .notice, category: "ipa.verify", message: "Verified MD5 for \(ipaURL.lastPathComponent).")
        } else {
            await logger.append(level: .info, category: "ipa.verify", message: "Skipped MD5 verification because the current version did not provide a checksum.")
        }

        await logger.append(level: .notice, category: "ipa.rewrite", message: "Rewrote IPA metadata and signature payload for \(ipaURL.lastPathComponent).")
    }

    private func buildMetadata(for version: AppVersion, appleID: String) -> [String: Any] {
        var metadata: [String: Any] = version.metadataValues.reduce(into: [:]) { partialResult, pair in
            partialResult[pair.key] = pair.value.foundationValue
        }
        metadata["bundleDisplayName"] = metadata["bundleDisplayName"] ?? version.displayName
        metadata["bundleIdentifier"] = metadata["bundleIdentifier"] ?? version.bundleIdentifier
        metadata["bundleShortVersionString"] = metadata["bundleShortVersionString"] ?? version.version
        metadata["apple-id"] = appleID
        metadata["userName"] = appleID
        metadata["appleId"] = appleID
        metadata["com.apple.iTunesStore.downloadInfo"] = [
            "accountInfo": [
                "AppleID": appleID,
            ],
        ]
        return metadata
    }
}
