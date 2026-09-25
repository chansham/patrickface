import Foundation

enum PatrickAppGroup {
    static let identifier = "group.com.chans.patrickface.shared"
    static let settingsKey = "patrick.settings.v1"
    static let timerKey = "patrick.timer.v1"
    static let pendingActionsKey = "patrick.pending-actions.v1"
    static let processedMessageIDsKey = "patrick.processed-message-ids.v1"
}

struct PendingPatrickAction: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Hashable, Sendable {
        case playThemeSound
        case openWatchFace
    }

    var id: UUID
    var kind: Kind
    var createdAt: Date
}

/// Stores only user-selected presentation state. No account, analytics, location,
/// contacts, health data, or cloud identifier is collected.
final class PatrickSharedStore: @unchecked Sendable {
    static let shared = PatrickSharedStore()

    private let defaults: UserDefaults
    private let lock = NSLock()
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(defaults: UserDefaults? = nil) {
        self.defaults = defaults
            ?? UserDefaults(suiteName: PatrickAppGroup.identifier)
            ?? .standard

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func loadSettings() -> PatrickSettings {
        lock.withLock {
            guard
                let data = defaults.data(forKey: PatrickAppGroup.settingsKey),
                let value = try? decoder.decode(PatrickSettings.self, from: data),
                value.version <= PatrickSettings.schemaVersion
            else {
                return .defaults
            }
            return value
        }
    }

    @discardableResult
    func updateSettings(
        _ mutation: (inout PatrickSettings) -> Void
    ) -> PatrickSettings {
        lock.withLock {
            var value: PatrickSettings
            if
                let data = defaults.data(forKey: PatrickAppGroup.settingsKey),
                let decoded = try? decoder.decode(PatrickSettings.self, from: data),
                decoded.version <= PatrickSettings.schemaVersion
            {
                value = decoded
            } else {
                value = .defaults
            }

            mutation(&value)
            value = value.nextRevision()
            if let data = try? encoder.encode(value) {
                defaults.set(data, forKey: PatrickAppGroup.settingsKey)
            }
            return value
        }
    }

    func saveSettings(_ settings: PatrickSettings) {
        lock.withLock {
            guard let data = try? encoder.encode(settings) else { return }
            defaults.set(data, forKey: PatrickAppGroup.settingsKey)
        }
    }

    func loadTimer() -> PatrickTimerSnapshot {
        lock.withLock {
            guard
                let data = defaults.data(forKey: PatrickAppGroup.timerKey),
                let value = try? decoder.decode(PatrickTimerSnapshot.self, from: data)
            else {
                return .inactive
            }
            return value
        }
    }

    func saveTimer(_ timer: PatrickTimerSnapshot) {
        lock.withLock {
            guard let data = try? encoder.encode(timer) else { return }
            defaults.set(data, forKey: PatrickAppGroup.timerKey)
        }
    }

    func enqueue(_ kind: PendingPatrickAction.Kind) {
        lock.withLock {
            var actions = decode(
                [PendingPatrickAction].self,
                forKey: PatrickAppGroup.pendingActionsKey
            ) ?? []
            actions.append(PendingPatrickAction(id: UUID(), kind: kind, createdAt: .now))
            actions = Array(actions.suffix(20))
            encode(actions, forKey: PatrickAppGroup.pendingActionsKey)
        }
        NotificationCenter.default.post(name: .patrickPendingActionsChanged, object: nil)
    }

    func consumePendingActions() -> [PendingPatrickAction] {
        lock.withLock {
            let actions = decode(
                [PendingPatrickAction].self,
                forKey: PatrickAppGroup.pendingActionsKey
            ) ?? []
            defaults.removeObject(forKey: PatrickAppGroup.pendingActionsKey)
            return actions
        }
    }

    /// Returns false for duplicate WatchConnectivity delivery.
    func markMessageProcessed(_ id: UUID) -> Bool {
        lock.withLock {
            var ids = defaults.stringArray(
                forKey: PatrickAppGroup.processedMessageIDsKey
            ) ?? []
            let value = id.uuidString
            guard !ids.contains(value) else { return false }
            ids.append(value)
            defaults.set(Array(ids.suffix(100)), forKey: PatrickAppGroup.processedMessageIDsKey)
            return true
        }
    }

    func resetLocalData() {
        lock.withLock {
            [
                PatrickAppGroup.settingsKey,
                PatrickAppGroup.timerKey,
                PatrickAppGroup.pendingActionsKey,
                PatrickAppGroup.processedMessageIDsKey,
            ].forEach { key in
                defaults.removeObject(forKey: key)
            }
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? encoder.encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

extension Notification.Name {
    static let patrickPendingActionsChanged = Notification.Name(
        "com.chans.patrickface.pending-actions-changed"
    )
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
