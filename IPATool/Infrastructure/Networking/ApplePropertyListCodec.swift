import Foundation

enum ApplePropertyListCodecError: LocalizedError {
    case invalidRootObject

    var errorDescription: String? {
        switch self {
        case .invalidRootObject:
            "The Apple service payload was not a property list dictionary."
        }
    }
}

enum ApplePropertyListCodec {
    static func encode(_ dictionary: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: dictionary, format: .xml, options: 0)
    }

    static func decodeDictionary(from data: Data) throws -> [String: Any] {
        let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = object as? [String: Any] else {
            throw ApplePropertyListCodecError.invalidRootObject
        }
        return dictionary
    }
}
