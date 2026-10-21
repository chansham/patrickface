import Foundation
import UserNotifications

/// Replaces the single pending countdown alert. Pause, cancel, and a new end
/// time all flow through the planner, so the old request is removed.
@MainActor
final class PatrickCountdownNotifier {
    static let shared = PatrickCountdownNotifier()

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    /// Ask the first time a person starts a countdown, not at launch.
    func requestPermissionForNewCountdown() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound])
    }

    func sync(
        activity: PatrickLocalActivity?,
        breakSession: PatrickBreakSession?,
        legacy: PatrickCountdownLegacy?,
        settings: PatrickExperienceSettings,
        schedules: Bool,
        contextQuiet: Bool = false,
        now: Date = .now
    ) async {
        let planned = schedules ? PatrickCountdownPlanner.notices(
            activity: activity,
            breakSession: breakSession,
            legacy: legacy,
            settings: settings,
            now: now,
            contextQuiet: contextQuiet
        ) : []
        let desired = PatrickCountdownPlanner.pending(planned, now: now)
        let pending = await center.pendingNotificationRequests()
        let known = Set(pending.map(\.identifier)).filter { $0.hasPrefix(PatrickCountdownPlanner.prefix) }
        let keep = Set(desired.map(\.identifier))
        let stale = Array(known.subtracting(keep))
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            center.removeDeliveredNotifications(withIdentifiers: stale)
        }
        for notice in desired {
            await add(notice, now: now)
        }
    }

    private func add(_ notice: PatrickCountdownNotice, now: Date) async {
        let interval = notice.fireAt.timeIntervalSince(now)
        guard interval > 0 else { return }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, interval), repeats: false)
        let content = content(for: notice)
        let request = UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger)
        do {
            try await center.add(request)
        } catch {
            guard notice.breaksQuietFocus else { return }
            content.interruptionLevel = .active
            let fallback = UNNotificationRequest(identifier: notice.identifier, content: content, trigger: trigger)
            try? await center.add(fallback)
        }
    }

    private func content(for notice: PatrickCountdownNotice) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.threadIdentifier = "patrick.countdown"
        content.sound = notice.playsSound ? .default : nil
        if notice.breaksQuietFocus {
            content.interruptionLevel = .timeSensitive
        } else if notice.playsSound {
            content.interruptionLevel = .active
        } else {
            content.interruptionLevel = .passive
        }
        return content
    }
}
