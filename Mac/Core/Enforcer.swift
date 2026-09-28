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

    func resetForNewDay() {
        warned.removeAll()
        snoozedUntil.removeAll()
        goalNotified = false
    }

    func evaluate(activity: Activity?, now: Date) {
        guard let state else { return }
        let prefs = state.config.preferences

        let goal = Double(prefs.dailyGoalMinutes * 60)
        if goal > 0, !goalNotified, state.today.total >= goal {
            goalNotified = true
            notify(title: "Daily goal reached", body: "You've hit \(Formatting.duration(goal)) of screen time today.")
        }

        guard let activity, !overlay.isVisible else { return }
        let targets = activity.targets

        for schedule in state.config.schedules where schedule.isActive(at: now) {
            guard let target = schedule.targets.first(where: { targets.contains($0) }) else { continue }
            block(BlockReason(
                title: "\(schedule.name) is on",
                detail: "\(schedule.name(for: target)) is off-limits until \(Formatting.clock(minuteOfDay: schedule.endMinute)).",
                note: schedule.note, target: target, activity: activity, canSnooze: false))
            return
        }

        for limit in state.config.limits where limit.enabled && targets.contains(limit.target) {
            if let until = snoozedUntil[limit.target.id], until > now { continue }
            let used = state.today.seconds(for: limit.target)
            let cap = Double(limit.minutesPerDay * 60)
            if used >= cap {
                block(BlockReason(
                    title: "Time's up for \(limit.displayName)",
                    detail: "You've used \(Formatting.duration(used)) of your \(Formatting.duration(cap)) today.",
                    note: limit.note, target: limit.target, activity: activity, canSnooze: limit.allowSnooze))
                return
            }
            let warnAt = cap - Double(prefs.warnMinutesBefore * 60)
            if prefs.warnMinutesBefore > 0, used >= warnAt, !warned.contains(limit.id) {
                warned.insert(limit.id)
                notify(title: "\(Formatting.duration(cap - used)) left on \(limit.displayName)",
                       body: limit.note.isEmpty ? "Start wrapping up." : limit.note)
            }
        }
    }

    private func block(_ reason: BlockReason) {
        guard let state else { return }
        let snoozeMinutes = state.config.preferences.snoozeMinutes
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

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
    }
}
