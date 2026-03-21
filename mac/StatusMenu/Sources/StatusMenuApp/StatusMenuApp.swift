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
                    // Switch to regular app so macOS gives us full window focus + keyboard input
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        for window in NSApp.windows where window.title.contains("Settings") {
                            window.makeKeyAndOrderFront(nil)
                        }
                    }
                }
                .onDisappear {
                    // If no other windows are visible, hide the Dock icon again
                    let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && !$0.title.isEmpty && $0.title != "Settings" && $0.level != .statusBar }
                    if !hasVisibleWindows {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        }
        .defaultSize(width: 520, height: 620)
        .windowResizability(.contentSize)
    }
}
