import SwiftUI

struct SetupView: View {
    @EnvironmentObject var state: PhoneState
    @State private var newApp = ""

    private static let suggestions = ["Instagram", "TikTok", "YouTube", "Snapchat", "X", "Reddit", "Netflix", "Roblox"]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("iPhone doesn't let other apps read Screen Time, so Screentime learns what you open from **Shortcuts automations**. Set up two things once, then it runs by itself.")
                        .font(.callout)
                }

                Section("1 · Apps to track") {
                    ForEach(state.config.trackedApps, id: \.self) { app in
                        Text(app)
                    }
                    .onDelete { offsets in
                        offsets.map { state.config.trackedApps[$0] }.forEach(state.removeTrackedApp)
                    }
                    HStack {
                        TextField("App name, e.g. Instagram", text: $newApp)
                            .textInputAutocapitalization(.words)
                            .onSubmit(addApp)
                        Button("Add", action: addApp).disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(Self.suggestions.filter { s in !state.config.trackedApps.contains(s) }, id: \.self) { s in
                                Button(s) { state.config.trackedApps.append(s) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }

                Section("2 · One \"opened\" automation per app") {
                    step(1, "Open the **Shortcuts** app → **Automation** tab → **+** (or **New Automation**).")
                    step(2, "Choose **App**. Tap **Choose**, pick the app (e.g. Instagram) → **Done**.")
                    step(3, "Select **Is Opened** only. Select **Run Immediately**. Tap **Next**.")
                    step(4, "Tap **New Blank Automation** → **Add Action** → search **Log App Opened** (Screentime). Type the app's name exactly as listed above.")
                    step(5, "Add action **If**. Set it to *If* **Result** *is* **true** (tap the grey Input box → **Result**).")
                    step(6, "Inside the If, add action **Open App** → choose **Screentime**. Tap **Done**.")
                    Text("Repeat for each app you track.").font(.caption).foregroundStyle(.secondary)
                }

                Section("3 · One \"closed\" automation for all of them") {
                    step(1, "Shortcuts → **Automation** → **+** → **App**.")
                    step(2, "Tap **Choose** and select **every** app you track.")
                    step(3, "Select **Is Closed** only, and **Run Immediately** → **Next**.")
                    step(4, "**New Blank Automation** → add action **Log App Closed** (Screentime) → **Done**.")
                }

                Section("Check it works") {
                    Text("Open one of your apps for a minute, then come back here. It should show up on the Today tab.")
                        .font(.callout)
                    if let last = state.lastEvent {
                        Label("Last automation event: \(last.formatted(date: .omitted, time: .shortened))", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }

                Section("Reinstalling every 7 days") {
                    Text("Apps installed with a free Apple ID stop opening after 7 days. Plug your iPhone into your Mac, open the Screentime project in Xcode and press ▶︎ Run. Your data and automations stay.")
                        .font(.callout)
                }
            }
            .navigationTitle("Setup")
        }
    }

    private func addApp() {
        let name = newApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        if !state.config.trackedApps.contains(where: { PhoneState.key(for: $0) == PhoneState.key(for: name) }) {
            state.config.trackedApps.append(name)
        }
        newApp = ""
    }

    private func step(_ number: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor.opacity(0.2)))
            Text(text).font(.callout)
        }
    }
}

struct PhoneSettingsView: View {
    @EnvironmentObject var state: PhoneState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Goals") {
                    Stepper(value: $state.config.preferences.dailyGoalMinutes, in: 0...960, step: 15) {
                        Text("Daily goal: \(state.config.preferences.dailyGoalMinutes == 0 ? "off" : Formatting.duration(Double(state.config.preferences.dailyGoalMinutes * 60)))")
                    }
                    TextField("Personal motto (shown on Time's Up)", text: $state.config.preferences.motto)
                }
                Section("Limits") {
                    Stepper(value: $state.config.preferences.warnMinutesBefore, in: 0...30) {
                        Text("Warn \(state.config.preferences.warnMinutesBefore) min before a limit")
                    }
                    Stepper(value: $state.config.preferences.snoozeMinutes, in: 1...30) {
                        Text("\"More time\" gives \(state.config.preferences.snoozeMinutes) min")
                    }
                }
                Section {
                    Stepper(value: $state.config.preferences.maxPhoneSessionMinutes, in: 5...240, step: 5) {
                        Text("Count at most \(state.config.preferences.maxPhoneSessionMinutes) min per visit")
                    }
                } footer: {
                    Text("Safety net in case a \"closed\" event is missed, e.g. when the phone locks.")
                }
                Section("Categories") {
                    ForEach(state.config.trackedApps, id: \.self) { app in
                        let key = PhoneState.key(for: app)
                        Picker(app, selection: Binding(
                            get: { state.category(forApp: key, name: app) },
                            set: { state.config.categoryOverrides["app:\(key)"] = $0 })) {
                            ForEach(Categories.all, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
