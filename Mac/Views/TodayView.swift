import Charts
import SwiftUI

struct TodayView: View {
    @EnvironmentObject var state: AppState
    @State private var newLimit: UsageLimit?

    var body: some View {
        let today = state.today
        let goal = Double(state.config.preferences.distractionGoalMinutes * 60)
        let distracted = state.config.distractionSeconds(today)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    StatCard(title: "Distractions", value: Formatting.duration(distracted),
                             subtitle: goal > 0 ? "Goal \(Formatting.duration(goal))" : nil, systemImage: "flame.fill")
                    StatCard(title: goal > 0 && distracted > goal ? "Over goal by" : "Left in goal",
                             value: goal > 0 ? Formatting.duration(abs(goal - distracted)) : "—",
                             systemImage: "target")
                    StatCard(title: "Screen time", value: Formatting.duration(today.total),
                             subtitle: "Homework counts here, not in the goal", systemImage: "clock.fill")
                    StatCard(title: "Most used", value: today.topApps.first.map { today.name(forApp: $0.id) } ?? "—",
                             subtitle: today.topApps.first.map { Formatting.duration($0.seconds) }, systemImage: "star.fill")
                    StatCard(title: "App switches", value: "\(today.opens.values.reduce(0, +))", systemImage: "arrow.left.arrow.right")
                }

                GroupBox("By hour") {
                    Chart(0..<24, id: \.self) { hour in
                        BarMark(x: .value("Hour", hour), y: .value("Minutes", today.hourly[hour] / 60))
                            .foregroundStyle(Color.accentColor.gradient)
                    }
                    .chartXScale(domain: 0...23)
                    .chartXAxis {
                        AxisMarks(values: [0, 6, 12, 18, 23]) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let h = value.as(Int.self) { Text(Formatting.clock(minuteOfDay: h * 60)) }
                            }
                        }
                    }
                    .chartYAxisLabel("minutes")
                    .frame(height: 170)
                    .padding(.top, 6)
                }

                HStack(alignment: .top, spacing: 16) {
                    GroupBox("Categories") { categoryList(today) }
                    GroupBox("Websites") { siteList(today) }
                }

                GroupBox("Apps") { appList(today) }
            }
            .padding(20)
        }
        .navigationTitle("Today")
        .sheet(item: $newLimit) { limit in
            LimitEditor(limit: limit, isNew: true)
        }
    }

    private func categoryList(_ today: DayUsage) -> some View {
        let items = today.topCategories
        let maxValue = max(items.first?.seconds ?? 1, 1)
        return VStack(spacing: 8) {
            if items.isEmpty { emptyRow }
            ForEach(items, id: \.id) { item in
                usageRow(target: Target(kind: .category, value: item.id), name: item.id,
                         seconds: item.seconds, fraction: item.seconds / maxValue, tint: .purple)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func siteList(_ today: DayUsage) -> some View {
        let items = Array(today.topSites.prefix(10))
        let maxValue = max(items.first?.seconds ?? 1, 1)
        return VStack(spacing: 8) {
            if items.isEmpty { emptyRow }
            ForEach(items, id: \.id) { item in
                usageRow(target: Target(kind: .site, value: item.id), name: item.id,
                         seconds: item.seconds, fraction: item.seconds / maxValue, tint: .blue)
                    .contextMenu { categoryMenu(key: "site:\(item.id)") }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func appList(_ today: DayUsage) -> some View {
        let items = today.topApps
        let maxValue = max(items.first?.seconds ?? 1, 1)
        return VStack(spacing: 8) {
            if items.isEmpty { emptyRow }
            ForEach(items, id: \.id) { item in
                usageRow(target: Target(kind: .app, value: item.id), name: today.name(forApp: item.id),
                         seconds: item.seconds, fraction: item.seconds / maxValue, tint: .accentColor,
                         detail: state.catalog.category(for: item.id, overrides: state.config.categoryOverrides))
                    .contextMenu { categoryMenu(key: "app:\(item.id)") }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var emptyRow: some View {
        Text("Nothing yet").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
    }

    private func usageRow(target: Target, name: String, seconds: Double, fraction: Double,
                          tint: Color, detail: String? = nil) -> some View {
        let limit = state.config.limits.first { $0.target == target && $0.enabled }
        return HStack(spacing: 10) {
            TargetIcon(target: target)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(name).lineLimit(1)
                    if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
                    Spacer()
                    if let limit {
                        Text("limit \(Formatting.duration(Double(limit.minutesPerDay * 60)))")
                            .font(.caption).foregroundStyle(.orange)
                    }
                    Text(Formatting.duration(seconds)).monospacedDigit().foregroundStyle(.secondary)
                }
                UsageBar(fraction: fraction, tint: tint)
            }
            Button {
                newLimit = limit ?? UsageLimit(target: target, displayName: name, minutesPerDay: 30)
            } label: {
                Image(systemName: limit == nil ? "hourglass.badge.plus" : "hourglass")
            }
            .buttonStyle(.borderless)
            .help(limit == nil ? "Add a daily limit" : "Edit limit")
        }
    }

    @ViewBuilder
    private func categoryMenu(key: String) -> some View {
        Menu("Set category") {
            ForEach(Categories.all, id: \.self) { category in
                Button(category) { state.setCategory(category, for: key) }
            }
        }
    }
}
