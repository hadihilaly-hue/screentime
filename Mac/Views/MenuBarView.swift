import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let today = state.today
        let goal = Double(state.config.preferences.dailyGoalMinutes * 60)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Formatting.duration(today.total))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("today").foregroundStyle(.secondary)
                Spacer()
                if goal > 0 {
                    Text("goal \(Formatting.duration(goal))").font(.caption).foregroundStyle(.secondary)
                }
            }
            if goal > 0 {
                UsageBar(fraction: today.total / goal, tint: today.total > goal ? .red : .accentColor)
            }
            if let current = state.current {
                HStack(spacing: 8) {
                    AppIcon(bundleID: current.appID, size: 18)
                    Text("Now: \(current.displayName)").lineLimit(1)
                    Spacer()
                    Text(current.category).font(.caption).foregroundStyle(.secondary)
                }
                .font(.callout)
            } else if state.isPaused {
                Label("Tracking paused", systemImage: "pause.circle").foregroundStyle(.orange)
            }
            Divider()
            let top = Array(today.topApps.prefix(6))
            if top.isEmpty {
                Text("Nothing tracked yet today.").foregroundStyle(.secondary)
            }
            ForEach(top, id: \.id) { item in
                HStack(spacing: 8) {
                    AppIcon(bundleID: item.id, size: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(today.name(forApp: item.id)).lineLimit(1)
                            Spacer()
                            Text(Formatting.duration(item.seconds)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        UsageBar(fraction: item.seconds / max(top.first?.seconds ?? 1, 1))
                    }
                }
                .font(.callout)
            }
            Divider()
            HStack {
                Button("Open Dashboard") {
                    openWindow(id: "dashboard")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                Button(state.isPaused ? "Resume" : "Pause") { state.togglePause() }
                Spacer()
                Button("Quit") { state.save(); NSApp.terminate(nil) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }
}
