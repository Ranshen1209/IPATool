import Foundation

enum DownloadManagerError: LocalizedError {
    case unableToDetermineRemoteSize
    case invalidSourceURL
    case missingResumeVersion(String)
    case missingAuthorizationContext
    case invalidChunkResponse(expectedStatus: Int, actualStatus: Int)
    case invalidContentRange(expected: String, actual: String?)
    case unexpectedChunkLength(expected: Int64, actual: Int64)

    var errorDescription: String? {
        switch self {
        case .unableToDetermineRemoteSize:
            "The downloader could not determine the remote file size."
        case .invalidSourceURL:
            "The selected app version does not contain a valid download URL."
        case .missingResumeVersion(let taskID):
            "The app could not recover the version details required to resume task \(taskID)."
        case .missingAuthorizationContext:
            "The current download requires a signed-in session with Apple authorization headers."
        case .invalidChunkResponse(let expectedStatus, let actualStatus):
            "The chunk download expected HTTP \(expectedStatus) but received HTTP \(actualStatus)."
        case .invalidContentRange(let expected, let actual):
            "The chunk response returned Content-Range \(actual ?? "<missing>") instead of \(expected)."
        case .unexpectedChunkLength(let expected, let actual):
            "The chunk response size was \(actual) bytes instead of the expected \(expected) bytes."
        }
    }
}

private struct ChunkDescriptor: Sendable {
    var index: Int
    var start: Int64
    var end: Int64

    nonisolated var expectedSize: Int64 {
        end - start + 1
    }
}

actor ChunkedDownloadManager {
    private struct PersistedTaskEnvelope: Codable {
        var record: DownloadTaskRecord
        var version: AppVersion?
    }

    private struct ManagedTask {
        var record: DownloadTaskRecord
        var version: AppVersion?
        var session: AppSession?
        var sourceURL: URL?
        var worker: Task<Void, Never>?
    }

    private let httpClient: HTTPClient
    private let logger: LoggingServicing
    private let credentialStore: CredentialStoring
    private let ipaProcessor: IPAProcessingServicing
    private let recoveryCatalog: DownloadRecoveryCatalog
    private let fileManager: FileManager
    private let persistenceURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var tasks: [UUID: ManagedTask] = [:]

    init(
        persistenceURL: URL,
        httpClient: HTTPClient,
        logger: LoggingServicing,
        credentialStore: CredentialStoring,
        ipaProcessor: IPAProcessingServicing,
        recoveryCatalog: DownloadRecoveryCatalog = DownloadRecoveryCatalog(),
        fileManager: FileManager = .default
    ) {
        self.persistenceURL = persistenceURL
        self.httpClient = httpClient
        self.logger = logger
        self.credentialStore = credentialStore
        self.ipaProcessor = ipaProcessor
        self.recoveryCatalog = recoveryCatalog
        self.fileManager = fileManager
    }

    func loadPersistedTasks() async {
        guard
            let data = try? Data(contentsOf: persistenceURL),
            let payload = try? decoder.decode([PersistedTaskEnvelope].self, from: data)
        else {
            return
        }

        for envelope in payload {
            let task = envelope.record
            let version = envelope.version ?? recoveryCatalog.version(for: task.id)
            if let version {
                recoveryCatalog.store(version: version, for: task.id)
            }
            tasks[task.id] = ManagedTask(record: task, version: version, session: nil, sourceURL: version?.downloadURL, worker: nil)
        }
    }

    func attachSessionIfNeeded(_ session: AppSession?) {
        for id in tasks.keys {
            guard var managed = tasks[id] else { continue }
            guard managed.sourceURL?.isFileURL == false else { continue }
            managed.session = session
            tasks[id] = managed
        }
    }

    func resumePendingTasks(settings: AppSettingsSnapshot) async {
        let resumableTaskIDs = tasks.compactMap { id, managed in
            managed.record.status.resumesAfterLaunch ? id : nil
        }

        for taskID in resumableTaskIDs {
            do {
                try await resumeTask(id: taskID, settings: settings)
            } catch {
                try? await updateTask(id: taskID) {
                    $0.status = .failed
                    $0.detailMessage = "Resume failed: \(error.localizedDescription)"
                }
                await logger.append(level: .error, category: "download.resume", message: "Failed to resume task \(taskID.uuidString): \(error.localizedDescription)")
            }
        }
    }

    func snapshot() -> [DownloadTaskRecord] {
        tasks.values
            .map(\.record)
            .sorted { $0.createdAt > $1.createdAt }
    }

    func cancel(id: UUID) async {
        guard var managed = tasks[id] else { return }
        managed.worker?.cancel()
        managed.record.status = .cancelled
        managed.record.detailMessage = "Cancelled by the user."
        managed.record.updatedAt = .now
        tasks[id] = managed
        await persist()
        await logger.append(level: .notice, category: "download", message: "Cancelled task \(id.uuidString).")
    }

    func pause(id: UUID) async {
        guard var managed = tasks[id] else { return }
        managed.worker?.cancel()
        managed.worker = nil
        managed.record.status = .paused
        managed.record.detailMessage = "Paused by the user. Resume with Retry to continue from cached chunks."
        managed.record.updatedAt = .now
        tasks[id] = managed
        await persist()
        await logger.append(level: .notice, category: "download", message: "Paused task \(id.uuidString).")
    }

    func pauseAuthenticatedDownloads() async -> Int {
        let candidateIDs = tasks.compactMap { id, managed -> UUID? in
            guard managed.record.status.isTerminal == false else { return nil }
            guard managed.sourceURL?.isFileURL == false else { return nil }
            return id
        }

        for id in candidateIDs {
            await pause(id: id)
        }

        if candidateIDs.isEmpty == false {
            await logger.append(
                level: .notice,
                category: "download",
                message: "Paused \(candidateIDs.count) authenticated download task(s) after Apple sign-out."
            )
        }

        return candidateIDs.count
    }

    func retry(id: UUID, session: AppSession, settings: AppSettingsSnapshot) async throws {
        guard var managed = tasks[id] else { return }
        guard let version = managed.version ?? recoveryCatalog.version(for: id) else {
            throw DownloadManagerError.missingResumeVersion(id.uuidString)
        }

        managed.worker?.cancel()
        managed.session = session
        managed.version = version
        managed.sourceURL = version.downloadURL
        managed.record.status = .queued
        managed.record.progress = 0
        managed.record.bytesDownloaded = 0
        managed.record.totalBytes = 0
        managed.record.retryCount = 0
        managed.record.detailMessage = "Retrying download."
        managed.record.updatedAt = .now

        let cacheDirectory = URL(fileURLWithPath: managed.record.cachePath, isDirectory: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        if let chunkFiles = try? fileManager.contentsOfDirectory(at: cacheDirectory, includingPropertiesForKeys: nil) {
            for fileURL in chunkFiles where fileURL.lastPathComponent.hasPrefix("part_") || fileURL.pathExtension == "ipa" {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        let outputURL = URL(fileURLWithPath: managed.record.outputPath)
        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }

        let worker = Task {
            await self.runDownload(
                id: id,
                version: version,
                session: session,
                outputURL: outputURL,
                cacheDirectory: cacheDirectory,
                settings: settings
            )
        }

        managed.worker = worker
        tasks[id] = managed
        await persist()
        await logger.append(level: .notice, category: "download", message: "Retrying task \(id.uuidString).")
    }

    func delete(id: UUID) async {
        guard let managed = tasks.removeValue(forKey: id) else { return }
        managed.worker?.cancel()
        recoveryCatalog.removeVersion(for: id)

        let outputURL = URL(fileURLWithPath: managed.record.outputPath)
        let cacheURL = URL(fileURLWithPath: managed.record.cachePath, isDirectory: true)
        if fileManager.fileExists(atPath: outputURL.path) {
            try? fileManager.removeItem(at: outputURL)
        }
        if fileManager.fileExists(atPath: cacheURL.path) {
            try? fileManager.removeItem(at: cacheURL)
        }

        await persist()
        await logger.append(level: .notice, category: "download", message: "Deleted task \(id.uuidString) and cleaned its output/cache files.")
    }

    func enqueue(version: AppVersion, session: AppSession, settings: AppSettingsSnapshot) async throws -> DownloadTaskRecord {
        let downloadsDirectory = expandedDirectory(from: settings.outputDirectoryPath)
        let cacheRootDirectory = expandedDirectory(from: settings.cacheDirectoryPath)
        try fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: cacheRootDirectory, withIntermediateDirectories: true)

        let identifier = UUID()
        let outputURL = downloadsDirectory.appendingPathComponent("\(version.displayName)_\(version.version).ipa")
        let cacheDirectory = cacheRootDirectory.appendingPathComponent(identifier.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let record = DownloadTaskRecord(
            id: identifier,
            title: version.displayName,
            version: version.version,
            status: .queued,
            progress: 0,
            bytesDownloaded: 0,
            totalBytes: 0,
            retryCount: 0,
            outputPath: outputURL.path,
            cachePath: cacheDirectory.path,
            detailMessage: "Task created and waiting to start.",
            createdAt: .now,
            updatedAt: .now
        )

        let worker = Task {
            await self.runDownload(
                id: identifier,
                version: version,
                session: session,
                outputURL: outputURL,
                cacheDirectory: cacheDirectory,
                settings: settings
            )
        }

        recoveryCatalog.store(version: version, for: identifier)
        tasks[identifier] = ManagedTask(record: record, version: version, session: session, sourceURL: version.downloadURL, worker: worker)
        await persist()
        await logger.append(level: .info, category: "download", message: "Enqueued task \(identifier.uuidString) for \(version.displayName) \(version.version).")
        return record
    }

    private func resumeTask(id: UUID, settings: AppSettingsSnapshot) async throws {
        guard var managed = tasks[id] else { return }
        guard managed.worker == nil else { return }
        guard let version = managed.version ?? recoveryCatalog.version(for: id) else {
            throw DownloadManagerError.missingResumeVersion(id.uuidString)
        }
        guard version.downloadURL?.isFileURL == true || managed.session != nil else {
            throw DownloadManagerError.missingAuthorizationContext
        }

        let outputURL = URL(fileURLWithPath: managed.record.outputPath)
        let cacheDirectory = URL(fileURLWithPath: managed.record.cachePath, isDirectory: true)
        try fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        try await updateTask(id: id) {
            $0.status = .queued
            $0.detailMessage = "Resuming unfinished task after app relaunch."
        }

        let worker = Task {
            await self.runDownload(
                id: id,
                version: version,
                session: managed.session,
                outputURL: outputURL,
                cacheDirectory: cacheDirectory,
                settings: settings
            )
        }

        managed.version = version
        managed.sourceURL = version.downloadURL
        managed.worker = worker
        tasks[id] = managed
        await persist()
        await logger.append(level: .notice, category: "download.resume", message: "Resumed pending task \(id.uuidString).")
    }

    private func runDownload(
        id: UUID,
        version: AppVersion,
        session: AppSession?,
        outputURL: URL,
        cacheDirectory: URL,
        settings: AppSettingsSnapshot
    ) async {
        do {
            try Task.checkCancellation()
            try await updateTask(id: id) {
                $0.status = .preparingDownload
                $0.detailMessage = "Preparing chunk plan."
            }

            guard let sourceURL = version.downloadURL else {
                throw DownloadManagerError.invalidSourceURL
            }

            await logger.append(
                level: .info,
                category: "download",
                message: "Starting download for task \(id.uuidString). remote=\(!sourceURL.isFileURL) authenticated=\(session != nil)"
            )

            let totalSize = try await resolveTotalSize(for: sourceURL, session: session)
            let chunkSize = Int64(settings.chunkSizeInMegabytes) * 1024 * 1024
            let descriptors = makeChunkDescriptors(totalSize: totalSize, chunkSize: max(chunkSize, 1024 * 1024))
            await logger.append(
                level: .info,
                category: "download",
                message: "Resolved remote size \(totalSize) bytes for task \(id.uuidString); chunkSize=\(max(chunkSize, 1024 * 1024)) bytes, chunks=\(descriptors.count)."
            )

            try await updateTask(id: id) {
                $0.totalBytes = totalSize
                $0.detailMessage = "Downloading \(descriptors.count) chunks."
            }

            try await downloadChunks(
                id: id,
                sourceURL: sourceURL,
                session: session,
                descriptors: descriptors,
                cacheDirectory: cacheDirectory,
                concurrency: max(1, settings.maximumConcurrentChunks)
            )

            try Task.checkCancellation()
            try await updateTask(id: id) {
                $0.status = .verifying
                $0.detailMessage = "Merging finished chunks."
            }

            let stagedOutputURL = cacheDirectory.appendingPathComponent(outputURL.lastPathComponent)
            try mergeChunks(descriptors: descriptors, cacheDirectory: cacheDirectory, outputURL: stagedOutputURL)
            let stagedSize = (try? fileManager.attributesOfItem(atPath: stagedOutputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            await logger.append(level: .info, category: "download", message: "Merged \(descriptors.count) chunks into staged IPA at \(stagedOutputURL.path) (\(stagedSize) bytes).")
            try stageMergedIPA(from: stagedOutputURL, to: outputURL)
            let finalSize = (try? fileManager.attributesOfItem(atPath: outputURL.path)[.size] as? NSNumber)?.int64Value ?? 0
            await logger.append(level: .info, category: "download", message: "Promoted staged IPA to final output path \(outputURL.path) (\(finalSize) bytes).")

            if !sourceURL.isFileURL {
                try await updateTask(id: id) {
                    $0.detailMessage = "Validating downloaded IPA."
                }
            }

            guard let credential = try await credentialStore.loadCredential() else {
                throw IPAProcessingError.missingAppleID
            }

            try await updateTask(id: id) {
                $0.status = .rewritingIPA
                $0.detailMessage = "Rewriting IPA metadata and signature payload."
            }
            try await ipaProcessor.processDownloadedIPA(at: outputURL, version: version, appleID: credential.appleID)

            try await updateTask(id: id) {
                $0.status = .completed
                $0.progress = 1
                $0.bytesDownloaded = $0.totalBytes
                $0.detailMessage = "Download completed successfully."
            }

            try? fileManager.removeItem(at: cacheDirectory)
            clearWorker(id: id)
            recoveryCatalog.removeVersion(for: id)

            await logger.append(level: .notice, category: "download", message: "Completed task \(id.uuidString).")
        } catch is CancellationError {
            clearWorker(id: id)
            if tasks[id]?.record.status == .paused {
                await persist()
                await logger.append(level: .notice, category: "download", message: "Stopped task \(id.uuidString) in paused state.")
            } else {
                await cancel(id: id)
            }
        } catch {
            try? await updateTask(id: id) {
                $0.status = .failed
                $0.detailMessage = "Download failed. \(error.localizedDescription) Inspect the cache path and logs before retrying."
            }
            clearWorker(id: id)
            await logger.append(level: .error, category: "download", message: "Task \(id.uuidString) failed: \(error.localizedDescription)")
        }
    }

    private func resolveTotalSize(for url: URL, session: AppSession?) async throws -> Int64 {
        if url.isFileURL {
            let values = try url.resourceValues(forKeys: [.fileSizeKey])
            if let fileSize = values.fileSize {
                return Int64(fileSize)
            }
            throw DownloadManagerError.unableToDetermineRemoteSize
        }

        guard let session else {
            throw DownloadManagerError.missingAuthorizationContext
        }

        let baseHeaders = session.authHeaders
        await logger.append(level: .debug, category: "download", message: "Attempting to resolve remote size via HEAD for \(url.absoluteString).")
        let headRequest = HTTPRequest(url: url, method: .head, headers: baseHeaders, timeoutInterval: 8)

        if let response = try? await httpClient.send(headRequest),
           let contentLength = response.headers["Content-Length"] ?? response.headers["content-length"],
           let size = Int64(contentLength) {
            await logger.append(level: .debug, category: "download", message: "Resolved remote size via HEAD for \(url.absoluteString).")
            return size
        }

        await logger.append(level: .debug, category: "download", message: "HEAD did not return a usable size for \(url.absoluteString). Falling back to ranged GET.")
        let fallbackRequest = HTTPRequest(
            url: url,
            method: .get,
            headers: baseHeaders.merging(["Range": "bytes=0-0"]) { _, new in new },
            timeoutInterval: 20
        )
        let response = try await httpClient.send(fallbackRequest)
        if let contentRange = response.headers["Content-Range"] ?? response.headers["content-range"],
           let totalPart = contentRange.split(separator: "/").last,
           let total = Int64(totalPart) {
            await logger.append(level: .debug, category: "download", message: "Resolved remote size via ranged GET fallback for \(url.absoluteString).")
            return total
        }

        throw DownloadManagerError.unableToDetermineRemoteSize
    }

    private func makeChunkDescriptors(totalSize: Int64, chunkSize: Int64) -> [ChunkDescriptor] {
        var descriptors: [ChunkDescriptor] = []
        var start: Int64 = 0
        var index = 0

        while start < totalSize {
            descriptors.append(
                ChunkDescriptor(
                    index: index,
                    start: start,
                    end: min(start + chunkSize - 1, totalSize - 1)
                )
            )
            start += chunkSize
            index += 1
        }

        return descriptors
    }

    private func downloadChunks(
        id: UUID,
        sourceURL: URL,
        session: AppSession?,
        descriptors: [ChunkDescriptor],
        cacheDirectory: URL,
        concurrency: Int
    ) async throws {
        try await updateTask(id: id) {
            $0.status = .downloading
        }

        var iterator = descriptors.makeIterator()
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<min(concurrency, descriptors.count) {
                guard let descriptor = iterator.next() else { break }
                group.addTask { try await self.processChunk(id: id, sourceURL: sourceURL, session: session, descriptor: descriptor, cacheDirectory: cacheDirectory) }
            }

            while try await group.next() != nil {
                if let descriptor = iterator.next() {
                    group.addTask { try await self.processChunk(id: id, sourceURL: sourceURL, session: session, descriptor: descriptor, cacheDirectory: cacheDirectory) }
                }
            }
        }
    }

    private func processChunk(
        id: UUID,
        sourceURL: URL,
        session: AppSession?,
        descriptor: ChunkDescriptor,
        cacheDirectory: URL
    ) async throws {
        let partURL = cacheDirectory.appendingPathComponent("part_\(descriptor.index)")
        if let attributes = try? fileManager.attributesOfItem(atPath: partURL.path),
           let fileSize = attributes[.size] as? NSNumber,
           fileSize.int64Value == descriptor.expectedSize {
            try await incrementProgress(id: id, bytes: descriptor.expectedSize, detail: "Reused chunk \(descriptor.index + 1).")
            return
        }

        var lastError: Error?
        for attempt in 1...3 {
            do {
                try Task.checkCancellation()
                if descriptor.index < 3 {
                    await logger.append(
                        level: .debug,
                        category: "download.chunk",
                        message: "Fetching chunk \(descriptor.index + 1) range \(descriptor.start)-\(descriptor.end) for task \(id.uuidString), attempt \(attempt)."
                    )
                }
                let data = try await fetchChunk(from: sourceURL, session: session, descriptor: descriptor)
                try data.write(to: partURL, options: .atomic)
                if descriptor.index < 3 {
                    await logger.append(
                        level: .debug,
                        category: "download.chunk",
                        message: "Stored chunk \(descriptor.index + 1) for task \(id.uuidString) at \(partURL.lastPathComponent) (\(data.count) bytes)."
                    )
                }
                try await incrementProgress(id: id, bytes: Int64(data.count), detail: "Finished chunk \(descriptor.index + 1).")
                return
            } catch {
                lastError = error
                await logger.append(
                    level: .notice,
                    category: "download.chunk",
                    message: "Chunk \(descriptor.index + 1) for task \(id.uuidString) failed on attempt \(attempt): \(error.localizedDescription)"
                )
                try await updateTask(id: id) {
                    $0.retryCount += 1
                    $0.detailMessage = "Retrying chunk \(descriptor.index + 1), attempt \(attempt)."
                }
                try await Task.sleep(for: .milliseconds(250 * attempt))
            }
        }

        throw lastError ?? DownloadManagerError.invalidSourceURL
    }

    private func fetchChunk(from sourceURL: URL, session: AppSession?, descriptor: ChunkDescriptor) async throws -> Data {
        if sourceURL.isFileURL {
            let handle = try FileHandle(forReadingFrom: sourceURL)
            defer { try? handle.close() }
            try handle.seek(toOffset: UInt64(descriptor.start))
            return try handle.read(upToCount: Int(descriptor.expectedSize)) ?? Data()
        }

        guard let session else {
            throw DownloadManagerError.missingAuthorizationContext
        }

        let request = HTTPRequest(
            url: sourceURL,
            method: .get,
            headers: session.authHeaders.merging(["Range": "bytes=\(descriptor.start)-\(descriptor.end)"]) { _, new in new },
            timeoutInterval: 60
        )
        let response = try await httpClient.send(request)
        let expectedContentRange = "bytes \(descriptor.start)-\(descriptor.end)"
        guard response.statusCode == 206 else {
            throw DownloadManagerError.invalidChunkResponse(expectedStatus: 206, actualStatus: response.statusCode)
        }
        let contentRange = response.headers["Content-Range"] ?? response.headers["content-range"]
        guard let contentRange, contentRange.hasPrefix(expectedContentRange + "/") else {
            throw DownloadManagerError.invalidContentRange(expected: expectedContentRange + "/*", actual: contentRange)
        }
        guard Int64(response.body.count) == descriptor.expectedSize else {
            throw DownloadManagerError.unexpectedChunkLength(
                expected: descriptor.expectedSize,
                actual: Int64(response.body.count)
            )
        }
        return response.body
    }

    private func mergeChunks(descriptors: [ChunkDescriptor], cacheDirectory: URL, outputURL: URL) throws {
        try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: outputURL.path) {
            try fileManager.removeItem(at: outputURL)
        }
        guard fileManager.createFile(atPath: outputURL.path, contents: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        let outputHandle = try FileHandle(forWritingTo: outputURL)
        defer { try? outputHandle.close() }

        for descriptor in descriptors {
            let partURL = cacheDirectory.appendingPathComponent("part_\(descriptor.index)")
            let inputHandle = try FileHandle(forReadingFrom: partURL)
            defer { try? inputHandle.close() }

            while let chunk = try inputHandle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try outputHandle.seekToEnd()
                try outputHandle.write(contentsOf: chunk)
            }
        }
    }

    private func stageMergedIPA(from stagedURL: URL, to finalURL: URL) throws {
        try fileManager.createDirectory(at: finalURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: finalURL.path) {
            try fileManager.removeItem(at: finalURL)
        }

        do {
            try fileManager.moveItem(at: stagedURL, to: finalURL)
        } catch {
            if fileManager.fileExists(atPath: finalURL.path) {
                try? fileManager.removeItem(at: finalURL)
            }
            do {
                try fileManager.copyItem(at: stagedURL, to: finalURL)
                try? fileManager.removeItem(at: stagedURL)
            } catch {
                throw error
            }
        }
    }

    private func incrementProgress(id: UUID, bytes: Int64, detail: String) async throws {
        try await updateTask(id: id) {
            $0.bytesDownloaded += bytes
            if $0.totalBytes > 0 {
                $0.progress = min(Double($0.bytesDownloaded) / Double($0.totalBytes), 1)
            }
            $0.detailMessage = detail
        }
    }

    private func updateTask(id: UUID, mutate: (inout DownloadTaskRecord) -> Void) async throws {
        guard var managed = tasks[id] else { return }
        mutate(&managed.record)
        managed.record.updatedAt = .now
        tasks[id] = managed
        await persist()
    }

    private func persist() async {
        let payload = tasks.values
            .map { PersistedTaskEnvelope(record: $0.record, version: $0.version) }
            .sorted { $0.record.createdAt > $1.record.createdAt }
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }
        try? fileManager.createDirectory(at: persistenceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: persistenceURL, options: .atomic)
    }

    private func clearWorker(id: UUID) {
        guard var managed = tasks[id] else { return }
        managed.worker = nil
        tasks[id] = managed
    }

    private func expandedDirectory(from rawPath: String) -> URL {
        let path = (rawPath as NSString).expandingTildeInPath
        return URL(fileURLWithPath: path, isDirectory: true)
    }
}
