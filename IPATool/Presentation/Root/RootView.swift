import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 16) {
                VStack(alignment: .center, spacing: 6) {
                    Text("IPATool")
                        .font(.title2.weight(.semibold))
                    Text(sidebarSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)

                List(AppRoute.allCases, selection: $model.selectedRoute) { route in
                    Label(route.title, systemImage: route.systemImage)
                        .tag(route)
                }

                VStack(alignment: .center, spacing: 8) {
                    Label("\(model.activeTaskCount) active tasks", systemImage: "arrow.down.circle")
                    Label("\(model.completedTaskCount) completed", systemImage: "checkmark.circle")
                    if model.failedTaskCount > 0 {
                        Label("\(model.failedTaskCount) need attention", systemImage: "exclamationmark.triangle")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .navigationTitle("IPATool")
            .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 280)
        } detail: {
            contentView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task {
                        await model.refreshTaskHistory()
                        await model.refreshLogs()
                    }
                } label: {
                    Label("Refresh Workspace", systemImage: "arrow.clockwise")
                }

                Button {
                    model.selectedRoute = .tasks
                } label: {
                    Label("Tasks", systemImage: "square.stack.3d.down.right")
                }
            }
        }
        .task {
            await model.bootstrap()
        }
        .alert(
            model.latestError?.title ?? "",
            isPresented: Binding(
                get: { model.latestError != nil },
                set: { newValue in
                    if !newValue {
                        model.dismissError()
                    }
                }
            ),
            presenting: model.latestError
        ) { _ in
            Button("OK") {
                model.dismissError()
            }
        } message: { error in
            Text("\(error.message)\n\n\(error.recoverySuggestion)")
        }
        .sheet(
            item: Binding(
                get: { model.verificationPrompt },
                set: { newValue in
                    if newValue == nil {
                        model.cancelVerificationPrompt()
                    }
                }
            )
        ) { prompt in
            VerificationCodeSheet(model: model, prompt: prompt)
        }
    }

    @ViewBuilder
    private var contentView: some View {
        switch model.selectedRoute ?? .search {
        case .auth:
            AuthView(model: model)
        case .search:
            SearchView(model: model)
        case .tasks:
            TasksView(model: model)
        case .logs:
            LogsView(model: model)
        case .compliance:
            RiskCenterView(risks: model.operationalRisks)
        case .settings:
            SettingsView(model: model, settings: model.container.settings) {
                model.persistSettings()
            }
        }
    }

    private var sidebarSubtitle: String {
        switch model.sessionState {
        case .signedOut:
            "Sign in to request licenses and rewrite IPA metadata."
        case .signingIn:
            "Authenticating with the isolated account flow."
        case .signedIn(let session):
            "Signed in as \(session.displayName.isEmpty ? session.appleID : session.displayName)."
        case .failed:
            "Review the latest error before continuing."
        }
    }
}
