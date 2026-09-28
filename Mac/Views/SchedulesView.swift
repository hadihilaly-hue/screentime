import SwiftUI

struct SchedulesView: View {
    @EnvironmentObject var state: AppState
    @State private var editing: FocusSchedule?

    var body: some View {
        List {
            if state.config.schedules.isEmpty {
                Text("Focus schedules block apps, websites or categories during set hours — like homework time or bedtime.")
                    .foregroundStyle(.secondary)
            }
            ForEach($state.config.schedules) { $schedule in
                HStack(spacing: 12) {
                    Image(systemName: schedule.isActive(at: Date()) ? "moon.stars.fill" : "moon.stars")
                        .font(.title2)
                        .foregroundStyle(schedule.isActive(at: Date()) ? .indigo : .secondary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(schedule.name).font(.headline)
                        Text("\(Formatting.weekdays(schedule.weekdays)) · \(Formatting.clock(minuteOfDay: schedule.startMinute))–\(Formatting.clock(minuteOfDay: schedule.endMinute))")
                            .font(.caption).foregroundStyle(.secondary)
                        Text("Blocks: " + schedule.targets.map { schedule.name(for: $0) }.joined(separator: ", "))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Toggle("", isOn: $schedule.enabled).labelsHidden().toggleStyle(.switch)
                    Button("Edit") { editing = schedule }
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Focus Schedules")
        .toolbar {
            Button {
                editing = FocusSchedule(name: "Homework", weekdays: [1, 2, 3, 4, 5], startMinute: 16 * 60,
                                        endMinute: 19 * 60, targets: [])
            } label: { Label("Add schedule", systemImage: "plus") }
        }
        .sheet(item: $editing) { schedule in
            ScheduleEditor(schedule: schedule)
        }
    }
}

struct ScheduleEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var schedule: FocusSchedule
    @State private var pickTarget = Target(kind: .category, value: "")
    @State private var pickName = ""

    var body: some View {
        let exists = state.config.schedules.contains { $0.id == schedule.id }
        VStack(alignment: .leading, spacing: 16) {
            Text(exists ? "Edit focus schedule" : "New focus schedule").font(.title2.bold())
            Form {
                TextField("Name", text: $schedule.name)
                HStack {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Calendar.current.veryShortWeekdaySymbols[day - 1], isOn: Binding(
                            get: { schedule.weekdays.contains(day) },
                            set: { on in if on { schedule.weekdays.insert(day) } else { schedule.weekdays.remove(day) } }))
                        .toggleStyle(.button)
                    }
                }
                DatePicker("Starts", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                TextField("Note to yourself", text: $schedule.note, axis: .vertical).lineLimit(2...3)

                Section("Blocked during this time") {
                    ForEach(schedule.targets) { target in
                        HStack {
                            TargetIcon(target: target, size: 18)
                            Text(schedule.name(for: target))
                            Spacer()
                            Button {
                                schedule.targets.removeAll { $0 == target }
                            } label: { Image(systemName: "minus.circle.fill") }.buttonStyle(.borderless)
                        }
                    }
                    TargetPicker(target: $pickTarget, name: $pickName)
                    Button("Add to schedule") {
                        guard !pickTarget.value.isEmpty, !schedule.targets.contains(pickTarget) else { return }
                        schedule.targets.append(pickTarget)
                        schedule.targetNames[pickTarget.id] = pickName.isEmpty ? pickTarget.value : pickName
                    }
                    .disabled(pickTarget.value.isEmpty)
                }
            }
            HStack {
                if exists {
                    Button("Delete", role: .destructive) {
                        state.config.schedules.removeAll { $0.id == schedule.id }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    if let index = state.config.schedules.firstIndex(where: { $0.id == schedule.id }) {
                        state.config.schedules[index] = schedule
                    } else {
                        state.config.schedules.append(schedule)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(schedule.name.isEmpty || schedule.weekdays.isEmpty || schedule.targets.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<FocusSchedule, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minute = schedule[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: Date()) ?? Date()
            },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                schedule[keyPath: keyPath] = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            })
    }
}
