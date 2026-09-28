import SwiftUI
import UserNotifications

@main
struct ScreentimePhoneApp: App {
    @StateObject private var state = PhoneState.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(state)
                .onAppear {
                    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
                }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.becameActive() }
        }
    }
}
