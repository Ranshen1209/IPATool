import SwiftUI

struct SearchView: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                TextField(
                    "Enter App ID",
                    text: Binding(
                        get: { model.appIDQuery },
                        set: { model.sanitizeAppIDInput($0) }
                    )
                )
                    .textFieldStyle(.roundedBorder)
                TextField(
                    "Optional Version ID",
                    text: Binding(
                        get: { model.requestedVersionID },
                        set: { model.sanitizeVersionIDInput($0) }
                    )
                )
                    .textFieldStyle(.roundedBorder)
                Button("Load Versions") {
                    Task {
                        await model.search()
                    }
                }
                .keyboardShortcut(.defaultAction)
            }

            stateBanner

            if model.versionResults.isEmpty {
                ContentUnavailableView(
                    "No Versions Loaded",
                    systemImage: "square.stack.3d.down.right",
                    description: Text("Sign in with Apple ID, enter a numeric App ID, and optionally provide a Version ID to query a specific build through the authenticated store session.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            } else {
                Table(
                    model.versionResults,
                    selection: Binding(
                        get: { model.selectedVersionID },
                        set: { model.selectVersion(id: $0) }
                    )
                ) {
                    TableColumn("App") { version in
                        Text(version.displayName)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    TableColumn("Version") { version in
                        Text(version.version)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                    TableColumn("Version ID") { version in
                        Text(version.externalVersionID)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    }
                }

                if let selectedVersion = model.versionResults.first(where: { $0.id == model.selectedVersionID }) {
                    VStack(alignment: .leading, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Selected Version")
                                .font(.headline)
                            Text("\(selectedVersion.displayName) \(selectedVersion.version)")
                            Text(selectedVersion.bundleIdentifier)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        HStack(spacing: 12) {
                            Button("Request License") {
                                Task {
                                    await model.requestSelectedVersionLicense()
                                }
                            }
                            .disabled({
                                if model.purchaseState.state == .requesting {
                                    return true
                                }
                                return false
                            }())

                            Button("Create Download Task") {
                                Task {
                                    await model.createDownloadTaskForSelectedVersion()
                                }
                            }
                            .disabled(!(model.purchaseState.state == .licensed || model.purchaseState.state == .alreadyOwned))
                        }

                        licenseStatusBadge
                            .frame(maxWidth: .infinity, alignment: .trailing)

                        Text(model.purchaseState.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle("Search")
    }

    @ViewBuilder
    private var stateBanner: some View {
        switch model.searchState {
        case .idle:
            EmptyView()
        case .searching:
            HStack {
                ProgressView()
                Text("Looking up app metadata and versions...")
            }
        case .loaded(let appID, let versions):
            Text("Loaded \(versions.count) version entr\(versions.count == 1 ? "y" : "ies") for app id \(appID).")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .failed(let error):
            VStack(alignment: .leading, spacing: 4) {
                Text(error.title)
                    .font(.headline)
                    .foregroundStyle(.red)
                Text(error.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var licenseStatusBadge: some View {
        Text(model.purchaseState.state.displayTitle)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .foregroundStyle(licenseStatusColor)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                licenseStatusColor.opacity(0.12),
                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(licenseStatusColor.opacity(0.18), lineWidth: 1)
            }
    }

    private var licenseStatusColor: Color {
        switch model.purchaseState.state {
        case .notRequested:
            .secondary
        case .requesting:
            .orange
        case .licensed:
            .blue
        case .alreadyOwned:
            .green
        case .failed:
            .red
        }
    }
}
