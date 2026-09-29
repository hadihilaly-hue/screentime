import Charts
import SwiftUI

struct PhoneTodayView: View {
    @EnvironmentObject var state: PhoneState
    @State private var showSettings = false

    var body: some View {
        let today = state.today
        let goal = Double(state.config.preferences.distractionGoalMinutes * 60)
        let distracted = state.config.distractionSeconds(today)
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(Formatting.duration(distracted)).font(.system(size: 40, weight: .bold, design: .rounded))
                            Text("on distractions").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(today.opens.values.reduce(0, +)) pickups").foregroundStyle(.secondary)
                        }
                        if goal > 0 {
                            PhoneUsageBar(fraction: distracted / goal, tint: distracted > goal ? .red : .accentColor)
                            Text(distracted > goal
                                 ? "\(Formatting.duration(distracted - goal)) over your \(Formatting.duration(goal)) goal"
                                 : "\(Formatting.duration(goal - distracted)) left in your \(Formatting.duration(goal)) goal")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("\(Formatting.duration(today.total)) total in tracked apps")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                if state.config.trackedApps.isEmpty {
                    Section {
                        Label("Open the Setup tab to connect your apps.", systemImage: "wand.and.stars")
                    }
                }
                Section("By hour") {
                    Chart(0..<24, id: \.self) { hour in
                        BarMark(x: .value("Hour", hour), y: .value("Minutes", today.hourly[hour] / 60))
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let h = value.as(Int.self) { Text(Formatting.clock(minuteOfDay: h * 60)) }
                            }
                        }
                    }
                    .frame(height: 140)
                }
                Section("Apps") {
                    let apps = today.topApps
                    if apps.isEmpty { Text("Nothing logged yet today.").foregroundStyle(.secondary) }
                    ForEach(apps, id: \.id) { item in
                        row(name: today.name(forApp: item.id), seconds: item.seconds,
                            fraction: item.seconds / max(apps.first?.seconds ?? 1, 1),
                            detail: "\(today.opens[item.id] ?? 0) opens · \(state.category(forApp: item.id, name: today.name(forApp: item.id)))")
                    }
                }
                Section("Categories") {
                    let categories = today.topCategories
                    ForEach(categories, id: \.id) { item in
                        row(name: item.id, seconds: item.seconds,
                            fraction: item.seconds / max(categories.first?.seconds ?? 1, 1), detail: nil, tint: .purple)
                    }
                }
            }
            .navigationTitle("Today")
            .toolbar {
                Button { showSettings = true } label: { Image(systemName: "gearshape") }
            }
            .sheet(isPresented: $showSettings) { PhoneSettingsView() }
            .refreshable { state.reload() }
        }
    }

    private func row(name: String, seconds: Double, fraction: Double, detail: String?, tint: Color = .accentColor) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(name)
                Spacer()
                Text(Formatting.duration(seconds)).monospacedDigit().foregroundStyle(.secondary)
            }
            PhoneUsageBar(fraction: fraction, tint: tint)
            if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(.vertical, 2)
    }
}

struct PhoneWeekView: View {
    @EnvironmentObject var state: PhoneState

    private struct Slice: Identifiable {
        let day: String
        let label: String
        let category: String
        let minutes: Double
        var id: String { "\(day)-\(category)" }
    }

    var body: some View {
        let days = state.history(days: 7)
        let totals = days.map(\.total)
        let active = totals.filter { $0 > 0 }
        let average = active.reduce(0, +) / Double(max(active.count, 1))
        let goalMinutes = Double(state.config.preferences.distractionGoalMinutes)
        let distractions = days.filter { $0.total > 0 }.map(state.config.distractionSeconds)
        let slices = days.flatMap { day -> [Slice] in
            let label = DayKey.date(for: day.day)?.formatted(.dateTime.weekday(.abbreviated)) ?? day.day
            return day.categories.map { Slice(day: day.day, label: label, category: $0.key, minutes: $0.value / 60) }
        }
        let categories = Categories.ordered(slices.map(\.category))
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Daily average").font(.caption).foregroundStyle(.secondary)
                            Text(Formatting.duration(average)).font(.title.bold())
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text("Under goal").font(.caption).foregroundStyle(.secondary)
                            Text("\(distractions.filter { $0 <= goalMinutes * 60 }.count) of \(active.count) days").font(.title3.bold())
                        }
                    }
                    Chart {
                        ForEach(slices) { slice in
                            BarMark(x: .value("Day", slice.label), y: .value("Minutes", slice.minutes))
                                .foregroundStyle(by: .value("Category", slice.category))
                        }
                    }
                    .chartForegroundStyleScale(domain: categories, range: categories.map(Categories.color(for:)))
                    .frame(height: 240)
                }
            }
            .navigationTitle("This Week")
        }
    }
}
