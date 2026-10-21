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

    @Published private(set) var decreaseTick = 0
    private(set) var readingHeartRate = false
    private var lastPlayedAt: Date?
    private var lastFeedFullAt: Date?
    private var lastBattery: String?

    func setReadingHeartRate(_ reading: Bool) { readingHeartRate = reading }

    func play(
        _ moment: PatrickHapticMoment,
        settings: PatrickExperienceSettings,
        foreground: Bool,
        inWorkout: Bool = false,
        at date: Date = .now
    ) {
        if moment == .feedFull, let lastFeedFullAt, date.timeIntervalSince(lastFeedFullAt) < 8 { return }
        let quiet = settings.scene == .sleeping || settings.isSleepTime(date)
        guard PatrickHapticPolicy.allows(
            moment: moment,
            enabled: settings.hapticsEnabled,
            foreground: foreground,
            inWorkout: inWorkout,
            readingHeartRate: readingHeartRate,
            quiet: quiet,
            now: date,
            lastPlayedAt: lastPlayedAt
        ) else { return }
        lastPlayedAt = date
        if moment == .feedFull { lastFeedFullAt = date }
        perform(moment)
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
        case .directionUp: WKInterfaceDevice.current().play(.directionUp)
        case .directionDown: WKInterfaceDevice.current().play(.directionDown)
        case .retry: WKInterfaceDevice.current().play(.retry)
        case .success: WKInterfaceDevice.current().play(.success)
        case .notification: WKInterfaceDevice.current().play(.notification)
        case .failure: WKInterfaceDevice.current().play(.failure)
        case .decrease: decreaseTick &+= 1
        }
        #elseif os(iOS)
        switch kind {
        case .success, .directionUp:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .failure:
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        case .retry, .notification:
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .directionDown:
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        case .decrease:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            decreaseTick &+= 1
        }
        #endif
    }
}
