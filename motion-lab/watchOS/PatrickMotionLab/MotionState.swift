import Foundation
import SwiftUI
import WatchKit

enum FaceMode: String, CaseIterable {
    case awake
    case focus
    case sleep
}

enum MotionPerformanceTier: String {
    case active
    case alwaysOn
    case lowPower

    var framesPerSecond: Double {
        switch self {
        case .active: 30
        case .alwaysOn: 1
        case .lowPower: 0.2
        }
    }

    var animatesAmbientMotion: Bool { self == .active }
}

struct MotionPose {
    let tier: MotionPerformanceTier
    let hourTarget: Double
    let minuteTarget: Double
    let hourActual: Double
    let minuteActual: Double
    let idleWeight: Double
    let tapWeight: Double
    let breath: Double
    let blink: Double
    let sleepAmount: Double
    let focusAmount: Double
    let slump: Double
    let chargingPulse: Double
    let crown: Double
    let spriteFrame: Int?

    var maximumHandError: Double {
        max(
            MotionMath.shortestAngleError(hourActual, hourTarget),
            MotionMath.shortestAngleError(minuteActual, minuteTarget)
        )
    }
}

enum MotionMath {
    static let idleDuration = 1.8
    static let tapDuration = 0.56
    static let blinkDuration = 0.24
    static let spriteDuration = 0.84
    static let spriteFrameCount = 6

    static func clamp(_ value: Double, _ minimum: Double = 0, _ maximum: Double = 1) -> Double {
        min(maximum, max(minimum, value))
    }

    static func lerp(_ a: Double, _ b: Double, _ amount: Double) -> Double {
        a + (b - a) * amount
    }

    static func smoothstep(_ value: Double) -> Double {
        let x = clamp(value)
        return x * x * (3 - 2 * x)
    }

    static func envelope(elapsed: TimeInterval, duration: TimeInterval) -> Double {
        guard elapsed > 0, elapsed < duration else { return 0 }
        let sine = sin(.pi * elapsed / duration)
        return sine * sine
    }

    static func normalizedDegrees(_ value: Double) -> Double {
        let remainder = value.truncatingRemainder(dividingBy: 360)
        return remainder >= 0 ? remainder : remainder + 360
    }

    static func shortestAngleError(_ actual: Double, _ expected: Double) -> Double {
        abs((actual - expected + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    static func clockAngles(date: Date, calendar: Calendar = .current) -> (hour: Double, minute: Double) {
        let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let nanoseconds = Double(parts.nanosecond ?? 0)
        let seconds = Double(parts.second ?? 0) + nanoseconds / 1_000_000_000
        let minutes = Double(parts.minute ?? 0) + seconds / 60
        let hours = Double((parts.hour ?? 0) % 12) + minutes / 60
        return (normalizedDegrees(hours * 30), normalizedDegrees(minutes * 6))
    }

    static func makePose(
        date: Date,
        tier: MotionPerformanceTier,
        currentMode: FaceMode,
        previousMode: FaceMode,
        modeChangedAt: TimeInterval,
        crown: Double,
        lowBattery: Bool,
        charging: Bool,
        idleStartedAt: TimeInterval?,
        tapStartedAt: TimeInterval?,
        blinkStartedAt: TimeInterval?,
        spriteStartedAt: TimeInterval?
    ) -> MotionPose {
        let now = date.timeIntervalSinceReferenceDate
        let target = clockAngles(date: date)
        let animated = tier.animatesAmbientMotion

        var idleElapsed = -1.0
        if let idleStartedAt, now - idleStartedAt <= idleDuration {
            idleElapsed = now - idleStartedAt
        } else {
            let phase = now.truncatingRemainder(dividingBy: 12)
            if phase >= 0, phase < idleDuration { idleElapsed = phase }
        }
        let idleWeight = animated ? envelope(elapsed: idleElapsed, duration: idleDuration) : 0
        let hourOffset = -5 * idleWeight
        let minuteOffset = 19 * idleWeight

        let tapElapsed = tapStartedAt.map { now - $0 } ?? -1
        let tapWeight = animated ? envelope(elapsed: tapElapsed, duration: tapDuration) : 0

        var blinkElapsed = blinkStartedAt.map { now - $0 } ?? -1
        if blinkElapsed < 0 || blinkElapsed >= blinkDuration {
            let phase = now.truncatingRemainder(dividingBy: 4.8)
            blinkElapsed = phase < blinkDuration ? phase : -1
        }
        let blink = animated ? envelope(elapsed: blinkElapsed, duration: blinkDuration) : 0

        let transition = smoothstep((now - modeChangedAt) / 0.65)
        let oldSleep = previousMode == .sleep ? 1.0 : 0.0
        let newSleep = currentMode == .sleep ? 1.0 : 0.0
        let oldFocus = previousMode == .focus ? 1.0 : 0.0
        let newFocus = currentMode == .focus ? 1.0 : 0.0

        var spriteFrame: Int?
        if animated, let spriteStartedAt {
            let elapsed = now - spriteStartedAt
            if elapsed >= 0, elapsed < spriteDuration {
                spriteFrame = Int(floor(elapsed * 10)) % spriteFrameCount
            }
        }

        return MotionPose(
            tier: tier,
            hourTarget: target.hour,
            minuteTarget: target.minute,
            hourActual: normalizedDegrees(target.hour + hourOffset),
            minuteActual: normalizedDegrees(target.minute + minuteOffset),
            idleWeight: idleWeight,
            tapWeight: tapWeight,
            breath: animated ? sin(now * .pi * 0.72) : 0,
            blink: blink,
            sleepAmount: lerp(oldSleep, newSleep, transition),
            focusAmount: lerp(oldFocus, newFocus, transition),
            slump: lowBattery ? 1 : 0,
            chargingPulse: animated && charging ? (sin(now * .pi * 1.2) + 1) / 2 : 0,
            crown: clamp(crown),
            spriteFrame: spriteFrame
        )
    }

    static func verifyHandReturn() -> (passed: Bool, maximumError: Double) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let samples = [
            DateComponents(year: 2026, month: 9, day: 23, hour: 10, minute: 10, second: 30),
            DateComponents(year: 2026, month: 9, day: 23, hour: 3, minute: 15, second: 0),
            DateComponents(year: 2026, month: 9, day: 23, hour: 23, minute: 59, second: 59)
        ].compactMap { calendar.date(from: $0) }

        var maximumError = 0.0
        for date in samples {
            let now = date.timeIntervalSinceReferenceDate
            let pose = makePose(
                date: date,
                tier: .active,
                currentMode: .awake,
                previousMode: .awake,
                modeChangedAt: now - 1,
                crown: 0,
                lowBattery: false,
                charging: false,
                idleStartedAt: now - idleDuration,
                tapStartedAt: nil,
                blinkStartedAt: nil,
                spriteStartedAt: nil
            )
            maximumError = max(maximumError, pose.maximumHandError)
        }
        return (maximumError <= 1e-9, maximumError)
    }
}

struct MotionTimelineSchedule: TimelineSchedule {
    let lowPower: Bool

    func entries(
        from startDate: Date,
        mode: TimelineScheduleMode
    ) -> PeriodicTimelineSchedule.Entries {
        let interval: TimeInterval
        if mode == .lowFrequency {
            interval = 60
        } else {
            interval = lowPower ? 5 : 1.0 / 30.0
        }
        return PeriodicTimelineSchedule(from: startDate, by: interval)
            .entries(from: startDate, mode: mode)
    }
}

@MainActor
final class MotionController: ObservableObject {
    @Published var crown = 0.0
    @Published var mode: FaceMode = .awake
    @Published var previousMode: FaceMode = .awake
    @Published var lowBattery = false
    @Published var charging = false
    @Published var fixedClock = true
    @Published var lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
    @Published var verificationLabel = "TEST"

    private let appStartedAt = Date()
    private let fixedEpoch: Date
    private var powerObserver: NSObjectProtocol?

    private(set) var modeChangedAt = Date().timeIntervalSinceReferenceDate
    private(set) var idleStartedAt: TimeInterval?
    private(set) var tapStartedAt: TimeInterval?
    private(set) var blinkStartedAt: TimeInterval?
    private(set) var spriteStartedAt: TimeInterval?

    init() {
        var components = DateComponents()
        components.year = 2026
        components.month = 9
        components.day = 23
        components.hour = 10
        components.minute = 10
        components.second = 30
        fixedEpoch = Calendar.current.date(from: components) ?? Date()

        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        }
    }

    deinit {
        if let powerObserver {
            NotificationCenter.default.removeObserver(powerObserver)
        }
    }

    func renderDate(from timelineDate: Date) -> Date {
        guard fixedClock else { return timelineDate }
        return fixedEpoch.addingTimeInterval(timelineDate.timeIntervalSince(appStartedAt))
    }

    func cycleMode(at date: Date) {
        previousMode = mode
        switch mode {
        case .awake: mode = .focus
        case .focus: mode = .sleep
        case .sleep: mode = .awake
        }
        modeChangedAt = date.timeIntervalSinceReferenceDate
    }

    func cyclePowerState() {
        if !lowBattery && !charging {
            lowBattery = true
        } else if lowBattery {
            lowBattery = false
            charging = true
        } else {
            charging = false
        }
    }

    func triggerIdle(at date: Date) {
        idleStartedAt = date.timeIntervalSinceReferenceDate
    }

    func triggerTap(at date: Date) {
        tapStartedAt = date.timeIntervalSinceReferenceDate
        WKInterfaceDevice.current().play(.click)
    }

    func triggerBlink(at date: Date) {
        blinkStartedAt = date.timeIntervalSinceReferenceDate
    }

    func triggerSprite(at date: Date) {
        spriteStartedAt = date.timeIntervalSinceReferenceDate
    }

    func runVerification() {
        let result = MotionMath.verifyHandReturn()
        verificationLabel = result.passed ? "PASS 0°" : String(format: "FAIL %.6f°", result.maximumError)
        if result.passed {
            WKInterfaceDevice.current().play(.success)
        } else {
            WKInterfaceDevice.current().play(.failure)
        }
    }
}
