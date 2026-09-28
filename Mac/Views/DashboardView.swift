import SwiftUI

enum DashboardSection: String, CaseIterable, Identifiable {
    case today = "Today", week = "This Week", limits = "Limits", focus = "Focus Schedules", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .today: return "sun.max.fill"
        case .week: return "chart.bar.fill"
        case .limits: return "hourglass"
        case .focus: return "moon.stars.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

struct DashboardView: View {
    @State private var section: DashboardSection? = .today

    var body: some View {
        NavigationSplitView {
            List(DashboardSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(190)
        } detail: {
            switch section ?? .today {
            case .today: TodayView()
            case .week: WeekView()
            case .limits: LimitsView()
            case .focus: SchedulesView()
            case .settings: SettingsView()
            }
        }
    }
}
