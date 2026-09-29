import SwiftUI

struct LockInView: View {
    @EnvironmentObject var state: AppState
    @State private var minutes = 50
    @State private var pick = Target(kind: .site, value: "")
    @State private var pickName = ""
    @State private var allowPick = Target(kind: .app, value: "")
    @State private var allowPickName = ""
    @State private var newTrack = ""
    @State private var givingUp = false

    var body: some View {
        Form {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                if let session = state.config.activeLockIn(at: context.date) {
                    activeSection(session, now: context.date)
                } else {
                    startSection
                }
            }
            codesSection
            blockedSection
            musicSection
        }
        .formStyle(.grouped)
        .navigationTitle("Lock In")
        .onAppear { minutes = state.config.lockIn.minutes }
        .sheet(isPresented: $givingUp) {
            GiveUpSheet { state.giveUpLockIn() }
        }
    }

    private func activeSection(_ session: LockInSession, now: Date) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("You're locked in", systemImage: "lock.fill").font(.title2.bold())
                Text(Formatting.countdown(session.remaining(at: now)))
                    .font(.system(size: 54, weight: .bold, design: .rounded))
                    .monospacedDigit()
                UsageBar(fraction: 1 - session.remaining(at: now) / max(session.duration, 1), tint: .indigo)
                Text("Worked \(Formatting.duration(session.activeSeconds)) so far. Stay at the computer for at least \(Formatting.duration(session.duration * 0.7)) to earn \(state.config.lockIn.rewardMinutes) phone minutes.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Give up early…", role: .destructive) { givingUp = true }
            }
            .padding(.vertical, 6)
        }
    }

    private var startSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Blocks everything distracting until the timer ends, and plays your focus music on repeat. You can't snooze it, and quitting Screentime doesn't end it.")
                    .foregroundStyle(.secondary)
                Stepper(value: $minutes, in: 10...240, step: 5) {
                    Text("Length: \(Formatting.duration(Double(minutes * 60)))")
                }
                HStack {
                    ForEach([25, 50, 90], id: \.self) { m in
                        Button("\(m) min") { minutes = m }
                    }
                    Spacer()
                    Button {
                        state.startLockIn(minutes: minutes)
                    } label: {
                        Label("Lock In", systemImage: "lock.fill").padding(.horizontal, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(.indigo)
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var codesSection: some View {
        Section("Phone unlock codes") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let codes = state.todaysCodes(at: context.date)
                VStack(alignment: .leading, spacing: 8) {
                    if codes.isEmpty {
                        Text("Finish a Lock In to earn \(state.config.lockIn.rewardMinutes) minutes of Snapchat, Instagram and YouTube on your phone.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(codes.enumerated()), id: \.offset) { i, code in
                            HStack {
                                Text("Lock In \(i + 1)").foregroundStyle(.secondary)
                                Spacer()
                                Text("\(code.prefix(3)) \(code.suffix(3))")
                                    .font(.system(.title2, design: .monospaced).bold())
                                    .textSelection(.enabled)
                            }
                        }
                        let change = UnlockCode.nextChange(after: context.date).timeIntervalSince(context.date)
                        Text("Type a code into Screentime on your phone. Codes change in \(Formatting.countdown(change)), each works for 10 minutes and only once.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            LabeledContent("Pairing key") {
                Text(state.config.lockIn.pairingKey).font(.system(.body, design: .monospaced)).textSelection(.enabled)
            }
            Text("Type this key into Screentime on your iPhone (Focus → Earn your apps) once, so it can check the codes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var blockedSection: some View {
        let locked = state.lockIn != nil
        return Section("Blocked while locked in") {
            ForEach(Categories.all.filter { !["Productivity", "Education", "Utilities", "Other"].contains($0) }, id: \.self) { category in
                Toggle(isOn: Binding(
                    get: { state.config.lockIn.blockedCategories.contains(category) },
                    set: { on in
                        state.config.lockIn.blockedCategories.removeAll { $0 == category }
                        if on { state.config.lockIn.blockedCategories.append(category) }
                    })) {
                    Label(category, systemImage: Categories.icon(for: category))
                }
                .disabled(locked && state.config.lockIn.blockedCategories.contains(category))
            }
            ForEach(state.config.lockIn.blockedTargets) { target in
                targetRow(target, allowed: false, locked: locked)
            }
            TargetPicker(target: $pick, name: $pickName)
            Button("Also block this") {
                guard !pick.value.isEmpty, !state.config.lockIn.blockedTargets.contains(pick) else { return }
                state.config.lockIn.blockedTargets.append(pick)
                state.config.lockIn.targetNames[pick.id] = pickName.isEmpty ? pick.value : pickName
                pick = Target(kind: pick.kind, value: "")
                pickName = ""
            }
            .disabled(pick.value.isEmpty)

            Text("Always allowed").font(.headline).padding(.top, 6)
            Text("Apps or sites you need for school work, even if they're in a blocked category.")
                .font(.caption).foregroundStyle(.secondary)
            ForEach(state.config.lockIn.allowedTargets) { target in
                targetRow(target, allowed: true, locked: locked)
            }
            TargetPicker(target: $allowPick, name: $allowPickName)
            Button("Allow this") {
                guard !allowPick.value.isEmpty, !state.config.lockIn.allowedTargets.contains(allowPick) else { return }
                state.config.lockIn.allowedTargets.append(allowPick)
                state.config.lockIn.targetNames[allowPick.id] = allowPickName.isEmpty ? allowPick.value : allowPickName
                allowPick = Target(kind: allowPick.kind, value: "")
                allowPickName = ""
            }
            .disabled(allowPick.value.isEmpty || locked)
        }
    }

    private func targetRow(_ target: Target, allowed: Bool, locked: Bool) -> some View {
        HStack {
            TargetIcon(target: target, size: 18)
            Text(state.config.lockIn.name(for: target))
            Text(target.kind.label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Button(role: .destructive) {
                if allowed {
                    state.config.lockIn.allowedTargets.removeAll { $0 == target }
                } else {
                    state.config.lockIn.blockedTargets.removeAll { $0 == target }
                }
            } label: { Image(systemName: "minus.circle") }
            .buttonStyle(.borderless)
            .disabled(locked && !allowed)
        }
    }

    private var musicSection: some View {
        Section("Focus music") {
            Toggle("Play on repeat in Spotify while locked in", isOn: Binding(
                get: { state.config.lockIn.playMusic },
                set: { state.setLockInMusic($0) }))
            if !FocusMusic.isSpotifyInstalled {
                Text("Install the Spotify app from spotify.com/download to use this.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(Array(state.config.lockIn.tracks.enumerated()), id: \.offset) { i, link in
                HStack {
                    Image(systemName: "music.note")
                    Text(FocusMusic.uri(from: link).flatMap { LockInSettings.trackNames[$0] } ?? link).lineLimit(1)
                    Spacer()
                    Button(role: .destructive) {
                        state.config.lockIn.tracks.remove(at: i)
                    } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Paste a Spotify song link (Share → Copy Song Link)", text: $newTrack)
                Button("Add") {
                    state.config.lockIn.tracks.append(newTrack.trimmingCharacters(in: .whitespaces))
                    newTrack = ""
                }
                .disabled(FocusMusic.uri(from: newTrack) == nil)
            }
            if state.config.lockIn.tracks != LockInSettings.defaultTracks {
                Button("Reset to Experience + Solas") { state.config.lockIn.tracks = LockInSettings.defaultTracks }
            }
        }
    }
}
