import AppKit
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @Bindable var settings: AppSettingsController
    var onPersist: () -> Void = {}
    @State private var concurrentChunksText = ""
    @State private var chunkSizeText = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                settingsSection("Storage") {
                    VStack(alignment: .leading, spacing: 18) {
                        pathEditor(
                            title: "Output Directory",
                            value: $settings.outputDirectoryPath,
                            panelTitle: "Choose Output Directory",
                            bookmarkKey: AppSettingsSnapshot.outputDirectoryBookmarkKey
                        )
                        Divider()
                        pathEditor(
                            title: "Cache Directory",
                            value: $settings.cacheDirectoryPath,
                            panelTitle: "Choose Cache Directory",
                            bookmarkKey: AppSettingsSnapshot.cacheDirectoryBookmarkKey
                        )
                        Button("Clear Cache Directory") {
                            model.clearCacheDirectory()
                        }
                    }
                }

                settingsSection("Downloader") {
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
                        numericSettingField(
                            title: "Concurrent Chunks",
                            text: $concurrentChunksText,
                            currentValue: settings.maximumConcurrentChunks,
                            range: 1...16,
                            suffix: nil
                        ) { value in
                            settings.maximumConcurrentChunks = value
                        }
                        Divider()
                            .gridCellColumns(3)
                        numericSettingField(
                            title: "Chunk Size",
                            text: $chunkSizeText,
                            currentValue: settings.chunkSizeInMegabytes,
                            range: 1...64,
                            suffix: "MB"
                        ) { value in
                            settings.chunkSizeInMegabytes = value
                        }
                    }
                }

            }
            .padding(20)
            .frame(maxWidth: 780, alignment: .leading)
        }
        .navigationTitle("Settings")
        .task {
            concurrentChunksText = String(settings.maximumConcurrentChunks)
            chunkSizeText = String(settings.chunkSizeInMegabytes)
        }
        .onChange(of: settings.outputDirectoryPath) { _, _ in onPersist() }
        .onChange(of: settings.cacheDirectoryPath) { _, _ in onPersist() }
        .onChange(of: settings.maximumConcurrentChunks) { _, value in
            concurrentChunksText = String(value)
            onPersist()
        }
        .onChange(of: settings.chunkSizeInMegabytes) { _, value in
            chunkSizeText = String(value)
            onPersist()
        }
    }

    @ViewBuilder
    private func settingsSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    @ViewBuilder
    private func pathEditor(title: String, value: Binding<String>, panelTitle: String, bookmarkKey: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            HStack {
                TextField("", text: value)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let selectedPath = chooseDirectory(title: panelTitle, startingAt: value.wrappedValue) {
                        value.wrappedValue = selectedPath
                        model.persistBookmark(for: URL(fileURLWithPath: selectedPath, isDirectory: true), key: bookmarkKey)
                        onPersist()
                    }
                }
                Button("Reveal") {
                    reveal(path: value.wrappedValue)
                }
            }
            Text((value.wrappedValue as NSString).expandingTildeInPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private func chooseDirectory(title: String, startingAt path: String) -> String? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)

        return panel.runModal() == .OK ? panel.url?.path : nil
    }

    private func reveal(path: String) {
        let expandedPath = (path as NSString).expandingTildeInPath
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: expandedPath)])
    }

    @ViewBuilder
    private func numericSettingField(
        title: String,
        text: Binding<String>,
        currentValue: Int,
        range: ClosedRange<Int>,
        suffix: String?,
        onCommitValue: @escaping (Int) -> Void
    ) -> some View {
        GridRow(alignment: .center) {
            Text(title)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField(
                "",
                text: Binding(
                    get: { text.wrappedValue },
                    set: { newValue in
                        text.wrappedValue = newValue.filter(\.isNumber)
                    }
                )
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 68)
            .multilineTextAlignment(.trailing)
            .onSubmit {
                commitNumericInput(text: text, currentValue: currentValue, range: range, onCommitValue: onCommitValue)
            }
            .onChange(of: text.wrappedValue) { _, newValue in
                if let parsed = Int(newValue) {
                    onCommitValue(min(max(parsed, range.lowerBound), range.upperBound))
                }
            }

            Text(suffix ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 28, alignment: .leading)
        }
        .frame(minHeight: 38, alignment: .center)
    }

    private func commitNumericInput(
        text: Binding<String>,
        currentValue: Int,
        range: ClosedRange<Int>,
        onCommitValue: (Int) -> Void
    ) {
        let fallback = min(max(currentValue, range.lowerBound), range.upperBound)
        let parsed = Int(text.wrappedValue).map { min(max($0, range.lowerBound), range.upperBound) } ?? fallback
        text.wrappedValue = String(parsed)
        onCommitValue(parsed)
    }
}
