import SwiftUI

private let lockableCategories = ["Social", "Entertainment", "Games", "Communication", "News", "Shopping", "Creativity"]

struct PhoneLockInSection: View {
    @EnvironmentObject var state: PhoneState
    @Environment(\.openURL) private var openURL
    @State private var minutes = 50
    @State private var givingUp = false

    var body: some View {
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let session = state.config.activeLockIn(at: context.date) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("You're locked in", systemImage: "lock.fill").font(.headline).foregroundStyle(.indigo)
                        Text(Formatting.countdown(session.remaining(at: context.date)))
                            .font(.system(size: 44, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        PhoneUsageBar(fraction: 1 - session.remaining(at: context.date) / max(session.duration, 1), tint: .indigo)
                        HStack {
                            Button { playMusic() } label: { Label("Focus music", systemImage: "music.note") }
                            Spacer()
                            Button("Give up early…", role: .destructive) { givingUp = true }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(.vertical, 4)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Stepper(value: $minutes, in: 10...240, step: 5) {
                            Text("Length: \(Formatting.duration(Double(minutes * 60)))")
                        }
                        Button {
                            state.startLockIn(minutes: minutes)
                            if state.config.lockIn.playMusic { playMusic() }
                        } label: {
                            Label("Lock In", systemImage: "lock.fill").frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                }
            }
        } header: {
            Text("Lock In")
        } footer: {
            Text("Blocks \(state.config.lockIn.blockedCategories.joined(separator: ", ")) until the timer ends and opens your focus music in Spotify (turn on repeat there). To earn unlock codes, do your Lock In on the Mac: it can check you're actually working.")
        }
        .onAppear { minutes = state.config.lockIn.minutes }
        .sheet(isPresented: $givingUp) {
            GiveUpSheet { state.giveUpLockIn() }.presentationDetents([.medium])
        }
    }

    private func playMusic() {
        if let link = state.config.lockIn.tracks.first, let url = URL(string: link) { openURL(url) }
    }
}

struct PhoneEarnSection: View {
    @EnvironmentObject var state: PhoneState
    @State private var key = ""
    @State private var turningOff = false

    var body: some View {
        let on = state.config.lockIn.requireCode
        Section {
            if on {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    if let until = state.config.unlockedUntil, until > context.date {
                        Label("Unlocked for \(Formatting.countdown(until.timeIntervalSince(context.date)))", systemImage: "lock.open.fill")
                            .foregroundStyle(.green).font(.headline)
                    } else {
                        Label("Locked until you enter a code", systemImage: "lock.fill")
                            .foregroundStyle(.indigo).font(.headline)
                    }
                }
                UnlockCodeField()
            } else {
                Text("Keep your distracting apps locked until you finish a Lock In on your Mac. Each finished Lock In shows a code that gives you \(state.config.lockIn.rewardMinutes) minutes.")
                    .font(.callout)
                TextField("Pairing key from Mac → Lock In", text: $key)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.body.monospaced())
                Button("Turn on") {
                    state.config.lockIn.pairingKey = UnlockCode.normalizedKey(key)
                    state.config.lockIn.requireCode = true
                }
                .disabled(UnlockCode.normalizedKey(key).count != 9)
            }
            ForEach(lockableCategories, id: \.self) { category in
                let blocked = state.config.lockIn.blockedCategories.contains(category)
                Toggle(isOn: Binding(
                    get: { blocked },
                    set: { value in
                        state.config.lockIn.blockedCategories.removeAll { $0 == category }
                        if value { state.config.lockIn.blockedCategories.append(category) }
                    })) {
                    Label(category, systemImage: Categories.icon(for: category))
                }
                .disabled(blocked && (on || state.config.activeLockIn() != nil))
            }
            if on {
                Button("Turn off…", role: .destructive) { turningOff = true }
            }
        } header: {
            Text("Earn your apps")
        } footer: {
            Text("Only apps with Shortcuts automations (Setup tab) can be locked. For a lock you can't get around, also set Settings → Screen Time → App Limits and let a parent choose the passcode.")
        }
        .onAppear { key = state.config.lockIn.pairingKey }
        .sheet(isPresented: $turningOff) {
            GiveUpSheet(title: "Turn off Earn your apps?",
                        detail: "Your apps will open without a code. To turn it off anyway, type:",
                        action: "Turn off") {
                state.config.lockIn.requireCode = false
            }
            .presentationDetents([.medium])
        }
    }
}

struct UnlockCodeField: View {
    @EnvironmentObject var state: PhoneState
    @State private var code = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Code from your Mac", text: $code)
                    .keyboardType(.numberPad)
                    .font(.title3.monospaced())
                Button("Unlock") {
                    error = state.redeem(code)
                    if error == nil { code = "" }
                }
                .buttonStyle(.borderedProminent)
                .disabled(code.filter(\.isNumber).count != 6)
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
