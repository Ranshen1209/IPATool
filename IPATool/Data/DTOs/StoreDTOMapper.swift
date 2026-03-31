import Foundation

enum StoreDTOMapper {
    nonisolated static func mapSession(from response: StoreLoginResponseDTO, guid: String) -> AppSession {
        AppSession(
            appleID: response.accountInfo.appleID,
            displayName: "\(response.accountInfo.address.firstName) \(response.accountInfo.address.lastName)".trimmingCharacters(in: .whitespaces),
            dsid: response.dsPersonID,
            guid: guid,
            storeFront: response.storeFront,
            authHeaders: response.authHeaders
        )
    }

    nonisolated static func mapVersions(from response: StoreAppInfoResponseDTO) -> [AppVersion] {
        var versions: [AppVersion] = []
        var seenIDs = Set<String>()

        for song in response.songs {
            let primary = AppVersion(
                id: "\(song.adamID)-\(song.externalVersionID)",
                appID: song.adamID,
                displayName: song.metadata.bundleDisplayName,
                bundleIdentifier: song.metadata.bundleIdentifier,
                version: song.metadata.bundleShortVersionString,
                externalVersionID: song.externalVersionID,
                expectedMD5: song.md5,
                metadataValues: song.metadata.rawValues,
                signaturePayload: song.sinfs.first?.sinf,
                downloadURL: song.downloadURL
            )

            if seenIDs.insert(primary.id).inserted {
                versions.append(primary)
            }

            for candidateVersionID in metadataCandidateVersionIDs(from: song.metadata.rawValues) where !candidateVersionID.isEmpty {
                let candidate = AppVersion(
                    id: "\(song.adamID)-\(candidateVersionID)",
                    appID: song.adamID,
                    displayName: song.metadata.bundleDisplayName,
                    bundleIdentifier: song.metadata.bundleIdentifier,
                    version: song.metadata.bundleShortVersionString,
                    externalVersionID: candidateVersionID,
                    expectedMD5: nil,
                    metadataValues: song.metadata.rawValues,
                    signaturePayload: nil,
                    downloadURL: nil
                )
                if seenIDs.insert(candidate.id).inserted {
                    versions.append(candidate)
                }
            }
        }

        return versions
    }

    nonisolated static func metadataCandidateVersionIDs(from metadata: [String: AppVersion.PropertyListValue]) -> [String] {
        var candidates: [String] = []

        if case .string(let value)? = metadata["softwareVersionExternalIdentifier"], !value.isEmpty {
            candidates.append(value)
        }
        if case .integer(let value)? = metadata["softwareVersionExternalIdentifier"] {
            candidates.append(String(value))
        }
        if case .array(let values)? = metadata["softwareVersionExternalIdentifiers"] {
            candidates.append(contentsOf: values.compactMap(versionIDString))
        }

        return Array(NSOrderedSet(array: candidates)) as? [String] ?? candidates
    }

    nonisolated private static func versionIDString(from value: AppVersion.PropertyListValue) -> String? {
        switch value {
        case .string(let value):
            value
        case .integer(let value):
            String(value)
        case .double(let value):
            String(Int(value))
        default:
            nil
        }
    }
}
