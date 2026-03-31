//
//  IPAToolApp.swift
//  IPATool
//
//  Created by Ariel on 2026/3/31.
//

import SwiftUI

@main
struct IPAToolApp: App {
    @State private var container: AppContainer
    @State private var model: AppModel

    init() {
        let container = AppContainer()
        _container = State(initialValue: container)
        _model = State(initialValue: AppModel(container: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
                .frame(minWidth: 800, minHeight: 540)
        }
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            IPAToolCommands(model: model)
        }

        Settings {
            SettingsView(model: model, settings: container.settings) {
                model.persistSettings()
            }
                .frame(minWidth: 480, minHeight: 320)
        }
    }
}
