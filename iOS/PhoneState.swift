import Foundation
import UserNotifications

struct PhoneBlock: Codable, Identifiable, Equatable {
    var id = UUID()
    var createdAt = Date()
    var title: String
    var detail: String
    var note: String
    var appName: String
    var targetID: String
    var canSnooze: Bool
    /// Blocked until a Mac Lock In unlock code is entered.
    var needsCode: Bool? = nil
}

/// Usage tracking driven by Shortcuts automations ("When Instagram is opened / closed").
@MainActor
final class PhoneState: ObservableObject {
    static let shared = PhoneState()
    static let suggestedApps = ["Instagram", "Snapchat", "YouTube", "TikTok", "X", "Reddit", "Netflix", "Roblox", "Discord"]

    struct OpenSession: Codable, Equatable {
        var app: String
        var name: String
        var start: Date
    }

    private struct Runtime: Codable {
        var session: OpenSession?
        var snoozedUntil: [String: Date] = [:]
        var pendingBlock: PhoneBlock?
        var lastEvent: Date?
    }

    @Published private(set) var today: DayUsage
    @Published var config: Config {
        didSet { if config != oldValue { store.saveConfig(config) } }
    }
    @Published var pendingBlock: PhoneBlock? {
        didSet { if pendingBlock != oldValue { saveRuntime() } }
    }
    @Published private(set) var openSession: OpenSession?
    @Published private(set) var lastEvent: Date?

    let store = JSONStore()
    private var snoozedUntil: [String: Date] = [:]
    private static let runtimeFile = "runtime.json"
    /// A Time's Up screen is only shown if Screentime opens shortly after the blocked app did.
    private static let blockLifetime: TimeInterval = 120

    private init() {
        today = store.loadDay(DayKey.key(for: Date()))
        config = store.loadConfig()
        loadRuntime()
    }

    static func key(for appName: String) -> String {
        appName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func category(forApp key: String, name: String) -> String {
        config.categoryOverrides["app:\(key)"] ?? Categories.forAppName(name) ?? "Other"
    }

    func history(days: Int) -> [DayUsage] {
        var days = store.history(days: days)
        if let last = days.indices.last, days[last].day == today.day { days[last] = today }
        return days
    }

    /// Picks up changes written while the app was in the background (e.g. by an intent).
    func reload() {
        today = store.loadDay(DayKey.key(for: Date()))
        let fresh = store.loadConfig()
        if fresh != config { config = fresh }
        loadRuntime()
    }

    // MARK: - Automation events

    /// Returns true when the app is over its limit or blocked by a focus schedule.
    func appOpened(_ rawName: String) -> Bool {
        reload()
        let now = Date()
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = Self.key(for: name)
        guard !key.isEmpty else { return false }
        endSession(at: now)
        today.opens[key, default: 0] += 1
        today.names[key] = name
        store.saveDay(today)
        if !config.trackedApps.contains(where: { Self.key(for: $0) == key }) {
            config.trackedApps.append(name)
        }
        openSession = OpenSession(app: key, name: name, start: now)
        lastEvent = now

        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        let block = evaluate(key: key, name: name, now: now)
        pendingBlock = block
        if block == nil { scheduleLimitAlerts(key: key, name: name, now: now) }
        saveRuntime()
        return block != nil
    }

    /// Ends the open session. A close for a different app than the one open is a late event and is ignored.
    func appClosed(_ rawName: String? = nil) {
        reload()
        lastEvent = Date()
        let key = rawName.map(Self.key(for:)) ?? ""
        if !key.isEmpty, let session = openSession, session.app != key {
            saveRuntime()
            return
        }
        endSession(at: Date())
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        saveRuntime()
    }

    /// Called when Screentime itself comes to the foreground: the tracked app is no longer on screen.
    func becameActive() {
        reload()
        if openSession != nil {
            endSession(at: Date())
            UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
            saveRuntime()
        }
    }

    func snooze(_ block: PhoneBlock) {
        snoozedUntil[block.targetID] = Date().addingTimeInterval(Double(config.preferences.snoozeMinutes * 60))
        pendingBlock = nil
        saveRuntime()
    }

    func dismissBlock() {
        pendingBlock = nil
    }

    /// Adds an app to the Setup list so its Shortcuts automations get set up.
    func track(_ rawName: String) {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !config.trackedApps.contains(where: { Self.key(for: $0) == Self.key(for: name) }) else { return }
        config.trackedApps.append(name)
    }

    // MARK: - Lock In and unlock codes

    func startLockIn(minutes: Int) {
        guard config.activeLockIn() == nil else { return }
        let now = Date()
        config.lockIn.minutes = minutes
        config.lockInSession = LockInSession(start: now, end: now.addingTimeInterval(Double(minutes * 60)))
    }

    func giveUpLockIn() {
        config.lockInSession = nil
    }

    var isUnlocked: Bool { (config.unlockedUntil ?? .distantPast) > Date() }

    /// Checks a code from the Mac. Returns an error message, or nil when the apps were unlocked.
    func redeem(_ code: String) -> String? {
        reload()
        let now = Date()
        let day = DayKey.key(for: now)
        guard !config.lockIn.pairingKey.isEmpty else { return "Type your Mac's pairing key first." }
        guard let index = UnlockCode.index(of: code, key: config.lockIn.pairingKey, day: day, at: now) else {
            return "That code is wrong or expired. Use the one showing on your Mac right now."
        }
        let id = "\(day)|\(index)"
        guard !config.usedCodes.contains(id) else { return "That Lock In's code was already used. Finish another one." }
        config.usedCodes = config.usedCodes.filter { $0.hasPrefix(day) } + [id]
        let from = max(now, config.unlockedUntil ?? now)
        config.unlockedUntil = from.addingTimeInterval(Double(config.lockIn.rewardMinutes * 60))
        pendingBlock = nil
        saveRuntime()
        return nil
    }

    func removeTrackedApp(_ name: String) {
        config.trackedApps.removeAll { $0 == name }
    }

    // MARK: - Rules

    private func evaluate(key: String, name: String, now: Date) -> PhoneBlock? {
        let targets = [Target(kind: .app, value: key), Target(kind: .category, value: category(forApp: key, name: name))]
        if let session = config.activeLockIn(at: now), let target = config.lockIn.blockedTarget(in: targets) {
            return PhoneBlock(
                title: "You're locked in",
                detail: "\(name) is off for \(Formatting.duration(session.remaining(at: now))) more. Get back to work.",
                note: "", appName: name, targetID: target.id, canSnooze: false)
        }
        if config.lockIn.requireCode, (config.unlockedUntil ?? .distantPast) <= now,
           let target = config.lockIn.blockedTarget(in: targets) {
            return PhoneBlock(
                title: "Earn it first",
                detail: "Finish a Lock In on your Mac, then type the code it shows to get \(config.lockIn.rewardMinutes) minutes of \(name).",
                note: "", appName: name, targetID: target.id, canSnooze: false, needsCode: true)
        }
        for schedule in config.schedules where schedule.isActive(at: now) {
            guard let target = schedule.targets.first(where: { targets.contains($0) }) else { continue }
            return PhoneBlock(
                title: "\(schedule.name) is on",
                detail: "\(schedule.name(for: target)) is off-limits until \(Formatting.clock(minuteOfDay: schedule.endMinute)).",
                note: schedule.note, appName: name, targetID: target.id, canSnooze: false)
        }
        for limit in config.limits where limit.enabled && targets.contains(limit.target) {
            if let until = snoozedUntil[limit.target.id], until > now { continue }
            let used = today.seconds(for: limit.target)
            let cap = Double(limit.minutesPerDay * 60)
            if used >= cap {
                return PhoneBlock(
                    title: "Time's up for \(limit.displayName)",
                    detail: "You've used \(Formatting.duration(used)) of your \(Formatting.duration(cap)) today.",
                    note: limit.note, appName: name, targetID: limit.target.id, canSnooze: limit.allowSnooze)
            }
        }
        return nil
    }

    private func scheduleLimitAlerts(key: String, name: String, now: Date) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let targets = [Target(kind: .app, value: key), Target(kind: .category, value: category(forApp: key, name: name))]
        let warn = Double(config.preferences.warnMinutesBefore * 60)
        if config.lockIn.requireCode, let until = config.unlockedUntil, until > now,
           config.lockIn.blockedTarget(in: targets) != nil {
            add(center, id: "unlock-up", after: until.timeIntervalSince(now),
                title: "Your earned time is up", body: "Put \(name) down. Finish another Lock In to earn more.")
        }
        for limit in config.limits where limit.enabled && targets.contains(limit.target) {
            let remaining = Double(limit.minutesPerDay * 60) - today.seconds(for: limit.target)
            guard remaining > 0 else { continue }
            add(center, id: "\(limit.id)-up", after: remaining,
                title: "Time's up for \(limit.displayName)",
                body: limit.note.isEmpty ? "You've reached today's limit. Time to put it down." : limit.note)
            if warn > 0, remaining > warn {
                add(center, id: "\(limit.id)-warn", after: remaining - warn,
                    title: "\(Formatting.duration(warn)) left on \(limit.displayName)", body: "Start wrapping up.")
            }
        }
        let goal = Double(config.preferences.dailyGoalMinutes * 60)
        if goal > 0, today.total < goal {
            add(center, id: "goal", after: goal - today.total,
                title: "Daily goal reached", body: "You've hit \(Formatting.duration(goal)) of phone time today.")
        }
    }

    private func add(_ center: UNUserNotificationCenter, id: String, after seconds: Double, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(seconds, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Recording

    private func endSession(at end: Date) {
        guard let session = openSession else { return }
        openSession = nil
        let cap = Double(config.preferences.maxPhoneSessionMinutes * 60)
        let stop = min(end, session.start.addingTimeInterval(cap))
        guard stop > session.start else { return }
        let category = category(forApp: session.app, name: session.name)
        let calendar = Calendar.current
        var cursor = session.start
        while cursor < stop {
            guard let hour = calendar.dateInterval(of: .hour, for: cursor) else { break }
            let chunkEnd = min(stop, hour.end)
            let seconds = chunkEnd.timeIntervalSince(cursor)
            let hourIndex = calendar.component(.hour, from: cursor)
            let dayKey = DayKey.key(for: cursor)
            var day = dayKey == today.day ? today : store.loadDay(dayKey)
            day.apps[session.app, default: 0] += seconds
            day.categories[category, default: 0] += seconds
            day.hourly[hourIndex] += seconds
            day.names[session.app] = session.name
            store.saveDay(day)
            if dayKey == today.day { today = day }
            cursor = chunkEnd
        }
        if DayKey.key(for: Date()) != today.day { today = store.loadDay(DayKey.key(for: Date())) }
    }

    private func loadRuntime() {
        let runtime = store.read(Runtime.self, named: Self.runtimeFile) ?? Runtime()
        openSession = runtime.session
        lastEvent = runtime.lastEvent
        snoozedUntil = runtime.snoozedUntil.filter { $0.value > Date() }
        let block = runtime.pendingBlock.flatMap { Date().timeIntervalSince($0.createdAt) < Self.blockLifetime ? $0 : nil }
        if block != pendingBlock { pendingBlock = block }
    }

    private func saveRuntime() {
        store.write(Runtime(session: openSession, snoozedUntil: snoozedUntil, pendingBlock: pendingBlock,
                            lastEvent: lastEvent),
                    named: Self.runtimeFile)
    }
}
