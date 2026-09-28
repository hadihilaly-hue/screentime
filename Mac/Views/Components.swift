import SwiftUI

struct AppIcon: View {
    @EnvironmentObject var state: AppState
    let bundleID: String
    var size: CGFloat = 22

    var body: some View {
        Image(nsImage: state.catalog.icon(for: bundleID))
            .resizable()
            .frame(width: size, height: size)
    }
}

struct TargetIcon: View {
    let target: Target
    var size: CGFloat = 22

    var body: some View {
        switch target.kind {
        case .app:
            AppIcon(bundleID: target.value, size: size)
        case .site:
            Image(systemName: "globe").frame(width: size, height: size).foregroundStyle(.blue)
        case .category:
            Image(systemName: Categories.icon(for: target.value)).frame(width: size, height: size).foregroundStyle(.purple)
        }
    }
}

struct UsageBar: View {
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

struct StatCard: View {
    let title: String
    let value: String
    var subtitle: String?
    var systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage).font(.subheadline).foregroundStyle(.secondary)
            Text(value).font(.system(size: 28, weight: .semibold, design: .rounded))
            if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
    }
}

/// Everything the user has used recently, for building limits and schedules.
struct TargetChoice: Identifiable, Hashable {
    let target: Target
    let name: String
    var id: String { target.id }
}

extension AppState {
    func recentChoices(kind: TargetKind) -> [TargetChoice] {
        let week = history(days: 7)
        switch kind {
        case .app:
            var totals: [String: Double] = [:]
            var names: [String: String] = [:]
            for day in week {
                for (id, s) in day.apps { totals[id, default: 0] += s }
                names.merge(day.names) { _, new in new }
            }
            return totals.sorted { $0.value > $1.value }.map {
                TargetChoice(target: Target(kind: .app, value: $0.key), name: names[$0.key] ?? $0.key)
            }
        case .site:
            var totals: [String: Double] = [:]
            for day in week { for (id, s) in day.sites { totals[id, default: 0] += s } }
            return totals.sorted { $0.value > $1.value }.map {
                TargetChoice(target: Target(kind: .site, value: $0.key), name: $0.key)
            }
        case .category:
            return Categories.all.map { TargetChoice(target: Target(kind: .category, value: $0), name: $0) }
        }
    }
}
