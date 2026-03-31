import Foundation

protocol AppleAuthenticationGateway: Sendable {
    func login(request: StoreLoginRequestDTO) async throws -> StoreLoginResponseDTO
}

protocol AppleCatalogGateway: Sendable {
    func appInfo(request: StoreAppInfoRequestDTO, context: StoreProtocolContext) async throws -> StoreAppInfoResponseDTO
}

protocol ApplePurchaseGateway: Sendable {
    func purchase(request: StorePurchaseRequestDTO, context: StoreProtocolContext) async throws -> StorePurchaseResponseDTO
}

struct PendingAppleAuthenticationGateway: AppleAuthenticationGateway {
    let httpClient: HTTPClient

    func login(request: StoreLoginRequestDTO) async throws -> StoreLoginResponseDTO {
        guard let url = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast?guid=\(request.guid)") else {
            throw HTTPClientError.transport("The Apple authentication URL could not be constructed.")
        }

        let body = try ApplePropertyListCodec.encode([
            "appleId": request.appleID,
            "attempt": 1,
            "createSession": "true",
            "guid": request.guid,
            "password": request.password + (request.verificationCode ?? ""),
            "rmp": 0,
            "why": "signIn",
        ])

        let response = try await httpClient.send(
            HTTPRequest(
                url: url,
                method: .post,
                headers: [
                    "User-Agent": "Configurator/2.15 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8",
                    "Content-Type": "application/x-www-form-urlencoded",
                ],
                body: body,
                timeoutInterval: 30
            )
        )

        let dictionary = try ApplePropertyListCodec.decodeDictionary(from: response.body)
        return StoreLoginResponseDTO(dictionary: dictionary, headers: response.headers)
    }
}

struct PendingAppleCatalogGateway: AppleCatalogGateway {
    let httpClient: HTTPClient

    func appInfo(request: StoreAppInfoRequestDTO, context: StoreProtocolContext) async throws -> StoreAppInfoResponseDTO {
        guard let url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(request.guid)") else {
            throw HTTPClientError.transport("The Apple catalog URL could not be constructed.")
        }

        var payload: [String: Any] = [
            "creditDisplay": "",
            "guid": request.guid,
            "salableAdamId": request.appID,
        ]
        if let versionID = request.versionID, !versionID.isEmpty {
            payload["externalVersionId"] = versionID
        }

        let body = try ApplePropertyListCodec.encode(payload)

        let response = try await httpClient.send(
            HTTPRequest(
                url: url,
                method: .post,
                headers: mergedHeaders(
                    base: context.authHeaders,
                    requestURL: url,
                    extra: [
                    "User-Agent": "Configurator/2.15 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8",
                    "Content-Type": "application/x-www-form-urlencoded",
                    ]
                ),
                body: body,
                timeoutInterval: 30
            )
        )

        let dictionary = try ApplePropertyListCodec.decodeDictionary(from: response.body)
        return StoreAppInfoResponseDTO(dictionary: dictionary)
    }
}

struct PendingApplePurchaseGateway: ApplePurchaseGateway {
    let httpClient: HTTPClient

    func purchase(request: StorePurchaseRequestDTO, context: StoreProtocolContext) async throws -> StorePurchaseResponseDTO {
        guard let url = URL(string: "https://buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/buyProduct") else {
            throw HTTPClientError.transport("The Apple purchase URL could not be constructed.")
        }

        var payload: [String: Any] = [
            "appExtVrsId": request.versionID?.isEmpty == false ? request.versionID! : "0",
            "buyWithoutAuthorization": "true",
            "hasAskedToFulfillPreorder": "true",
            "hasDoneAgeCheck": "true",
            "price": "0",
            "pricingParameters": "STDQ",
            "productType": "C",
            "salableAdamId": request.appID,
            "guid": request.guid,
        ]

        if payload["appExtVrsId"] == nil {
            payload["appExtVrsId"] = "0"
        }

        let body = try ApplePropertyListCodec.encode(payload)

        let response = try await httpClient.send(
            HTTPRequest(
                url: url,
                method: .post,
                headers: mergedHeaders(
                    base: context.authHeaders,
                    requestURL: url,
                    extra: [
                    "User-Agent": "Configurator/2.15 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8",
                    "Content-Type": "application/x-www-form-urlencoded",
                    ]
                ),
                body: body,
                timeoutInterval: 30
            )
        )

        let dictionary = try ApplePropertyListCodec.decodeDictionary(from: response.body)
        return StorePurchaseResponseDTO(dictionary: dictionary)
    }
}

private func mergedHeaders(base: [String: String], requestURL: URL, extra: [String: String]) -> [String: String] {
    var headers = base.merging(extra) { _, new in new }
    if let cookieHeader = cookieHeader(for: requestURL), !cookieHeader.isEmpty {
        headers["Cookie"] = cookieHeader
    }
    return headers
}

private func cookieHeader(for url: URL) -> String? {
    let cookies = HTTPCookieStorage.shared.cookies(for: url) ?? []
    guard !cookies.isEmpty else { return nil }
    return cookies
        .map { "\($0.name)=\($0.value)" }
        .joined(separator: "; ")
}
