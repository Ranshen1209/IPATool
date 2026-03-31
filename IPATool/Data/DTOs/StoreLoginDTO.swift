import Foundation

struct StoreLoginRequestDTO: Sendable, Equatable {
    var appleID: String
    var password: String
    var verificationCode: String?
    var guid: String
}

struct StoreLoginResponseDTO: Sendable, Equatable {
    struct AccountInfoDTO: Sendable, Equatable {
        struct AddressDTO: Sendable, Equatable {
            var firstName: String
            var lastName: String
        }

        var appleID: String
        var address: AddressDTO
    }

    var status: Int?
    var dsPersonID: String
    var passwordToken: String
    var storeFront: String?
    var accountInfo: AccountInfoDTO
    var failureType: String?
    var customerMessage: String?

    init(
        status: Int?,
        dsPersonID: String,
        passwordToken: String,
        storeFront: String?,
        accountInfo: AccountInfoDTO,
        failureType: String?,
        customerMessage: String?
    ) {
        self.status = status
        self.dsPersonID = dsPersonID
        self.passwordToken = passwordToken
        self.storeFront = storeFront
        self.accountInfo = accountInfo
        self.failureType = failureType
        self.customerMessage = customerMessage
    }

    nonisolated var authHeaders: [String: String] {
        var headers: [String: String] = [
            "X-Dsid": dsPersonID,
            "iCloud-DSID": dsPersonID,
            "X-Token": passwordToken,
        ]
        if let storeFront {
            headers["X-Apple-Store-Front"] = storeFront
        }
        return headers
    }

    init(dictionary: [String: Any], headers: [String: String]) {
        let status = dictionary["status"] as? Int ?? (dictionary["status"] as? NSNumber)?.intValue
        let dsPersonID = Self.stringValue(in: dictionary, keys: ["dsPersonId", "dsPersonID"]) ?? ""
        let passwordToken = Self.stringValue(in: dictionary, keys: ["passwordToken"]) ?? ""
        let failureType = Self.stringValue(in: dictionary, keys: ["failureType"])
        let customerMessage = Self.stringValue(in: dictionary, keys: ["customerMessage"])

        let accountInfoDictionary = dictionary["accountInfo"] as? [String: Any]
        let addressDictionary = accountInfoDictionary?["address"] as? [String: Any]
        let appleID = Self.stringValue(in: accountInfoDictionary, keys: ["appleId", "appleID"]) ?? ""
        let firstName = Self.stringValue(in: addressDictionary, keys: ["firstName"]) ?? ""
        let lastName = Self.stringValue(in: addressDictionary, keys: ["lastName"]) ?? ""
        let rawStoreFront = headers["x-set-apple-store-front"] ?? headers["X-Set-Apple-Store-Front"]
        let storeFront = rawStoreFront?.split(separator: "-").first.map(String.init)

        self.init(
            status: status,
            dsPersonID: dsPersonID,
            passwordToken: passwordToken,
            storeFront: storeFront,
            accountInfo: AccountInfoDTO(
                appleID: appleID,
                address: AccountInfoDTO.AddressDTO(firstName: firstName, lastName: lastName)
            ),
            failureType: failureType,
            customerMessage: customerMessage
        )
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
