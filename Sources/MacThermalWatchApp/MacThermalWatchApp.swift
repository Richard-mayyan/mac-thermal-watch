import SwiftUI

@main
struct MacThermalWatchDesktopApp: App {
    @StateObject private var monitor = MonitorViewModel()

    var body: some Scene {
        WindowGroup {
            DashboardView()
                .environmentObject(monitor)
                .frame(minWidth: 900, minHeight: 680)
                .onAppear { monitor.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(monitor.isRunning ? "Mettre en pause" : "Démarrer la surveillance") {
                    monitor.toggleMonitoring()
                }
                .keyboardShortcut("m", modifiers: [.command])

                Button("Mesurer maintenant") {
                    monitor.refresh()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
