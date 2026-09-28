import SwiftUI

struct RootView: View {
    @EnvironmentObject var state: PhoneState

    var body: some View {
        TabView {
            PhoneTodayView().tabItem { Label("Today", systemImage: "sun.max.fill") }
            PhoneWeekView().tabItem { Label("Week", systemImage: "chart.bar.fill") }
            PhoneLimitsView().tabItem { Label("Limits", systemImage: "hourglass") }
            PhoneFocusView().tabItem { Label("Focus", systemImage: "moon.stars.fill") }
            SetupView().tabItem { Label("Setup", systemImage: "wand.and.stars") }
        }
        .fullScreenCover(item: Binding(get: { state.pendingBlock }, set: { if $0 == nil { state.dismissBlock() } })) { block in
            TimesUpView(block: block)
        }
    }
}

struct PhoneUsageBar: View {
    let fraction: Double
    var tint: Color = .accentColor

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.15))
                Capsule().fill(tint).frame(width: max(4, geo.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 6)
    }
}

struct TimesUpView: View {
    @EnvironmentObject var state: PhoneState
    let block: PhoneBlock

    var body: some View {
        ZStack {
            LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom).ignoresSafeArea()
            VStack(spacing: 20) {
                Spacer()
                Image(systemName: block.canSnooze ? "hourglass" : "moon.stars.fill")
                    .font(.system(size: 64, weight: .light))
                Text(block.title)
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .multilineTextAlignment(.center)
                Text(block.detail)
                    .foregroundStyle(.white.opacity(0.75))
                    .multilineTextAlignment(.center)
                if !block.note.isEmpty {
                    Text("“\(block.note)”").font(.title3.italic()).multilineTextAlignment(.center).padding(.top, 8)
                }
                if !state.config.preferences.motto.isEmpty {
                    Text(state.config.preferences.motto).font(.headline).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Text("Swipe up to go home and do something else.")
                    .font(.footnote).foregroundStyle(.white.opacity(0.6))
                Button {
                    state.dismissBlock()
                } label: {
                    Text("OK, I'm done").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.white)
                .foregroundStyle(.indigo)
                if block.canSnooze {
                    Button("\(state.config.preferences.snoozeMinutes) more minutes of \(block.appName)") {
                        state.snooze(block)
                    }
                    .foregroundStyle(.white.opacity(0.8))
                }
            }
            .foregroundStyle(.white)
            .padding(28)
        }
    }
}
