import Foundation

struct SearchAppUseCase: Sendable {
    let catalogService: AppCatalogServicing
    let logger: LoggingServicing

    func execute(appID: String, session: AppSession) async throws -> [AppVersion] {
        await logger.append(level: .info, category: "usecase.search", message: "Starting app lookup for \(appID).")

        do {
            let versions = try await catalogService.search(appID: appID, session: session)
            await logger.append(level: .notice, category: "usecase.search", message: "Loaded \(versions.count) versions for \(appID).")
            return versions
        } catch {
            await logger.append(level: .error, category: "usecase.search", message: "App lookup failed: \(error.localizedDescription)")
            throw error
        }
    }

    func loadVersion(appID: String, versionID: String, session: AppSession) async throws -> AppVersion {
        await logger.append(level: .info, category: "usecase.search", message: "Loading explicitly requested version \(versionID) for \(appID).")

        do {
            let version = try await catalogService.loadVersion(appID: appID, versionID: versionID, session: session)
            await logger.append(level: .notice, category: "usecase.search", message: "Refreshed version \(version.externalVersionID) for \(appID).")
            return version
        } catch {
            await logger.append(level: .error, category: "usecase.search", message: "Version refresh failed: \(error.localizedDescription)")
            throw error
        }
    }

    func loadDownloadableVersion(appID: String, session: AppSession) async throws -> AppVersion {
        await logger.append(level: .info, category: "usecase.search", message: "Resolving a downloadable version for \(appID).")

        do {
            let version = try await catalogService.loadDownloadableVersion(appID: appID, session: session)
            await logger.append(level: .notice, category: "usecase.search", message: "Resolved downloadable version \(version.externalVersionID) for \(appID).")
            return version
        } catch {
            await logger.append(level: .error, category: "usecase.search", message: "Downloadable version resolution failed: \(error.localizedDescription)")
            throw error
        }
    }
}
