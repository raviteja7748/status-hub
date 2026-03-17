import SwiftUI

@main
struct StatusMenuApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Status", systemImage: model.iconName) {
            MenuContentView(model: model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(model: model)
        }
    }
}
