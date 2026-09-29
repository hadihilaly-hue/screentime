import AppKit
import ServiceManagement
import UserNotifications

struct Activity: Equatable {
    var appID: String
    var appName: String
    var site: String?
    var category: String

    var targets: [Target] {
        var result = [Target(kind: .app, value: appID), Target(kind: .category, value: category)]
        if let site { result += Domains.withParents(site).map { Target(kind: .site, value: $0) } }
        return result
    }

    var displayName: String { site ?? appName }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var today: DayUsage
    @Published var config: Config {
        didSet { if config != oldValue { store.saveConfig(config) } }
    }
    @Published var isPaused = false
    @Published private(set) var current: Activity?
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let store = JSONStore()
    let catalog = AppCatalog()
    let browser = BrowserInspector()
    let enforcer = Enforcer()
    let music = FocusMusic()

    private static let ignoredApps: Set<String> = [
        Bundle.main.bundleIdentifier ?? "com.hadihilaly.screentime.mac",
        "com.apple.loginwindow", "com.apple.ScreenSaver.Engine",
    ]

    private var timer: Timer?
    private var lastSampleDate = Date()
    private var lastActivity: Activity?
    private var screenLocked = false
    private var ticksSinceSave = 0
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []

    init() {
        today = store.loadDay(DayKey.key(for: Date()))
        config = store.loadConfig()
        if config.lockIn.pairingKey.isEmpty { config.lockIn.pairingKey = UnlockCode.newKey() }
        enforcer.state = self
        if config.activeLockIn() != nil, config.lockIn.playMusic { music.start(config.lockIn.tracks) }
        browser.onUpdate = { [weak self] in self?.tick() }
        startObserving()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        tick()
    }

    func history(days: Int) -> [DayUsage] {
        var days = store.history(days: days)
        if let last = days.indices.last, days[last].day == today.day { days[last] = today }
        return days
    }

    func name(for target: Target) -> String {
        switch target.kind {
        case .app: return today.names[target.value] ?? appName(for: target.value)
        case .site, .category: return target.value
        }
    }

    func appName(for bundleID: String) -> String {
        if let name = today.names[bundleID] { return name }
        if let url = catalog.url(for: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }

    func setCategory(_ category: String, for key: String) {
        config.categoryOverrides[key] = category
    }

    func togglePause() {
        tick()
        isPaused.toggle()
        tick()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Screentime: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    // MARK: - Lock In

    var lockIn: LockInSession? { config.activeLockIn() }

    /// The current unlock code for each Lock In finished today.
    func todaysCodes(at date: Date) -> [String] {
        let day = DayKey.key(for: date)
        let count = config.lockInsEarned[day] ?? 0
        return (0..<count).map { UnlockCode.code(key: config.lockIn.pairingKey, day: day, index: $0 + 1, at: date) }
    }

    func startLockIn(minutes: Int) {
        tick()
        guard config.lockInSession == nil else { return }
        let now = Date()
        config.lockIn.minutes = minutes
        config.lockInSession = LockInSession(start: now, end: now.addingTimeInterval(Double(minutes * 60)))
        if config.lockIn.playMusic { music.start(config.lockIn.tracks) }
        tick()
    }

    func giveUpLockIn() {
        config.lockInSession = nil
        music.stop()
        tick()
    }

    func setLockInMusic(_ on: Bool) {
        config.lockIn.playMusic = on
        if on, lockIn != nil { music.start(config.lockIn.tracks) } else { music.stop() }
    }

    private func updateLockIn(from start: Date, to end: Date, activity: Activity?, now: Date) {
        guard var session = config.lockInSession else { return }
        if let activity, config.lockIn.blockedTarget(in: activity.targets) == nil {
            let from = max(start, session.start), to = min(end, session.end)
            if to > from { session.activeSeconds += to.timeIntervalSince(from) }
        }
        guard now >= session.end else {
            config.lockInSession = session
            if config.lockIn.playMusic { music.poll() }
            return
        }
        config.lockInSession = nil
        music.stop()
        if session.earnedCode {
            let day = DayKey.key(for: session.end)
            config.lockInsEarned[day, default: 0] += 1
            enforcer.notify(title: "Lock In complete",
                            body: "Nice work. Open Screentime → Lock In for your phone unlock code.")
        } else {
            enforcer.notify(title: "Lock In over",
                            body: "You were away from the computer too much to earn an unlock code.")
        }
    }

    func save() {
        store.saveDay(today)
        ticksSinceSave = 0
    }

    // MARK: - Tracking

    func tick() {
        let now = Date()
        let start = lastSampleDate
        let end = min(now, start.addingTimeInterval(10))
        let split = min(end, Calendar.current.dateInterval(of: .day, for: start)?.end ?? end)
        if let activity = lastActivity, split > start {
            record(activity, seconds: split.timeIntervalSince(start), at: start)
        }
        if DayKey.key(for: now) != today.day {
            save()
            today = store.loadDay(DayKey.key(for: now))
            enforcer.resetForNewDay()
        }
        if let activity = lastActivity, end > split {
            record(activity, seconds: end.timeIntervalSince(split), at: split)
        }
        updateLockIn(from: start, to: end, activity: lastActivity, now: now)
        let activity = sample()
        if let activity, activity.appID != lastActivity?.appID {
            today.opens[activity.appID, default: 0] += 1
        }
        lastActivity = activity
        lastSampleDate = now
        if current != activity { current = activity }
        ticksSinceSave += 1
        if ticksSinceSave >= 6 { save() }
        enforcer.evaluate(activity: activity, now: now)
    }

    private func record(_ activity: Activity, seconds: Double, at date: Date) {
        today.apps[activity.appID, default: 0] += seconds
        today.names[activity.appID] = activity.appName
        if let site = activity.site { today.sites[site, default: 0] += seconds }
        today.categories[activity.category, default: 0] += seconds
        today.hourly[Calendar.current.component(.hour, from: date)] += seconds
    }

    private func sample() -> Activity? {
        guard !isPaused, !screenLocked else { return nil }
        let prefs = config.preferences
        if SystemActivity.idleSeconds() >= Double(prefs.idleSeconds),
           !(prefs.countMediaWhileIdle && SystemActivity.isMediaPlaying()) {
            return nil
        }
        guard let app = NSWorkspace.shared.frontmostApplication, let id = app.bundleIdentifier,
              !Self.ignoredApps.contains(id)
        else { return nil }
        var site: String?
        if prefs.trackWebsites, BrowserInspector.isBrowser(id) { site = browser.domain(for: id) }
        let siteCategory = site.flatMap { config.categoryOverrides["site:\($0)"] ?? Categories.forSite($0) }
        let category = siteCategory ?? catalog.category(for: id, overrides: config.categoryOverrides)
        return Activity(appID: id, appName: app.localizedName ?? id, site: site, category: category)
    }

    private func startObserving() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor (AppState) -> Void) {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    handler(self)
                }
            }
            observers.append((center, token))
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.browser.invalidate(); $0.tick() }
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            observe(workspace, name) { $0.tick(); $0.screenLocked = true; $0.tick(); $0.save() }
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification] {
            observe(workspace, name) { $0.screenLocked = false; $0.lastSampleDate = Date(); $0.tick() }
        }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) {
            $0.tick(); $0.screenLocked = true; $0.tick(); $0.save()
        }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) {
            $0.screenLocked = false; $0.lastSampleDate = Date(); $0.tick()
        }
        observe(NotificationCenter.default, NSApplication.willTerminateNotification) { $0.tick(); $0.save() }
    }
}
