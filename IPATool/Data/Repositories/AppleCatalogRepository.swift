import Foundation

struct AppleCatalogRepository: AppCatalogServicing {
    let gateway: AppleCatalogGateway
    let httpClient: HTTPClient
    let logger: LoggingServicing

    func search(appID: String, session: AppSession) async throws -> [AppVersion] {
        try await performLookup(appID: appID, versionID: nil, session: session, allowsPublicFallback: true)
    }

    func loadVersion(appID: String, versionID: String, session: AppSession) async throws -> AppVersion {
        let response = try await fetchLookup(appID: appID, versionID: versionID, session: session, allowsPublicFallback: false)
        let versions = normalizeRequestedVersions(StoreDTOMapper.mapVersions(from: response), requestedVersionID: versionID)
        let authoritativeVersionIDs = authoritativeVersionIDs(from: response, normalizedVersions: versions)
        guard authoritativeVersionIDs.contains(versionID),
              let version = versions.first(where: { $0.externalVersionID == versionID }) else {
            throw AppError(
                title: "Catalog Lookup Failed",
                message: "Apple did not return the requested version \(versionID) for app \(appID). The private catalog responded with version IDs: \(authoritativeVersionIDs.sorted().joined(separator: ", ")).",
                recoverySuggestion: "Verify that the version ID is still valid for the current storefront and account, then retry or fall back to the latest downloadable build."
            )
        }
        return version
    }

    func loadDownloadableVersion(appID: String, session: AppSession) async throws -> AppVersion {
        let versions = try await performLookup(appID: appID, versionID: nil, session: session, allowsPublicFallback: false)
        if let version = versions.first(where: { $0.downloadURL != nil && $0.signaturePayload != nil }) {
            return version
        }
        if let version = versions.first(where: { $0.downloadURL != nil }) {
            return version
        }
        throw AppError(
            title: "Download URL Missing",
            message: "The Apple catalog did not expose any downloadable version with a live asset URL for app \(appID).",
            recoverySuggestion: "Retry the license request, then refresh the catalog again and confirm the current account can access the target asset."
        )
    }

    private func performLookup(appID: String, versionID: String?, session: AppSession, allowsPublicFallback: Bool) async throws -> [AppVersion] {
        let response = try await fetchLookup(appID: appID, versionID: versionID, session: session, allowsPublicFallback: allowsPublicFallback)
        return StoreDTOMapper.mapVersions(from: response)
    }

    private func fetchLookup(appID: String, versionID: String?, session: AppSession, allowsPublicFallback: Bool) async throws -> StoreAppInfoResponseDTO {
        guard !appID.isEmpty else {
            return StoreAppInfoResponseDTO(
                failureType: nil,
                customerMessage: nil,
                status: nil,
                authorized: nil,
                songs: [],
                rawTopLevelKeys: [],
                rawSongCount: 0,
                rawSongSampleKeys: [],
                rawSongValueType: "empty"
            )
        }

        do {
            let response = try await gateway.appInfo(
                request: StoreAppInfoRequestDTO(appID: appID, versionID: versionID, guid: session.guid),
                context: StoreProtocolContext(session: session)
            )
            await logger.append(
                level: .info,
                category: "search",
                message: "Apple catalog response for \(appID) parsed \(response.songs.count)/\(response.rawSongCount) song entries. status=\(response.status.map(String.init) ?? "nil") authorized=\(response.authorized.map(String.init) ?? "nil") failureType=\(response.failureType ?? "nil") customerMessage=\(response.customerMessage ?? "nil") songValueType=\(response.rawSongValueType) songKeys=\(response.rawSongSampleKeys.joined(separator: ",")) topLevelKeys=\(response.rawTopLevelKeys.joined(separator: ","))"
            )
            if let customerMessage = response.customerMessage,
               !customerMessage.isEmpty,
               !(versionID == nil && (response.failureType == "5002" || response.failureType == "2040")) {
                throw AppError(
                    title: "Catalog Lookup Failed",
                    message: customerMessage,
                    recoverySuggestion: "Verify the app ID, storefront, and current account access before retrying."
                )
            }
            let versions = StoreDTOMapper.mapVersions(from: response)
            if let first = versions.first {
                let metadataKeys = first.metadataValues.keys.sorted().joined(separator: ",")
                await logger.append(
                    level: .info,
                    category: "search",
                    message: "First version payload: versionID=\(first.externalVersionID), hasURL=\(first.downloadURL != nil), hasMD5=\(first.expectedMD5 != nil), hasSINF=\(first.signaturePayload != nil), bundleID=\(first.bundleIdentifier.isEmpty ? "<missing>" : first.bundleIdentifier), metadataKeys=\(metadataKeys)"
                )
            }
            if let versionID, versions.contains(where: { $0.externalVersionID == versionID }) {
                await logger.append(
                    level: .notice,
                    category: "search",
                    message: "Normalized the requested version \(versionID) against the Apple catalog response for \(appID)."
                )
            }
            guard !versions.isEmpty else {
                if response.rawSongCount > 0 {
                    throw AppError(
                        title: "Catalog Mapping Failed",
                        message: "The Apple catalog returned \(response.rawSongCount) raw song entries for app \(appID), but none could be mapped into downloadable versions. Raw song keys: \(response.rawSongSampleKeys.joined(separator: ","))",
                        recoverySuggestion: "Inspect the current private catalog payload shape and extend the DTO mapping before retrying the download flow."
                    )
                }
                if allowsPublicFallback, versionID == nil {
                    return try await fallbackLookup(appID: appID)
                }
                throw AppError(
                    title: "Catalog Lookup Failed",
                    message: "The Apple catalog response did not contain any downloadable versions for app \(appID).",
                    recoverySuggestion: "Verify the app ID, version selection, storefront, and account entitlements before retrying."
                )
            }
            return response
        } catch let error as ProtocolAdapterError {
            await logger.append(level: .notice, category: "search", message: error.localizedDescription)
            throw AppError(
                title: "Protocol Adapter Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the private catalog protocol mapping and account state before retrying."
            )
        } catch let error as AppError {
            await logger.append(level: .error, category: "search", message: error.message)
            throw error
        } catch {
            await logger.append(level: .error, category: "search", message: error.localizedDescription)
            throw AppError(
                title: "Catalog Lookup Failed",
                message: error.localizedDescription,
                recoverySuggestion: "Review the Apple catalog response, account state, and DTO mapping before retrying."
            )
        }
    }

    private func fallbackLookup(appID: String) async throws -> StoreAppInfoResponseDTO {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(appID)&entity=software") else {
            throw AppError(
                title: "Catalog Lookup Failed",
                message: "The fallback lookup URL could not be constructed.",
                recoverySuggestion: "Retry the search with a numeric App ID."
            )
        }

        let response = try await httpClient.send(
            HTTPRequest(
                url: url,
                method: .get,
                headers: ["Accept": "application/json"],
                timeoutInterval: 30
            )
        )

        let object = try JSONSerialization.jsonObject(with: response.body)
        guard let dictionary = object as? [String: Any] else {
            throw AppError(
                title: "Catalog Lookup Failed",
                message: "The public iTunes Lookup response was not a JSON dictionary.",
                recoverySuggestion: "Retry the search and inspect the lookup response if the problem persists."
            )
        }

        let rawResults = dictionary["results"] as? [[String: Any]] ?? []
        await logger.append(
            level: .info,
            category: "search",
            message: "Public iTunes Lookup returned \(rawResults.count) result entries for \(appID)."
        )

        guard let app = rawResults.compactMap(PublicLookupApp.init).first else {
            let firstKeys = rawResults.first.map { Array($0.keys).sorted().joined(separator: ",") } ?? "none"
            throw AppError(
                title: "Catalog Lookup Failed",
                message: "Neither the private catalog nor the public iTunes lookup API returned a usable app payload for \(appID). First result keys: \(firstKeys)",
                recoverySuggestion: "Verify the numeric App ID and current storefront availability before retrying."
            )
        }

        await logger.append(
            level: .notice,
            category: "search",
            message: "Private catalog returned no downloadable versions for \(appID). Falling back to public iTunes Lookup metadata."
        )

        return StoreAppInfoResponseDTO(
            failureType: nil,
            customerMessage: nil,
            status: 0,
            authorized: nil,
            songs: [
                .init(
                    adamID: appID,
                    externalVersionID: "",
                    downloadURL: nil,
                    md5: nil,
                    metadata: .init(
                        bundleDisplayName: app.trackName,
                        bundleIdentifier: app.bundleIdentifier,
                        bundleShortVersionString: app.version,
                        rawValues: [
                            "bundleDisplayName": .string(app.trackName),
                            "bundleIdentifier": .string(app.bundleIdentifier),
                            "bundleShortVersionString": .string(app.version),
                        ]
                    ),
                    sinfs: []
                )
            ],
            rawTopLevelKeys: ["results"],
            rawSongCount: 1,
            rawSongSampleKeys: ["bundleDisplayName", "bundleIdentifier", "bundleShortVersionString"],
            rawSongValueType: "publicLookupFallback"
        )
    }

    private func normalizeRequestedVersions(_ versions: [AppVersion], requestedVersionID: String) -> [AppVersion] {
        versions.map { version in
            guard version.externalVersionID == "0" || version.externalVersionID.isEmpty else {
                return version
            }
            let metadataVersionIDs = StoreDTOMapper.metadataCandidateVersionIDs(from: version.metadataValues)
            guard metadataVersionIDs.contains(requestedVersionID) else {
                return version
            }
            return AppVersion(
                id: "\(version.appID)-\(requestedVersionID)",
                appID: version.appID,
                displayName: version.displayName,
                bundleIdentifier: version.bundleIdentifier,
                version: version.version,
                externalVersionID: requestedVersionID,
                expectedMD5: version.expectedMD5,
                metadataValues: version.metadataValues,
                signaturePayload: version.signaturePayload,
                downloadURL: version.downloadURL
            )
        }
    }

    private func authoritativeVersionIDs(from response: StoreAppInfoResponseDTO, normalizedVersions: [AppVersion]) -> Set<String> {
        var ids = Set(response.songs.map(\.externalVersionID))
        for version in normalizedVersions where !version.externalVersionID.isEmpty {
            ids.insert(version.externalVersionID)
        }
        return ids
    }
}

private struct PublicLookupApp {
    let trackName: String
    let bundleIdentifier: String
    let version: String

    init?(dictionary: [String: Any]) {
        let wrapperType = dictionary["wrapperType"] as? String
        let kind = dictionary["kind"] as? String
        let trackID = (dictionary["trackId"] as? NSNumber)?.stringValue ?? (dictionary["trackId"] as? String)
        let bundleIdentifier = dictionary["bundleId"] as? String ?? dictionary["bundleIdentifier"] as? String
        let trackName = dictionary["trackName"] as? String
        let version = dictionary["version"] as? String

        guard trackID != nil else { return nil }
        if let wrapperType, wrapperType != "software" && wrapperType != "track" {
            return nil
        }
        if let kind,
           !kind.localizedCaseInsensitiveContains("software"),
           !kind.localizedCaseInsensitiveContains("mac-software") {
            return nil
        }
        guard
            let trackName, !trackName.isEmpty,
            let bundleIdentifier, !bundleIdentifier.isEmpty,
            let version, !version.isEmpty
        else {
            return nil
        }

        self.trackName = trackName
        self.bundleIdentifier = bundleIdentifier
        self.version = version
    }
}
