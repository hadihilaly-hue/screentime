import SwiftUI

struct PhoneLimitsView: View {
    @EnvironmentObject var state: PhoneState
    @State private var editing: UsageLimit?

    var body: some View {
        NavigationStack {
            List {
                if state.config.limits.isEmpty {
                    Text("Add a daily limit for an app or a whole category. When you open it after the limit, Screentime pops up a Time's Up screen.")
                        .foregroundStyle(.secondary)
                }
                ForEach($state.config.limits) { $limit in
                    let used = state.today.seconds(for: limit.target)
                    let cap = Double(limit.minutesPerDay * 60)
                    Button { editing = limit } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(limit.displayName).font(.headline)
                                Text(limit.target.kind.label).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Toggle("", isOn: $limit.enabled).labelsHidden()
                            }
                            PhoneUsageBar(fraction: used / max(cap, 1), tint: used >= cap ? .red : .orange)
                            Text("\(Formatting.duration(used)) of \(Formatting.duration(cap)) today")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { state.config.limits.remove(atOffsets: $0) }
            }
            .navigationTitle("Limits")
            .toolbar {
                Button {
                    editing = UsageLimit(target: Target(kind: .app, value: ""), displayName: "", minutesPerDay: 30)
                } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { PhoneLimitEditor(limit: $0) }
        }
    }
}

struct PhoneLimitEditor: View {
    @EnvironmentObject var state: PhoneState
    @Environment(\.dismiss) private var dismiss
    @State var limit: UsageLimit

    var body: some View {
        NavigationStack {
            Form {
                PhoneTargetPicker(target: $limit.target, name: $limit.displayName)
                Stepper(value: $limit.minutesPerDay, in: 5...720, step: 5) {
                    Text("Daily limit: \(Formatting.duration(Double(limit.minutesPerDay * 60)))")
                }
                Toggle("Allow \"\(state.config.preferences.snoozeMinutes) more minutes\"", isOn: $limit.allowSnooze)
                Section("Note to yourself") {
                    TextField("e.g. You said you'd finish the essay first", text: $limit.note, axis: .vertical)
                }
                if state.config.limits.contains(where: { $0.id == limit.id }) {
                    Button("Delete limit", role: .destructive) {
                        state.config.limits.removeAll { $0.id == limit.id }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Limit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let i = state.config.limits.firstIndex(where: { $0.id == limit.id }) {
                            state.config.limits[i] = limit
                        } else {
                            state.config.limits.append(limit)
                        }
                        dismiss()
                    }
                    .disabled(limit.target.value.isEmpty)
                }
            }
        }
    }
}

struct PhoneTargetPicker: View {
    @EnvironmentObject var state: PhoneState
    @Binding var target: Target
    @Binding var name: String

    var body: some View {
        Picker("Type", selection: Binding(
            get: { target.kind },
            set: { target = Target(kind: $0, value: ""); name = "" })) {
            Text("App").tag(TargetKind.app)
            Text("Category").tag(TargetKind.category)
        }
        .pickerStyle(.segmented)

        let options: [(value: String, name: String)] = target.kind == .app
            ? state.config.trackedApps.map { (PhoneState.key(for: $0), $0) }
            : Categories.all.map { ($0, $0) }
        Picker(target.kind == .app ? "App" : "Category", selection: Binding(
            get: { target.value },
            set: { value in
                target = Target(kind: target.kind, value: value)
                name = options.first { $0.value == value }?.name ?? value
            })) {
            Text("Choose…").tag("")
            ForEach(options, id: \.value) { Text($0.name).tag($0.value) }
        }
        if target.kind == .app, state.config.trackedApps.isEmpty {
            Text("Add apps on the Setup tab first.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
