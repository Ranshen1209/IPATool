import Foundation

struct CreateDownloadTaskUseCase: Sendable {
    let downloadService: DownloadServicing
    let logger: LoggingServicing

    func execute(version: AppVersion, session: AppSession, settings: AppSettingsSnapshot) async throws -> DownloadTaskRecord {
        await logger.append(level: .info, category: "usecase.download", message: "Creating download task for \(version.displayName) \(version.version).")

        guard version.downloadURL != nil else {
            let error = AppError(
                title: "Download URL Missing",
                message: "The selected Apple catalog version does not contain a downloadable asset URL yet.",
                recoverySuggestion: "Request the license again and confirm the refreshed version payload includes a live asset URL before retrying."
            )
            await logger.append(level: .error, category: "usecase.download", message: error.message)
            throw error
        }

        guard version.signaturePayload != nil else {
            let error = AppError(
                title: "Signature Payload Missing",
                message: "The selected Apple catalog version does not contain `sinf` signature data required for IPA rewriting.",
                recoverySuggestion: "Refresh the version after license confirmation and verify the Apple response includes a `sinfs` payload."
            )
            await logger.append(level: .error, category: "usecase.download", message: error.message)
            throw error
        }

        if version.bundleIdentifier.isEmpty {
            await logger.append(
                level: .notice,
                category: "usecase.download",
                message: "Proceeding without a catalog bundle identifier for \(version.displayName) \(version.version); the IPA rewrite step will rely on available metadata and extracted archive contents instead."
            )
        }

        do {
            let task = try await downloadService.enqueueDownload(for: version, session: session, settings: settings)
            await logger.append(level: .notice, category: "usecase.download", message: "Download task \(task.id.uuidString) created.")
            return task
        } catch {
            await logger.append(level: .error, category: "usecase.download", message: "Failed to create download task: \(error.localizedDescription)")
            throw error
        }
    }
}
