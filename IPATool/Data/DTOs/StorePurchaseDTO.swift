import Foundation

struct StorePurchaseRequestDTO: Sendable, Equatable {
    var appID: String
    var versionID: String?
    var guid: String
}

struct StorePurchaseResponseDTO: Sendable, Equatable {
    var status: Int?
    var failureType: String?
    var customerMessage: String?

    init(status: Int?, failureType: String?, customerMessage: String?) {
        self.status = status
        self.failureType = failureType
        self.customerMessage = customerMessage
    }

    init(dictionary: [String: Any]) {
        self.status = dictionary["status"] as? Int ?? (dictionary["status"] as? NSNumber)?.intValue
        self.failureType = Self.stringValue(in: dictionary, keys: ["failureType"])
        self.customerMessage = Self.stringValue(in: dictionary, keys: ["customerMessage"])
    }

    var isSuccessfulLicenseResponse: Bool {
        status == 0 || failureType == "5002" || failureType == "2040"
    }

    private static func stringValue(in dictionary: [String: Any]?, keys: [String]) -> String? {
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
}
