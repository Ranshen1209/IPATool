import CryptoKit
import Foundation

enum FileIntegrityError: LocalizedError {
    case unsupportedChecksum(String)
    case checksumMismatch(expected: String, actual: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedChecksum(let checksum):
            "The checksum value is not a valid MD5 digest: \(checksum)"
        case .checksumMismatch(let expected, let actual):
            "Checksum verification failed. Expected \(expected), received \(actual)."
        }
    }
}

struct FileIntegrityVerifier: Sendable {
    nonisolated func verifyMD5(of fileURL: URL, expectedHex: String) throws {
        let normalizedExpected = expectedHex.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedExpected.range(of: #"^[0-9a-f]{32}$"#, options: .regularExpression) != nil else {
            throw FileIntegrityError.unsupportedChecksum(expectedHex)
        }

        let actual = try calculateMD5(of: fileURL)
        guard actual == normalizedExpected else {
            throw FileIntegrityError.checksumMismatch(expected: normalizedExpected, actual: actual)
        }
    }

    nonisolated private func calculateMD5(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var hasher = Insecure.MD5()
        while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
