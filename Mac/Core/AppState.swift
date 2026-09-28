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
        if let site { result.append(Target(kind: .site, value: site)) }
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
        enforcer.state = self
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

    func save() {
        store.saveDay(today)
        ticksSinceSave = 0
    }

    // MARK: - Tracking

    func tick() {
        let now = Date()
        if let activity = lastActivity {
            let elapsed = min(now.timeIntervalSince(lastSampleDate), 10)
            if elapsed > 0 { record(activity, seconds: elapsed, at: lastSampleDate) }
        }
        if DayKey.key(for: now) != today.day {
            save()
            today = store.loadDay(DayKey.key(for: now))
            enforcer.resetForNewDay()
        }
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
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { $0.tick() }
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
