import SwiftUI

struct IPAToolCommands: Commands {
    @Bindable var model: AppModel

    var body: some Commands {
        CommandMenu("Workspace") {
            Button("Search") {
                model.selectedRoute = .search
            }
            .keyboardShortcut("1", modifiers: [.command])

            Button("Tasks") {
                model.selectedRoute = .tasks
            }
            .keyboardShortcut("2", modifiers: [.command])

            Button("Logs") {
                model.selectedRoute = .logs
            }
            .keyboardShortcut("3", modifiers: [.command])

            Divider()

            Button("Refresh Tasks") {
                Task {
                    await model.refreshTaskHistory()
                }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Refresh Logs") {
                Task {
                    await model.refreshLogs()
                }
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
    }
}
