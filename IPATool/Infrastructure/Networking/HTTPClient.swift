import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case head = "HEAD"
}

struct HTTPRequest: Sendable {
    var url: URL
    var method: HTTPMethod
    var headers: [String: String]
    var body: Data?
    var timeoutInterval: TimeInterval

    nonisolated init(
        url: URL,
        method: HTTPMethod = .get,
        headers: [String: String] = [:],
        body: Data? = nil,
        timeoutInterval: TimeInterval = 30
    ) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
        self.timeoutInterval = timeoutInterval
    }
}

struct HTTPResponse: Sendable {
    var request: HTTPRequest
    var statusCode: Int
    var headers: [String: String]
    var body: Data
}

enum HTTPClientError: LocalizedError, Sendable {
    case invalidResponse
    case unacceptableStatusCode(Int, Data)
    case hostNotFound(String)
    case networkUnavailable(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "The server response was not a valid HTTP response."
        case .unacceptableStatusCode(let code, _):
            "The server returned an unexpected status code: \(code)."
        case .hostNotFound(let host):
            "The hostname \(host) could not be resolved."
        case .networkUnavailable(let message):
            message
        case .transport(let message):
            message
        }
    }
}

protocol HTTPClient: Sendable {
    func send(_ request: HTTPRequest) async throws -> HTTPResponse
}

struct URLSessionHTTPClient: HTTPClient {
    let session: URLSession
    let acceptedStatusCodes: Range<Int>

    init(
        session: URLSession = .shared,
        acceptedStatusCodes: Range<Int> = 200..<300
    ) {
        self.session = session
        self.acceptedStatusCodes = acceptedStatusCodes
    }

    func send(_ request: HTTPRequest) async throws -> HTTPResponse {
        var urlRequest = URLRequest(url: request.url, timeoutInterval: request.timeoutInterval)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }

        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw HTTPClientError.invalidResponse
            }
            guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
                throw HTTPClientError.unacceptableStatusCode(httpResponse.statusCode, data)
            }
            return HTTPResponse(
                request: request,
                statusCode: httpResponse.statusCode,
                headers: httpResponse.allHeaderFields.reduce(into: [:]) { partialResult, pair in
                    if let key = pair.key as? String {
                        partialResult[key] = String(describing: pair.value)
                    }
                },
                body: data
            )
        } catch let error as HTTPClientError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .cannotFindHost, .dnsLookupFailed:
                throw HTTPClientError.hostNotFound(request.url.host ?? request.url.absoluteString)
            case .notConnectedToInternet, .internationalRoamingOff, .callIsActive, .dataNotAllowed:
                throw HTTPClientError.networkUnavailable(error.localizedDescription)
            default:
                throw HTTPClientError.transport(error.localizedDescription)
            }
        } catch {
            throw HTTPClientError.transport(error.localizedDescription)
        }
    }
}
