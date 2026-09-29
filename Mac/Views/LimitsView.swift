import SwiftUI
import UniformTypeIdentifiers

struct LimitsView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: UsageLimit?
    @State private var isNew = false

    var body: some View {
        List {
            if state.config.limits.isEmpty {
                Text("No limits yet. Add one here, or click the hourglass next to any app on the Today page.")
                    .foregroundStyle(.secondary)
            }
            ForEach($state.config.limits) { $limit in
                let used = state.today.seconds(for: limit.target)
                let cap = Double(limit.minutesPerDay * 60)
                HStack(spacing: 12) {
                    TargetIcon(target: limit.target, size: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(limit.displayName).font(.headline)
                            Text(limit.target.kind.label).font(.caption).foregroundStyle(.secondary)
                        }
                        UsageBar(fraction: used / max(cap, 1), tint: used >= cap ? .red : .orange)
                        Text("\(Formatting.duration(used)) of \(Formatting.duration(cap)) used today")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Toggle("", isOn: $limit.enabled).labelsHidden().toggleStyle(.switch)
                    Button("Edit") { isNew = false; editing = limit }
                }
                .padding(.vertical, 4)
                .contextMenu {
                    Button("Delete", role: .destructive) { state.config.limits.removeAll { $0.id == limit.id } }
                }
            }
        }
        .navigationTitle("Limits")
        .toolbar {
            Button {
                isNew = true
                editing = UsageLimit(target: Target(kind: .app, value: ""), displayName: "", minutesPerDay: 30)
            } label: { Label("Add limit", systemImage: "plus") }
        }
        .sheet(item: $editing) { limit in
            LimitEditor(limit: limit, isNew: isNew)
        }
    }
}

struct LimitEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var limit: UsageLimit
    let isNew: Bool

    var body: some View {
        let exists = state.config.limits.contains { $0.id == limit.id }
        VStack(alignment: .leading, spacing: 16) {
            Text(exists ? "Edit limit" : "New limit").font(.title2.bold())
            Form {
                TargetPicker(target: $limit.target, name: $limit.displayName)
                Stepper(value: $limit.minutesPerDay, in: 5...720, step: 5) {
                    Text("Daily limit: \(Formatting.duration(Double(limit.minutesPerDay * 60)))")
                }
                Toggle("Allow \"\(state.config.preferences.snoozeMinutes) more minutes\"", isOn: $limit.allowSnooze)
                TextField("Note to yourself (shown when time's up)", text: $limit.note, axis: .vertical)
                    .lineLimit(2...4)
            }
            .formStyle(.grouped)
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        state.config.limits.removeAll { $0.id == limit.id }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let index = state.config.limits.firstIndex(where: { $0.id == limit.id }) {
                        state.config.limits[index] = limit
                    } else {
                        state.config.limits.append(limit)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(limit.target.value.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}

/// Choose an app, website or category, from recent usage or by typing.
struct TargetPicker: View {
    @EnvironmentObject var state: AppState
    @Binding var target: Target
    @Binding var name: String

    var body: some View {
        Picker("Type", selection: Binding(
            get: { target.kind },
            set: { target = Target(kind: $0, value: ""); name = "" })) {
            ForEach(TargetKind.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)

        let choices = state.recentChoices(kind: target.kind)
        Picker(target.kind == .category ? "Category" : "Recently used", selection: Binding(
            get: { target.value },
            set: { value in
                target = Target(kind: target.kind, value: value)
                name = choices.first { $0.target.value == value }?.name ?? value
            })) {
            Text("Choose…").tag("")
            ForEach(choices) { Text($0.name).tag($0.target.value) }
            if !target.value.isEmpty, !choices.contains(where: { $0.target.value == target.value }) {
                Text(name.isEmpty ? target.value : name).tag(target.value)
            }
        }

        if target.kind == .app {
            Button("Choose an app from Applications…") { chooseApp() }
        }

        if target.kind == .site {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(LockInSettings.popular, id: \.site) { item in
                    Button(item.name) {
                        target = Target(kind: .site, value: item.site)
                        name = item.name
                    }
                    .buttonStyle(.bordered)
                    .tint(target.value == item.site ? .accentColor : nil)
                }
            }
            Text("Website limits work in Safari, Chrome, Arc, Brave, Edge, Vivaldi and Opera, in every window and every Chrome profile or Google account.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("…or type a website (e.g. youtube.com)", text: Binding(
                get: { target.value },
                set: { value in
                    let cleaned = BrowserInspector.domain(from: value.contains("://") ? value : "https://\(value)") ?? value
                    target = Target(kind: .site, value: cleaned)
                    name = cleaned
                }))
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier else { return }
        target = Target(kind: .app, value: id)
        name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
