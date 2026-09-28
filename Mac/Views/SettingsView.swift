import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            Section("Goals") {
                Stepper(value: $state.config.preferences.dailyGoalMinutes, in: 0...960, step: 15) {
                    Text("Daily screen time goal: \(state.config.preferences.dailyGoalMinutes == 0 ? "off" : Formatting.duration(Double(state.config.preferences.dailyGoalMinutes * 60)))")
                }
                TextField("Personal motto (shown on block screens)", text: $state.config.preferences.motto)
            }
            Section("Limits") {
                Stepper(value: $state.config.preferences.warnMinutesBefore, in: 0...30) {
                    Text("Warn \(state.config.preferences.warnMinutesBefore) min before a limit")
                }
                Stepper(value: $state.config.preferences.snoozeMinutes, in: 1...30) {
                    Text("\"More time\" button gives \(state.config.preferences.snoozeMinutes) min")
                }
            }
            Section("Tracking") {
                Stepper(value: $state.config.preferences.idleSeconds, in: 30...900, step: 30) {
                    Text("Stop counting after \(Formatting.duration(Double(state.config.preferences.idleSeconds))) without input")
                }
                Toggle("Keep counting while a video is playing", isOn: $state.config.preferences.countMediaWhileIdle)
                Toggle("Track websites in Safari, Chrome, Arc, Brave and Edge", isOn: $state.config.preferences.trackWebsites)
                Text("macOS asks once per browser for permission to let Screentime read the current tab.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("App") {
                Toggle("Open Screentime at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.setLaunchAtLogin($0) }))
                Button("Show data folder in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([state.store.directory])
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}
