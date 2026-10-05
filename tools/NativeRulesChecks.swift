import Foundation

/// Native behavior tests, runnable without SwiftUI or the watchOS SDK:
/// swiftc PatrickFace/PatrickShared.swift tools/NativeRulesChecks.swift -o /tmp/patrick-native-checks
/// /tmp/patrick-native-checks
@main
struct NativeRulesChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        var checks = 0
        for minute in 0..<1440 {
            let date = calendar.date(from: DateComponents(
                year: 2026, month: 9, day: 27, hour: minute / 60, minute: minute % 60
            ))!
            require(
                PatrickPetRules.isNight(date, calendar: calendar) == (minute < 330 || minute >= 1320),
                "Night schedule boundary failed at minute \(minute)"
            )
            checks += 1
        }

        let phoneModes: [Bool?] = [nil, false, true]
        for scene in PatrickPetScene.allCases {
            for night in [false, true] {
                for phone in phoneModes {
                    for preview in [false, true] {
                        let expected: Bool
                        switch scene {
                        case .sleeping: expected = true
                        case .resting, .exercise: expected = false
                        case .automatic: expected = preview || (phone ?? night)
                        }
                        require(PatrickPetRules.isSleeping(
                            scene: scene, automaticNight: night,
                            companionSleep: phone, companionPreviewSleeping: preview
                        ) == expected, "Scene/phone precedence failed")
                        checks += 1
                    }
                }
            }
        }

        let samples: [(Int, Int, Double, Double)] = [
            (0, 0, 0, 0), (3, 45, 112.5, 270), (6, 30, 195, 180),
            (10, 10, 305, 60), (11, 55, 357.5, 330), (12, 0, 0, 0),
        ]
        for (hour, minute, expectedHour, expectedMinute) in samples {
            let date = calendar.date(from: DateComponents(
                year: 2026, month: 9, day: 27, hour: hour, minute: minute
            ))!
            let angles = PatrickClockAngles.make(for: date, calendar: calendar)
            require(abs(angles.hour - expectedHour) < 0.0001, "Incorrect hour hand")
            require(abs(angles.minute - expectedMinute) < 0.0001, "Incorrect minute hand")
            checks += 2
        }
        require(PatrickClockLayout.hourLength < PatrickClockLayout.minuteLength, "Hand lengths reversed")
        require(PatrickDeepLink.parse(URL(string: "patrickface://face?theme=cel")!)?.theme == .cel,
                "Existing deep link changed")
        require(PatrickDeepLink.parse(URL(string: "patrickface://face?theme=unknown")!) == nil,
                "Unknown theme accepted")
        print("PASS: \(checks + 3) native rule checks (Foundation only).")
    }
}
