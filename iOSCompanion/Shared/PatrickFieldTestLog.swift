import Foundation

/// Debug-only field-test switch and on-screen log.
///
/// Off unless someone turns it on from the hidden gesture, the
/// `PATRICK_FIELD_TEST=1` environment, or the `-patrick-field-test` argument.
/// Nothing in the normal companion flow reads this.
enum PatrickFieldTestGate {
    static let storageKey = "patrick.fieldtest.enabled.v1"

    static func isEnabled(
        defaults: UserDefaults = PatrickFieldTestDefaults.suite,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        if environment["PATRICK_FIELD_TEST"] == "1" { return true }
        if arguments.contains("-patrick-field-test") { return true }
        return defaults.bool(forKey: storageKey)
    }

    static func setEnabled(
        _ enabled: Bool,
        defaults: UserDefaults = PatrickFieldTestDefaults.suite
    ) {
        defaults.set(enabled, forKey: storageKey)
    }
}

enum PatrickFieldTestDefaults {
    /// Same App Group string as the companion. Duplicated so the watch build
    /// does not have to compile the phone store.
    static let appGroupIdentifier = "group.com.chans.patrickface.shared"

    static var suite: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }
}

struct PatrickFieldTestLine: Codable, Equatable, Sendable {
    var at: Date
    var topic: String
    var message: String
}

/// Timestamped text log shared by the app, the widget extension, and (when
/// the App Group is actually provisioned) the optional notification extension.
enum PatrickFieldTestLog {
    static let storageKey = "patrick.fieldtest.log.v1"
    private static let lock = NSLock()
    private static let limit = 400

    @discardableResult
    static func append(
        _ message: String,
        topic: String,
        defaults: UserDefaults = PatrickFieldTestDefaults.suite,
        now: Date = Date()
    ) -> PatrickFieldTestLine {
        let line = PatrickFieldTestLine(at: now, topic: topic, message: message)
        lock.lock()
        defer { lock.unlock() }
        var lines = loadUnlocked(defaults)
        lines.append(line)
        if lines.count > limit {
            lines.removeFirst(lines.count - limit)
        }
        saveUnlocked(lines, defaults)
        return line
    }

    static func lines(
        defaults: UserDefaults = PatrickFieldTestDefaults.suite
    ) -> [PatrickFieldTestLine] {
        lock.lock()
        defer { lock.unlock() }
        return loadUnlocked(defaults)
    }

    static func exportText(
        defaults: UserDefaults = PatrickFieldTestDefaults.suite
    ) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return lines(defaults: defaults).map { line in
            "\(formatter.string(from: line.at))  [\(line.topic)]  \(line.message)"
        }.joined(separator: "\n")
    }

    static func clear(defaults: UserDefaults = PatrickFieldTestDefaults.suite) {
        lock.lock()
        defer { lock.unlock() }
        defaults.removeObject(forKey: storageKey)
    }

    private static func loadUnlocked(_ defaults: UserDefaults) -> [PatrickFieldTestLine] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PatrickFieldTestLine].self, from: data)) ?? []
    }

    private static func saveUnlocked(_ lines: [PatrickFieldTestLine], _ defaults: UserDefaults) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(lines) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

/// Send times for the rapid Live Activity test, including the opening 0.
/// A 30 second run at 1s / 2s / 5s yields sequences 0...30, 0...15, and 0...6.
enum PatrickFieldTestRapidPlan {
    static func sequences(interval: TimeInterval, duration: TimeInterval = 30) -> [Int] {
        guard interval > 0, duration >= 0 else { return [0] }
        let steps = Int((duration / interval).rounded(.down))
        return Array(0...steps)
    }
}

enum PatrickFieldTestToggleStore {
    static let storageKey = "patrick.fieldtest.toggle.v1"

    static func value(defaults: UserDefaults = PatrickFieldTestDefaults.suite) -> Bool {
        defaults.bool(forKey: storageKey)
    }

    static func set(_ value: Bool, defaults: UserDefaults = PatrickFieldTestDefaults.suite) {
        defaults.set(value, forKey: storageKey)
    }
}

struct PatrickFieldTestAlarmRecord: Codable, Equatable, Sendable {
    var id: String
    var scheduledAt: Date
    var fireAt: Date
    var lastState: String
    var sawAlerting: Bool

    static let storageKey = "patrick.fieldtest.alarm.v1"

    static func load(
        defaults: UserDefaults = PatrickFieldTestDefaults.suite
    ) -> PatrickFieldTestAlarmRecord? {
        guard let data = defaults.data(forKey: storageKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(PatrickFieldTestAlarmRecord.self, from: data)
    }

    func save(defaults: UserDefaults = PatrickFieldTestDefaults.suite) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(self) else { return }
        defaults.set(data, forKey: storageKey)
    }
}

enum PatrickFieldTestNotificationKind {
    /// Must match the notification extension's Info.plist category.
    static let categoryID = "patrick.fieldtest.animation"
}
