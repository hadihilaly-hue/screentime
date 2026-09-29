import Charts
import SwiftUI

struct WeekView: View {
    @EnvironmentObject var state: AppState

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
        let average = totals.reduce(0, +) / Double(max(totals.filter { $0 > 0 }.count, 1))
        let goalMinutes = Double(state.config.preferences.dailyGoalMinutes)
        let slices = days.flatMap { day -> [Slice] in
            let label = DayKey.date(for: day.day)?.formatted(.dateTime.weekday(.abbreviated)) ?? day.day
            return day.categories.map { Slice(day: day.day, label: label, category: $0.key, minutes: $0.value / 60) }
        }
        let categories = Categories.ordered(slices.map(\.category))
        var appTotals: [String: Double] = [:]
        var names: [String: String] = [:]
        for day in days {
            for (id, s) in day.apps { appTotals[id, default: 0] += s }
            names.merge(day.names) { _, new in new }
        }
        let topApps = appTotals.sorted { $0.value > $1.value }.prefix(10)

        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    StatCard(title: "Daily average", value: Formatting.duration(average), systemImage: "chart.line.uptrend.xyaxis")
                    StatCard(title: "This week", value: Formatting.duration(totals.reduce(0, +)), systemImage: "calendar")
                    StatCard(title: "Days under goal", value: "\(totals.filter { $0 > 0 && $0 <= goalMinutes * 60 }.count) / \(totals.filter { $0 > 0 }.count)",
                             systemImage: "checkmark.seal.fill")
                }
                GroupBox("Last 7 days") {
                    Chart {
                        ForEach(slices) { slice in
                            BarMark(x: .value("Day", slice.label), y: .value("Minutes", slice.minutes))
                                .foregroundStyle(by: .value("Category", slice.category))
                        }
                        if goalMinutes > 0 {
                            RuleMark(y: .value("Goal", goalMinutes))
                                .foregroundStyle(.red.opacity(0.6))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                .annotation(position: .top, alignment: .leading) {
                                    Text("goal").font(.caption2).foregroundStyle(.red)
                                }
                        }
                    }
                    .chartForegroundStyleScale(domain: categories, range: categories.map(Categories.color(for:)))
                    .chartYAxisLabel("minutes")
                    .frame(height: 260)
                    .padding(.top, 6)
                }
                GroupBox("Top apps this week") {
                    VStack(spacing: 8) {
                        ForEach(Array(topApps), id: \.key) { item in
                            HStack(spacing: 10) {
                                AppIcon(bundleID: item.key)
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(names[item.key] ?? item.key)
                                        Spacer()
                                        Text(Formatting.duration(item.value)).monospacedDigit().foregroundStyle(.secondary)
                                    }
                                    UsageBar(fraction: item.value / max(topApps.first?.value ?? 1, 1))
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(20)
        }
        .navigationTitle("This Week")
    }
}
