import Foundation
import Darwin

enum AppleDeviceGUIDError: LocalizedError {
    case addressEnumerationFailed
    case hardwareAddressUnavailable

    var errorDescription: String? {
        switch self {
        case .addressEnumerationFailed:
            "The app could not enumerate local interfaces to derive an Apple login GUID."
        case .hardwareAddressUnavailable:
            "The app could not derive a hardware-address GUID for the Apple login flow."
        }
    }
}

enum AppleDeviceGUIDProvider {
    static func currentGUID() throws -> String {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else {
            throw AppleDeviceGUIDError.addressEnumerationFailed
        }
        defer { freeifaddrs(interfaces) }

        let preferredInterfaces = ["en0", "en1"]
        var fallback: String?
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }

            guard let namePointer = current.pointee.ifa_name else { continue }
            let name = String(cString: namePointer)

            guard let rawAddress = current.pointee.ifa_addr else { continue }
            guard rawAddress.pointee.sa_family == UInt8(AF_LINK) else { continue }

            let socketAddress = UnsafeRawPointer(rawAddress).assumingMemoryBound(to: sockaddr_dl.self)
            let hardwareLength = Int(socketAddress.pointee.sdl_alen)
            guard hardwareLength > 0 else { continue }

            let nameLength = Int(socketAddress.pointee.sdl_nlen)
            let dataPointer = UnsafeRawPointer(socketAddress).advanced(by: MemoryLayout<sockaddr_dl>.size)
            let hardwarePointer = dataPointer.advanced(by: nameLength).assumingMemoryBound(to: UInt8.self)
            let bytes = (0..<hardwareLength).map { hardwarePointer[$0] }
            let guid = bytes.map { String(format: "%02X", $0) }.joined()

            if preferredInterfaces.contains(name) {
                return guid
            }

            if fallback == nil {
                fallback = guid
            }
        }

        if let fallback {
            return fallback
        }

        throw AppleDeviceGUIDError.hardwareAddressUnavailable
    }
}
