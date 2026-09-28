import SwiftUI

struct PhoneFocusView: View {
    @EnvironmentObject var state: PhoneState
    @State private var editing: FocusSchedule?

    var body: some View {
        NavigationStack {
            List {
                if state.config.schedules.isEmpty {
                    Text("Focus schedules block apps or categories during set hours — like homework time or bedtime.")
                        .foregroundStyle(.secondary)
                }
                ForEach($state.config.schedules) { $schedule in
                    Button { editing = schedule } label: {
                        HStack {
                            Image(systemName: schedule.isActive(at: Date()) ? "moon.stars.fill" : "moon.stars")
                                .foregroundStyle(schedule.isActive(at: Date()) ? .indigo : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(schedule.name).font(.headline)
                                Text("\(Formatting.weekdays(schedule.weekdays)) · \(Formatting.clock(minuteOfDay: schedule.startMinute))–\(Formatting.clock(minuteOfDay: schedule.endMinute))")
                                    .font(.caption).foregroundStyle(.secondary)
                                Text(schedule.targets.map { schedule.name(for: $0) }.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            Toggle("", isOn: $schedule.enabled).labelsHidden()
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { state.config.schedules.remove(atOffsets: $0) }
            }
            .navigationTitle("Focus")
            .toolbar {
                Button {
                    editing = FocusSchedule(name: "Bedtime", weekdays: Set(1...7), startMinute: 22 * 60,
                                            endMinute: 7 * 60, targets: [])
                } label: { Image(systemName: "plus") }
            }
            .sheet(item: $editing) { PhoneScheduleEditor(schedule: $0) }
        }
    }
}

struct PhoneScheduleEditor: View {
    @EnvironmentObject var state: PhoneState
    @Environment(\.dismiss) private var dismiss
    @State var schedule: FocusSchedule
    @State private var pickTarget = Target(kind: .category, value: "")
    @State private var pickName = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $schedule.name)
                Section("Days") {
                    HStack {
                        ForEach(1...7, id: \.self) { day in
                            let on = schedule.weekdays.contains(day)
                            Button(Calendar.current.veryShortWeekdaySymbols[day - 1]) {
                                if on { schedule.weekdays.remove(day) } else { schedule.weekdays.insert(day) }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .background(Circle().fill(on ? Color.accentColor : Color.secondary.opacity(0.15)))
                            .foregroundStyle(on ? .white : .primary)
                            .buttonStyle(.plain)
                        }
                    }
                }
                Section("Time") {
                    DatePicker("Starts", selection: minuteBinding(\.startMinute), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: minuteBinding(\.endMinute), displayedComponents: .hourAndMinute)
                }
                Section("Blocked during this time") {
                    ForEach(schedule.targets) { target in
                        Text(schedule.name(for: target))
                    }
                    .onDelete { schedule.targets.remove(atOffsets: $0) }
                    PhoneTargetPicker(target: $pickTarget, name: $pickName)
                    Button("Add") {
                        guard !pickTarget.value.isEmpty, !schedule.targets.contains(pickTarget) else { return }
                        schedule.targets.append(pickTarget)
                        schedule.targetNames[pickTarget.id] = pickName.isEmpty ? pickTarget.value : pickName
                    }
                    .disabled(pickTarget.value.isEmpty)
                }
                Section("Note to yourself") {
                    TextField("e.g. Sleep > scrolling", text: $schedule.note, axis: .vertical)
                }
                if state.config.schedules.contains(where: { $0.id == schedule.id }) {
                    Button("Delete schedule", role: .destructive) {
                        state.config.schedules.removeAll { $0.id == schedule.id }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Focus schedule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if let i = state.config.schedules.firstIndex(where: { $0.id == schedule.id }) {
                            state.config.schedules[i] = schedule
                        } else {
                            state.config.schedules.append(schedule)
                        }
                        dismiss()
                    }
                    .disabled(schedule.name.isEmpty || schedule.weekdays.isEmpty || schedule.targets.isEmpty)
                }
            }
        }
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
