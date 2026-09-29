import AppKit
import UserNotifications

struct BlockReason: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var note: String
    var target: Target
    var activity: Activity
    var canSnooze: Bool
}

/// Applies limits and focus schedules to the current activity.
@MainActor
final class Enforcer {
    weak var state: AppState?
    let overlay = BlockOverlayController()

    private var warned: Set<UUID> = []
    private var goalNotified = false
    private var snoozedUntil: [String: Date] = [:]
    private var shown: BlockReason?

    func resetForNewDay() {
        warned.removeAll()
        snoozedUntil.removeAll()
        goalNotified = false
    }

    func evaluate(activity: Activity?, now: Date) {
        guard let state else { return }
        let prefs = state.config.preferences

        let goal = Double(prefs.distractionGoalMinutes * 60)
        if goal > 0, !goalNotified, state.config.distractionSeconds(state.today) >= goal {
            goalNotified = true
            notify(title: "Distraction goal reached",
                   body: "You've spent \(Formatting.duration(goal)) on \(state.config.distractionCategories.joined(separator: ", ")) today.")
        }

        if overlay.isVisible {
            if let shown, blockReason(for: shown.activity, now: now, warn: false) == nil {
                overlay.dismiss()
                self.shown = nil
            }
            return
        }
        guard var activity else { return }
        if prefs.trackWebsites, BrowserInspector.isBrowser(activity.appID), !state.browser.isFresh(activity.appID) {
            activity.site = nil
            activity.category = state.catalog.category(for: activity.appID, overrides: state.config.categoryOverrides)
        }
        if let reason = blockReason(for: activity, now: now, warn: true) { block(reason) }
    }

    private func blockReason(for activity: Activity, now: Date, warn: Bool) -> BlockReason? {
        guard let state else { return nil }
        let prefs = state.config.preferences
        let targets = activity.targets

        if let session = state.config.activeLockIn(at: now),
           let target = state.config.lockIn.blockedTarget(in: targets) {
            let parts = Calendar.current.dateComponents([.hour, .minute], from: session.end)
            let until = Formatting.clock(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0))
            return BlockReason(
                title: "You're locked in",
                detail: "\(activity.displayName) is off until \(until). Get back to work: \(Formatting.duration(session.remaining(at: now))) to go.",
                note: "", target: target, activity: activity, canSnooze: false)
        }

        for schedule in state.config.schedules where schedule.isActive(at: now) {
            guard let target = schedule.targets.first(where: { targets.contains($0) }) else { continue }
            return BlockReason(
                title: "\(schedule.name) is on",
                detail: "\(schedule.name(for: target)) is off-limits until \(Formatting.clock(minuteOfDay: schedule.endMinute)).",
                note: schedule.note, target: target, activity: activity, canSnooze: false)
        }

        for limit in state.config.limits where limit.enabled && targets.contains(limit.target) {
            if let until = snoozedUntil[limit.target.id], until > now { continue }
            let used = state.today.seconds(for: limit.target)
            let cap = Double(limit.minutesPerDay * 60)
            if used >= cap {
                return BlockReason(
                    title: "Time's up for \(limit.displayName)",
                    detail: "You've used \(Formatting.duration(used)) of your \(Formatting.duration(cap)) today.",
                    note: limit.note, target: limit.target, activity: activity, canSnooze: limit.allowSnooze)
            }
            let warnAt = cap - Double(prefs.warnMinutesBefore * 60)
            if warn, prefs.warnMinutesBefore > 0, used >= warnAt, !warned.contains(limit.id) {
                warned.insert(limit.id)
                notify(title: "\(Formatting.duration(cap - used)) left on \(limit.displayName)",
                       body: limit.note.isEmpty ? "Start wrapping up." : limit.note)
            }
        }
        return nil
    }

    private func block(_ reason: BlockReason) {
        guard let state else { return }
        let snoozeMinutes = state.config.preferences.snoozeMinutes
        shown = reason
        overlay.show(
            reason,
            motto: state.config.preferences.motto,
            snoozeMinutes: snoozeMinutes,
            onLeave: { [weak self] in self?.leave(reason) },
            onSnooze: { [weak self] in
                self?.snoozedUntil[reason.target.id] = Date().addingTimeInterval(Double(snoozeMinutes * 60))
                self?.overlay.dismiss()
            })
    }

    private func leave(_ reason: BlockReason) {
        let activity = reason.activity
        overlay.dismiss()
        if activity.site != nil, reason.target.kind != .app {
            state?.browser.closeActiveTab(bundleID: activity.appID)
        } else {
            NSRunningApplication.runningApplications(withBundleIdentifier: activity.appID).forEach { $0.hide() }
        }
        NSApp.hide(nil)
    }

    func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
