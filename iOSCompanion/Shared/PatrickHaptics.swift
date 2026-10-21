import Combine
import Foundation
#if os(watchOS)
import WatchKit
#elseif os(iOS)
import UIKit
#endif

/// One playback path for the selective haptic map. The toggle defaults on.
@MainActor
final class PatrickHaptics: ObservableObject {
    static let shared = PatrickHaptics()

    private(set) var readingHeartRate = false
    private var lastPlayedAt: Date?
    private var lastBattery: String?

    func setReadingHeartRate(_ reading: Bool) { readingHeartRate = reading }

    /// Notification pulses stay one second apart so the gap rule can play each one.
    func playRepeated(_ moment: PatrickHapticMoment, count: Int, settings: PatrickExperienceSettings,
                      foreground: Bool, inWorkout: Bool = false, context: PatrickContextSnapshot = PatrickContextSnapshot()) {
        let total = max(0, count)
        Task { @MainActor in
            for index in 0..<total {
                if index > 0 { try? await Task.sleep(nanoseconds: 1_100_000_000) }
                _ = self.play(moment, settings: settings, foreground: foreground, inWorkout: inWorkout, context: context)
            }
        }
    }

    @discardableResult
    func play(
        _ moment: PatrickHapticMoment,
        settings: PatrickExperienceSettings,
        foreground: Bool,
        inWorkout: Bool = false,
        context: PatrickContextSnapshot = PatrickContextSnapshot(),
        at date: Date = .now
    ) -> Bool {
        let quiet = settings.scene == .sleeping || settings.isSleepTime(date)
        guard PatrickHapticPolicy.allows(
            moment: moment,
            enabled: settings.hapticsEnabled,
            foreground: foreground,
            inWorkout: inWorkout,
            readingHeartRate: readingHeartRate,
            quiet: quiet,
            now: date,
            lastPlayedAt: lastPlayedAt,
            context: context
        ) else { return false }
        lastPlayedAt = date
        perform(moment)
        return true
    }

    /// User-armed wake cues. Soft, medium, and firm reuse the existing settle,
    /// attention, and completion kinds. They do not spend the daily knock budget.
    @discardableResult
    func playAlarm(_ strength: PatrickWakeStrength, settings: PatrickExperienceSettings, foreground: Bool, at date: Date = .now) -> Bool {
        guard settings.hapticsEnabled, foreground, !readingHeartRate else { return false }
        if let lastPlayedAt, date.timeIntervalSince(lastPlayedAt) < PatrickHapticPolicy.minimumGap { return false }
        lastPlayedAt = date
        switch strength {
        case .soft: perform(.wake)
        case .medium: perform(.timerClosing)
        case .firm: perform(.timerDone)
        }
        return true
    }

    /// Plays only when charging becomes full. Opening the app already full is quiet.
    func noteBattery(charging: Bool, full: Bool, settings: PatrickExperienceSettings, foreground: Bool, at date: Date = .now) {
        let state = full ? "full" : (charging ? "charging" : "unplugged")
        if state == "full", lastBattery == "charging" {
            play(.chargingFull, settings: settings, foreground: foreground, at: date)
        }
        lastBattery = state
    }

    private func perform(_ moment: PatrickHapticMoment) {
        let kind = PatrickHapticPolicy.kind(for: moment)
        #if os(watchOS)
        switch kind {
        case .click:
            WKInterfaceDevice.current().play(.click)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                WKInterfaceDevice.current().play(.click)
                try? await Task.sleep(for: .milliseconds(140))
                WKInterfaceDevice.current().play(.click)
            }
        case .directionDown: WKInterfaceDevice.current().play(.directionDown)
        case .success: WKInterfaceDevice.current().play(.success)
        case .notification: WKInterfaceDevice.current().play(.notification)
        }
        #elseif os(iOS)
        switch kind {
        case .success:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .notification, .click:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .directionDown:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        #endif
    }
}
