import SwiftUI

@main
struct ScreentimeMacApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView().environmentObject(state)
        } label: {
            MenuBarLabel(state: state)
        }
        .menuBarExtraStyle(.window)

        Window("Screentime", id: "dashboard") {
            DashboardView()
                .environmentObject(state)
                .frame(minWidth: 860, minHeight: 580)
        }
        .defaultSize(width: 980, height: 680)
    }
}

private struct MenuBarLabel: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            if let session = state.lockIn {
                Image(systemName: "lock.fill")
                Text(Formatting.duration(session.remaining(at: Date())))
            } else {
                Image(systemName: state.isPaused ? "pause.circle" : "hourglass")
                Text(Formatting.duration(state.config.distractionSeconds(state.today)))
            }
        }
    }
}
