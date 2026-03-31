import SwiftUI

struct TasksView: View {
    @Bindable var model: AppModel
    @State private var selectedStatus: DownloadTaskStatus?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            taskSummary

            if filteredTasks.isEmpty {
                ContentUnavailableView(
                    "No Matching Tasks",
                    systemImage: "clock.badge.exclamationmark",
                    description: Text("Create a download from the Search page, or change the current status filter.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                List {
                    ForEach(filteredTasks, id: \.id) { task in
                        TaskRowView(
                            task: task,
                            onCancel: {
                                Task {
                                    await model.cancelTask(id: task.id)
                                }
                            },
                            onPause: {
                                Task {
                                    await model.pauseTask(id: task.id)
                                }
                            },
                            onRetry: {
                                Task {
                                    await model.retryTask(id: task.id)
                                }
                            },
                            onDelete: {
                                Task {
                                    await model.deleteTask(id: task.id)
                                }
                            },
                            onRevealOutput: {
                                model.revealInFinder(path: task.outputPath)
                            },
                            onRevealCache: {
                                model.revealInFinder(path: task.cachePath)
                            },
                            onCopyOutputPath: {
                                model.copyToPasteboard(task.outputPath)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Tasks")
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Download Tasks")
                    .font(.title2.weight(.semibold))
                Text("Downloads now continue into verification and IPA rewriting. Use this workspace to monitor progress, retry signals, and output destinations.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu(selectedStatus?.displayTitle ?? "All Statuses") {
                Button("All Statuses") {
                    selectedStatus = nil
                }
                Divider()
                ForEach(DownloadTaskStatus.allCases, id: \.self) { status in
                    Button(status.displayTitle) {
                        selectedStatus = status
                    }
                }
            }
            Button("Refresh") {
                Task {
                    await model.refreshTaskHistory()
                }
            }
        }
    }

    private var filteredTasks: [DownloadTaskRecord] {
        guard let selectedStatus else { return model.taskHistory }
        return model.taskHistory.filter { $0.status == selectedStatus }
    }

    private var taskSummary: some View {
        HStack(spacing: 12) {
            summaryCard(title: "Active", value: "\(model.activeTaskCount)", color: .blue)
            summaryCard(title: "Completed", value: "\(model.completedTaskCount)", color: .green)
            summaryCard(title: "Failed", value: "\(model.failedTaskCount)", color: .red)
            summaryCard(title: "History", value: "\(model.taskHistory.count)", color: .secondary)
        }
    }

    private func summaryCard(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.weight(.semibold))
                .foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct TaskRowView: View {
    let task: DownloadTaskRecord
    let onCancel: () -> Void
    let onPause: () -> Void
    let onRetry: () -> Void
    let onDelete: () -> Void
    let onRevealOutput: () -> Void
    let onRevealCache: () -> Void
    let onCopyOutputPath: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading) {
                    Text(task.title)
                        .font(.headline)
                    Text("Version \(task.version)")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(task.status.displayTitle)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            ProgressView(value: task.progress)

            HStack {
                Text(formattedBytes(task.bytesDownloaded))
                Text("/")
                Text(totalBytesDescription)
                Spacer()
                Text("Retries \(task.retryCount)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(task.detailMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Text(task.createdAt, format: .dateTime.year().month().day().hour().minute())
                Spacer()
                Text(task.updatedAt, format: .dateTime.hour().minute().second())
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)

            HStack(spacing: 12) {
                if allowsPause {
                    Button("Pause", action: onPause)
                        .buttonStyle(.link)
                }
                if allowsCancellation {
                    Button("Cancel", action: onCancel)
                        .buttonStyle(.link)
                }
                if allowsRetry {
                    Button(task.status == .paused ? "Resume" : "Retry", action: onRetry)
                        .buttonStyle(.link)
                }
                Button("Delete", role: .destructive, action: onDelete)
                    .buttonStyle(.link)
                Button("Reveal Output", action: onRevealOutput)
                    .buttonStyle(.link)
                Button("Reveal Cache", action: onRevealCache)
                    .buttonStyle(.link)
                Button("Copy Output Path", action: onCopyOutputPath)
                    .buttonStyle(.link)
            }

            Text(task.outputPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
    }

    private var allowsCancellation: Bool {
        task.status == .downloading || task.status == .queued || task.status == .preparingDownload
    }

    private var allowsPause: Bool {
        task.status == .downloading || task.status == .queued || task.status == .preparingDownload
    }

    private var allowsRetry: Bool {
        task.status == .failed || task.status == .cancelled || task.status == .paused || task.status == .completed
    }

    private var statusColor: Color {
        switch task.status {
        case .queued, .resolvingLicense, .preparingDownload:
            .orange
        case .downloading, .verifying, .rewritingIPA:
            .blue
        case .paused:
            .yellow
        case .completed:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        }
    }

    private var totalBytesDescription: String {
        task.totalBytes == 0 ? "Unknown size" : formattedBytes(task.totalBytes)
    }

    private func formattedBytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
