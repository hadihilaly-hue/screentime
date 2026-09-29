import Foundation

enum TargetKind: String, Codable, CaseIterable, Identifiable {
    case app, site, category
    var id: String { rawValue }
    var label: String {
        switch self {
        case .app: return "App"
        case .site: return "Website"
        case .category: return "Category"
        }
    }
}

struct Target: Codable, Hashable, Identifiable {
    var kind: TargetKind
    var value: String
    var id: String { "\(kind.rawValue):\(value)" }
}

struct UsageLimit: Codable, Identifiable, Equatable {
    var id = UUID()
    var target: Target
    var displayName: String
    var minutesPerDay: Int
    var enabled = true
    var allowSnooze = true
    var note = ""
}

struct FocusSchedule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// Calendar weekday numbers, 1 = Sunday ... 7 = Saturday.
    var weekdays: Set<Int>
    var startMinute: Int
    var endMinute: Int
    var targets: [Target]
    var targetNames: [String: String] = [:]
    var enabled = true
    var note = ""

    func isActive(at date: Date, calendar: Calendar = .current) -> Bool {
        guard enabled else { return false }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        let weekday = parts.weekday ?? 1
        if startMinute <= endMinute {
            return weekdays.contains(weekday) && minute >= startMinute && minute < endMinute
        }
        // Overnight window: the part after midnight belongs to the previous day's schedule.
        if minute >= startMinute { return weekdays.contains(weekday) }
        let previous = weekday == 1 ? 7 : weekday - 1
        return minute < endMinute && weekdays.contains(previous)
    }

    func name(for target: Target) -> String { targetNames[target.id] ?? target.value }
}

struct Preferences: Codable, Equatable {
    /// Daily goal for time on distractions (the Lock In blocked categories), not total screen time.
    var distractionGoalMinutes = 60
    var idleSeconds = 120
    var warnMinutesBefore = 5
    var snoozeMinutes = 5
    var trackWebsites = true
    var countMediaWhileIdle = true
    var maxPhoneSessionMinutes = 45
    var motto = ""

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Preferences()
        distractionGoalMinutes = try c.decodeIfPresent(Int.self, forKey: .distractionGoalMinutes) ?? d.distractionGoalMinutes
        idleSeconds = try c.decodeIfPresent(Int.self, forKey: .idleSeconds) ?? d.idleSeconds
        warnMinutesBefore = try c.decodeIfPresent(Int.self, forKey: .warnMinutesBefore) ?? d.warnMinutesBefore
        snoozeMinutes = try c.decodeIfPresent(Int.self, forKey: .snoozeMinutes) ?? d.snoozeMinutes
        trackWebsites = try c.decodeIfPresent(Bool.self, forKey: .trackWebsites) ?? d.trackWebsites
        countMediaWhileIdle = try c.decodeIfPresent(Bool.self, forKey: .countMediaWhileIdle) ?? d.countMediaWhileIdle
        maxPhoneSessionMinutes = try c.decodeIfPresent(Int.self, forKey: .maxPhoneSessionMinutes) ?? d.maxPhoneSessionMinutes
        motto = try c.decodeIfPresent(String.self, forKey: .motto) ?? d.motto
    }
}

struct Config: Codable, Equatable {
    var limits: [UsageLimit] = []
    var schedules: [FocusSchedule] = []
    var preferences = Preferences()
    /// "app:<id>" or "site:<domain>" -> category name.
    var categoryOverrides: [String: String] = [:]
    /// iPhone only: app names the user has set up Shortcuts automations for.
    var trackedApps: [String] = []
    var lockIn = LockInSettings()
    var lockInSession: LockInSession?
    /// Mac: Lock Ins finished per day ("YYYY-MM-DD" -> count); each one issues an unlock code.
    var lockInsEarned: [String: Int] = [:]
    /// iPhone: codes already used ("YYYY-MM-DD|index").
    var usedCodes: [String] = []
    /// iPhone: blocked categories are open until this time after entering a code.
    var unlockedUntil: Date?

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        limits = try c.decodeIfPresent([UsageLimit].self, forKey: .limits) ?? []
        schedules = try c.decodeIfPresent([FocusSchedule].self, forKey: .schedules) ?? []
        preferences = try c.decodeIfPresent(Preferences.self, forKey: .preferences) ?? Preferences()
        categoryOverrides = try c.decodeIfPresent([String: String].self, forKey: .categoryOverrides) ?? [:]
        trackedApps = try c.decodeIfPresent([String].self, forKey: .trackedApps) ?? []
        lockIn = try c.decodeIfPresent(LockInSettings.self, forKey: .lockIn) ?? LockInSettings()
        lockInSession = try c.decodeIfPresent(LockInSession.self, forKey: .lockInSession)
        lockInsEarned = try c.decodeIfPresent([String: Int].self, forKey: .lockInsEarned) ?? [:]
        usedCodes = try c.decodeIfPresent([String].self, forKey: .usedCodes) ?? []
        unlockedUntil = try c.decodeIfPresent(Date.self, forKey: .unlockedUntil)
    }

    /// Social, Entertainment, Games etc.: what the daily goal and Lock In are about.
    var distractionCategories: [String] { lockIn.blockedCategories }

    func distractionSeconds(_ day: DayUsage) -> Double { day.seconds(inCategories: distractionCategories) }

    func activeLockIn(at now: Date = Date()) -> LockInSession? {
        guard let session = lockInSession, session.end > now else { return nil }
        return session
    }
}

struct DayUsage: Codable, Equatable {
    var day: String
    /// App id (bundle id on Mac, lowercased name on iPhone) -> seconds.
    var apps: [String: Double] = [:]
    var sites: [String: Double] = [:]
    var categories: [String: Double] = [:]
    var hourly: [Double] = Array(repeating: 0, count: 24)
    var opens: [String: Int] = [:]
    var names: [String: String] = [:]

    init(day: String) { self.day = day }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        day = try c.decode(String.self, forKey: .day)
        apps = try c.decodeIfPresent([String: Double].self, forKey: .apps) ?? [:]
        sites = try c.decodeIfPresent([String: Double].self, forKey: .sites) ?? [:]
        categories = try c.decodeIfPresent([String: Double].self, forKey: .categories) ?? [:]
        hourly = try c.decodeIfPresent([Double].self, forKey: .hourly) ?? Array(repeating: 0, count: 24)
        if hourly.count != 24 { hourly = Array(repeating: 0, count: 24) }
        opens = try c.decodeIfPresent([String: Int].self, forKey: .opens) ?? [:]
        names = try c.decodeIfPresent([String: String].self, forKey: .names) ?? [:]
    }

    var total: Double { hourly.reduce(0, +) }

    func seconds(inCategories names: [String]) -> Double {
        names.reduce(0) { $0 + (categories[$1] ?? 0) }
    }

    func seconds(for target: Target) -> Double {
        switch target.kind {
        case .app: return apps[target.value] ?? 0
        case .site:
            return sites.reduce(0) { total, entry in
                entry.key == target.value || entry.key.hasSuffix("." + target.value) ? total + entry.value : total
            }
        case .category: return categories[target.value] ?? 0
        }
    }

    func name(forApp id: String) -> String { names[id] ?? id }

    var topApps: [(id: String, seconds: Double)] {
        apps.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    var topSites: [(id: String, seconds: Double)] {
        sites.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }

    var topCategories: [(id: String, seconds: Double)] {
        categories.map { ($0.key, $0.value) }.sorted { $0.1 > $1.1 }
    }
}

enum DayKey {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func key(for date: Date) -> String { formatter.string(from: date) }
    static func date(for key: String) -> Date? { formatter.date(from: key) }
}

enum Formatting {
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return total > 0 ? "<1m" : "0m"
    }

    /// "23:05" or "1:02:09".
    static func countdown(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.up)))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func clock(minuteOfDay: Int) -> String {
        var parts = DateComponents()
        parts.hour = minuteOfDay / 60
        parts.minute = minuteOfDay % 60
        let date = Calendar.current.date(from: parts) ?? Date()
        return date.formatted(date: .omitted, time: .shortened)
    }

    static func weekdays(_ days: Set<Int>) -> String {
        if days.count == 7 { return "Every day" }
        if days == [2, 3, 4, 5, 6] { return "Weekdays" }
        if days == [1, 7] { return "Weekends" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return days.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
    }
}
