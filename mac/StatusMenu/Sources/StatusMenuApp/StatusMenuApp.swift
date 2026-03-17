import SwiftUI

@main
struct StatusMenuApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            MenuBarLabelView(model: model)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("Settings", id: "settings") {
            SettingsView(model: model)
                .onAppear {
                    bringSettingsToFront()
                }
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentSize)
    }

    private func bringSettingsToFront() {
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            for window in NSApp.windows where window.title.contains("Settings") {
                window.level = .floating
                window.orderFrontRegardless()
                window.makeKeyAndOrderFront(nil)
                // Reset to normal level after bringing to front so it behaves normally afterward
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    window.level = .normal
                }
            }
        }
    }
}
