import Foundation

struct StoreAppInfoRequestDTO: Sendable, Equatable {
    var appID: String
    var versionID: String?
    var guid: String
}

struct StoreAppInfoResponseDTO: Sendable, Equatable {
    struct SongDTO: Sendable, Equatable {
        struct MetadataDTO: Sendable, Equatable {
            var bundleDisplayName: String
            var bundleIdentifier: String
            var bundleShortVersionString: String
            var rawValues: [String: AppVersion.PropertyListValue]
        }

        struct SINFDTO: Sendable, Equatable {
            var sinf: String
        }

        var adamID: String
        var externalVersionID: String
        var downloadURL: URL?
        var md5: String?
        var metadata: MetadataDTO
        var sinfs: [SINFDTO]
    }

    var failureType: String?
    var customerMessage: String?
    var status: Int?
    var authorized: Bool?
    var songs: [SongDTO]
    var rawTopLevelKeys: [String]
    var rawSongCount: Int
    var rawSongSampleKeys: [String]
    var rawSongValueType: String

    init(
        failureType: String?,
        customerMessage: String?,
        status: Int?,
        authorized: Bool?,
        songs: [SongDTO],
        rawTopLevelKeys: [String],
        rawSongCount: Int,
        rawSongSampleKeys: [String],
        rawSongValueType: String
    ) {
        self.failureType = failureType
        self.customerMessage = customerMessage
        self.status = status
        self.authorized = authorized
        self.songs = songs
        self.rawTopLevelKeys = rawTopLevelKeys
        self.rawSongCount = rawSongCount
        self.rawSongSampleKeys = rawSongSampleKeys
        self.rawSongValueType = rawSongValueType
    }

    init(dictionary: [String: Any]) {
        self.failureType = Self.stringValue(in: dictionary, keys: ["failureType"])
        self.customerMessage = Self.stringValue(in: dictionary, keys: ["customerMessage"])
        self.status = dictionary["status"] as? Int ?? (dictionary["status"] as? NSNumber)?.intValue
        self.authorized = dictionary["authorized"] as? Bool ?? (dictionary["authorized"] as? NSNumber)?.boolValue
        self.rawTopLevelKeys = dictionary.keys.sorted()

        let rawSongItems = Self.arrayValue(in: dictionary, key: "songList")
        self.rawSongCount = rawSongItems.count
        self.rawSongValueType = {
            guard let first = rawSongItems.first else { return "empty" }
            return String(describing: type(of: first))
        }()
        self.rawSongSampleKeys = {
            guard let firstDictionary = Self.dictionaryValue(from: rawSongItems.first) else {
                return []
            }
            return firstDictionary.keys.sorted()
        }()
        self.songs = rawSongItems.compactMap(Self.parseSong)
    }

    nonisolated private static func parseSong(_ rawValue: Any) -> SongDTO? {
        guard let rawDictionary = dictionaryValue(from: rawValue) else {
            return nil
        }
        let dictionary = flattenedSongDictionary(from: rawDictionary)
        let adamID = stringValue(in: dictionary, keys: ["adamId", "adamID", "salableAdamId", "songId", "songID"]) ?? ""
        let fallbackAdamID = stringValue(in: dictionary, keys: ["item-id", "itemId", "id", "storeItemId", "download-id", "downloadId"])
        let externalVersionID = stringValue(in: dictionary, keys: ["externalVersionId", "externalVersionID", "appExtVrsId", "external-version-id"]) ?? "0"
        let urlString = stringValue(in: dictionary, keys: ["URL", "url", "downloadURL", "downloadUrl", "assetURL", "assetUrl"])
        let md5 = stringValue(in: dictionary, keys: ["md5", "MD5", "checksum", "fileChecksum"])
        let metadataDictionary = dictionaryValue(from: dictionary["metadata"]) ?? dictionaryValue(from: dictionary["softwareMetadata"]) ?? [:]
        let sinfValues = arrayValue(in: dictionary, key: "sinfs")

        let metadata = SongDTO.MetadataDTO(
            bundleDisplayName: stringValue(in: metadataDictionary, keys: ["bundleDisplayName"]) ?? stringValue(in: dictionary, keys: ["name"]) ?? "Unknown App",
            bundleIdentifier: stringValue(in: metadataDictionary, keys: ["bundleIdentifier"]) ?? "",
            bundleShortVersionString: stringValue(in: metadataDictionary, keys: ["bundleShortVersionString"]) ?? stringValue(in: dictionary, keys: ["version"]) ?? "",
            rawValues: metadataDictionary.reduce(into: [:]) { partialResult, pair in
                if let value = propertyListValue(from: pair.value) {
                    partialResult[pair.key] = value
                }
            }
        )

        let sinfs: [SongDTO.SINFDTO] = sinfValues.compactMap { item in
            if let dictionary = dictionaryValue(from: item),
               let sinf = signatureString(from: dictionary["sinf"]) ?? signatureString(from: dictionary["value"]) ?? stringValue(in: dictionary, keys: ["sinf", "value"]) {
                return SongDTO.SINFDTO(sinf: sinf)
            }
            if let sinf = signatureString(from: item) {
                return SongDTO.SINFDTO(sinf: sinf)
            }
            return nil
        }

        let resolvedAdamID = adamID.isEmpty ? (fallbackAdamID ?? "") : adamID
        guard !resolvedAdamID.isEmpty else {
            return nil
        }

        return SongDTO(
            adamID: resolvedAdamID,
            externalVersionID: externalVersionID,
            downloadURL: urlString.flatMap(URL.init(string:)),
            md5: md5,
            metadata: metadata,
            sinfs: sinfs
        )
    }

    nonisolated private static func stringValue(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let string = dictionary[key] as? String, !string.isEmpty {
                return string
            }
            if let number = dictionary[key] as? NSNumber {
                return number.stringValue
            }
        }
        return nil
    }

    nonisolated private static func arrayValue(in dictionary: [String: Any], key: String) -> [Any] {
        if let array = dictionary[key] as? [Any] {
            return array
        }
        if let array = dictionary[key] as? NSArray {
            return array.map { $0 }
        }
        return []
    }

    nonisolated private static func dictionaryValue(from value: Any?) -> [String: Any]? {
        switch value {
        case let dictionary as [String: Any]:
            dictionary
        case let dictionary as [AnyHashable: Any]:
            dictionary.reduce(into: [String: Any]()) { partialResult, pair in
                partialResult[String(describing: pair.key)] = pair.value
            }
        case let dictionary as NSDictionary:
            dictionary.reduce(into: [String: Any]()) { partialResult, pair in
                partialResult[String(describing: pair.key)] = pair.value
            }
        default:
            nil
        }
    }

    nonisolated private static func flattenedSongDictionary(from dictionary: [String: Any]) -> [String: Any] {
        if let nested = dictionaryValue(from: dictionary["song"]) {
            return nested.merging(dictionary) { current, _ in current }
        }
        if let nested = dictionaryValue(from: dictionary["item"]) {
            return nested.merging(dictionary) { current, _ in current }
        }
        return dictionary
    }

    nonisolated private static func propertyListValue(from value: Any) -> AppVersion.PropertyListValue? {
        switch value {
        case let value as String:
            .string(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() {
                .boolean(value.boolValue)
            } else if value.doubleValue.rounded(.towardZero) == value.doubleValue {
                .integer(value.intValue)
            } else {
                .double(value.doubleValue)
            }
        case let value as Data:
            .data(value)
        case let value as Date:
            .date(value)
        case let value as [Any]:
            .array(value.compactMap { propertyListValue(from: $0) })
        case let value as [String: Any]:
            .dictionary(value.reduce(into: [String: AppVersion.PropertyListValue]()) { partialResult, pair in
                if let nestedValue = propertyListValue(from: pair.value) {
                    partialResult[pair.key] = nestedValue
                }
            })
        default:
            nil
        }
    }

    nonisolated private static func signatureString(from value: Any?) -> String? {
        switch value {
        case let value as String where !value.isEmpty:
            value
        case let value as Data:
            value.base64EncodedString()
        case let value as NSData:
            Data(referencing: value).base64EncodedString()
        case let value as NSNumber:
            value.stringValue
        default:
            nil
        }
    }
}
