import Foundation

enum IPAArchiveRewriteError: LocalizedError {
    case invalidSignaturePayload
    case missingSignatureTemplate
    case missingPayloadDirectory
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidSignaturePayload:
            "The IPA rewrite step received invalid signature data."
        case .missingSignatureTemplate:
            "The extracted IPA does not contain a main app SC_Info/*.supp template file."
        case .missingPayloadDirectory:
            "The extracted IPA does not contain a Payload directory."
        case .commandFailed(let message):
            message
        }
    }
}

struct IPAArchiveRewriter: Sendable {
    nonisolated(unsafe) let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    nonisolated func rewriteIPA(
        at ipaURL: URL,
        metadata: [String: Any],
        signaturePayload: String
    ) throws {
        let fileManager = self.fileManager

        guard let signatureData = Data(base64Encoded: signaturePayload) else {
            throw IPAArchiveRewriteError.invalidSignaturePayload
        }

        let workspaceURL = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let extractionURL = workspaceURL.appendingPathComponent("Extracted", isDirectory: true)
        let rewrittenURL = workspaceURL.appendingPathComponent("Rewritten.ipa")

        try fileManager.createDirectory(at: extractionURL, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: workspaceURL) }

        try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", ipaURL.path, extractionURL.path]
        )

        let payloadURL = extractionURL.appendingPathComponent("Payload", isDirectory: true)
        guard fileManager.fileExists(atPath: payloadURL.path) else {
            throw IPAArchiveRewriteError.missingPayloadDirectory
        }

        let suppURL = try locateSignatureTemplate(in: payloadURL)
        let sinfURL = suppURL.deletingPathExtension().appendingPathExtension("sinf")
        let metadataURL = extractionURL.appendingPathComponent("iTunesMetadata.plist")

        let plistData = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try plistData.write(to: metadataURL, options: .atomic)
        try signatureData.write(to: sinfURL, options: .atomic)

        if fileManager.fileExists(atPath: rewrittenURL.path) {
            try fileManager.removeItem(at: rewrittenURL)
        }

        try runCommand(
            executableURL: URL(fileURLWithPath: "/usr/bin/zip"),
            arguments: ["-qry", rewrittenURL.path, "Payload", "iTunesMetadata.plist"],
            currentDirectoryURL: extractionURL
        )

        if fileManager.fileExists(atPath: ipaURL.path) {
            try fileManager.removeItem(at: ipaURL)
        }
        try fileManager.moveItem(at: rewrittenURL, to: ipaURL)
    }

    nonisolated private func locateSignatureTemplate(in payloadURL: URL) throws -> URL {
        let fileManager = self.fileManager

        guard
            let enumerator = fileManager.enumerator(
                at: payloadURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
        else {
            throw IPAArchiveRewriteError.missingSignatureTemplate
        }

        let suppCandidates = enumerator.compactMap { item -> URL? in
            guard let url = item as? URL else { return nil }
            guard url.pathExtension.lowercased() == "supp" else { return nil }
            let parentDirectory = url.deletingLastPathComponent().lastPathComponent.lowercased()
            return parentDirectory == "sc_info" ? url : nil
        }

        guard let selected = suppCandidates.min(by: { $0.path.count < $1.path.count }) else {
            throw IPAArchiveRewriteError.missingSignatureTemplate
        }

        return selected
    }

    nonisolated private func runCommand(
        executableURL: URL,
        arguments: [String],
        currentDirectoryURL: URL? = nil
    ) throws {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectoryURL

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw IPAArchiveRewriteError.commandFailed(output.isEmpty ? "Archive rewrite command failed." : output)
        }
    }
}
