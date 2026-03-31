import Foundation

struct AppVersion: Identifiable, Hashable, Sendable, Codable {
    enum PropertyListValue: Hashable, Sendable, Codable {
        case string(String)
        case integer(Int)
        case double(Double)
        case boolean(Bool)
        case data(Data)
        case date(Date)
        case array([PropertyListValue])
        case dictionary([String: PropertyListValue])

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()

            if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode(Int.self) {
                self = .integer(value)
            } else if let value = try? container.decode(Double.self) {
                self = .double(value)
            } else if let value = try? container.decode(Bool.self) {
                self = .boolean(value)
            } else if let value = try? container.decode(Data.self) {
                self = .data(value)
            } else if let value = try? container.decode(Date.self) {
                self = .date(value)
            } else if let value = try? container.decode([PropertyListValue].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: PropertyListValue].self) {
                self = .dictionary(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported property list value.")
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .string(let value):
                try container.encode(value)
            case .integer(let value):
                try container.encode(value)
            case .double(let value):
                try container.encode(value)
            case .boolean(let value):
                try container.encode(value)
            case .data(let value):
                try container.encode(value)
            case .date(let value):
                try container.encode(value)
            case .array(let value):
                try container.encode(value)
            case .dictionary(let value):
                try container.encode(value)
            }
        }

        var foundationValue: Any {
            switch self {
            case .string(let value):
                value
            case .integer(let value):
                value
            case .double(let value):
                value
            case .boolean(let value):
                value
            case .data(let value):
                value
            case .date(let value):
                value
            case .array(let value):
                value.map(\.foundationValue)
            case .dictionary(let value):
                value.mapValues(\.foundationValue)
            }
        }
    }

    let id: String
    let appID: String
    let displayName: String
    let bundleIdentifier: String
    let version: String
    let externalVersionID: String
    let expectedMD5: String?
    let metadataValues: [String: PropertyListValue]
    let signaturePayload: String?
    let downloadURL: URL?
}
