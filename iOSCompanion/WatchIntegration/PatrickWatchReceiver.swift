#if os(watchOS)
import Combine
import Foundation
import WatchConnectivity
import WatchKit

/// Watch-native endpoint for protocol v1. The DTOs are intentionally namespaced
/// in `PatrickWatchWire`, so the iPhone's `PatrickModels.swift` must not be
/// compiled into the watch target.
@MainActor
final class PatrickWatchReceiver: NSObject, ObservableObject {
    struct AppliedState: Sendable {
        var theme: PatrickTheme?
        var sleepMode: PatrickWatchWire.SleepMode?
        var previewState: PatrickWatchWire.VisualState?
        var experience: PatrickExperienceState?
        var careAction: PatrickCareAction?
        var playSound = false
    }

    static let shared = PatrickWatchReceiver()

    @Published private(set) var lastAcknowledgement: String?
    @Published private(set) var requestedRoute: URL?

    private let session = WCSession.default
    private let defaults: UserDefaults
    private var latestSettings: PatrickWatchWire.Settings?
    @Published private(set) var latestTimer: PatrickWatchWire.TimerSnapshot?
    private var pendingEnvelope: PatrickWatchWire.Envelope?
    private var currentTheme: (() -> PatrickTheme)?
    private var onControlApplied: ((AppliedState) -> Void)?
    private var onOpenFace: (() -> Void)?

    private static let processedIDsKey =
        "patrick.connectivity.processed-message-ids.v1"
    private static let settingsKey = "patrick.connectivity.settings.v1"
    private static let timerKey = "patrick.connectivity.timer.v1"

    private var processedIDs: [String] {
        get { defaults.stringArray(forKey: Self.processedIDsKey) ?? [] }
        set { defaults.set(Array(newValue.suffix(100)), forKey: Self.processedIDsKey) }
    }

    override private init() {
        let defaults = PatrickSharedStore.defaults
        self.defaults = defaults
        latestSettings = Self.decodeStored(
            PatrickWatchWire.Settings.self,
            data: defaults.data(forKey: Self.settingsKey)
        )
        latestTimer = Self.decodeStored(
            PatrickWatchWire.TimerSnapshot.self,
            data: defaults.data(forKey: Self.timerKey)
        )
        super.init()
    }

    func activate(
        currentTheme: @escaping () -> PatrickTheme,
        onControlApplied: @escaping (AppliedState) -> Void,
        onOpenFace: @escaping () -> Void
    ) {
        self.currentTheme = currentTheme
        self.onControlApplied = onControlApplied
        self.onOpenFace = onOpenFace

        if let settings = latestSettings {
            onControlApplied(
                AppliedState(
                    theme: settings.theme.watchTheme,
                    sleepMode: settings.sleepMode,
                    previewState: settings.previewState,
                    experience: settings.experience
                )
            )
        }

        guard WCSession.isSupported() else {
            lastAcknowledgement = "WatchConnectivity is unavailable."
            return
        }
        session.delegate = self
        session.activate()
    }

    func sendSnapshot(theme: PatrickTheme, experience: PatrickExperienceState? = nil) {
        var settings = latestSettings
            ?? PatrickWatchWire.Settings.initial(theme: theme)
        let wireTheme = PatrickWatchWire.Theme(theme)
        if settings.theme != wireTheme {
            settings.theme = wireTheme
            settings.revision &+= 1
            settings.updatedAt = .now
        }
        settings.version = PatrickWatchWire.settingsSchemaVersion
        if let experience, settings.experience != experience {
            settings.experience = experience
            settings.revision &+= 1
            settings.updatedAt = .now
        }
        settings.demoMode = false
        latestSettings = settings
        persist(settings)

        let envelope = PatrickWatchWire.Envelope.snapshot(
            settings: settings,
            timer: settings.experience?.activity == nil ? latestTimer : nil
        )
        deliver(envelope)
    }

    private func publishCurrentSnapshot() {
        guard let theme = currentTheme?() else { return }
        sendSnapshot(theme: theme)
    }

    private func deliver(_ envelope: PatrickWatchWire.Envelope) {
        guard session.activationState == .activated else {
            pendingEnvelope = envelope
            return
        }

        do {
            let data = try envelope.encoded()
            do {
                try session.updateApplicationContext([
                    PatrickWatchWire.transportKey: data,
                ])
            } catch {
                lastAcknowledgement = "Latest-state context failed: \(error.localizedDescription)"
            }
            if session.isReachable {
                session.sendMessageData(
                    data,
                    replyHandler: { [weak self] data in
                        Task { @MainActor in
                            self?.acceptReply(data)
                        }
                    },
                    errorHandler: { [weak self] error in
                        Task { @MainActor in
                            self?.queue(data, after: error)
                        }
                    }
                )
            } else {
                queue(data)
            }
        } catch {
            lastAcknowledgement = error.localizedDescription
        }
    }

    private func queue(_ data: Data, after error: Error? = nil) {
        session.transferUserInfo([PatrickWatchWire.transportKey: data])
        lastAcknowledgement = error.map {
            "Interactive delivery failed; snapshot queued: \($0.localizedDescription)"
        } ?? "Snapshot queued for iPhone delivery."
    }

    private func acceptReply(_ data: Data) {
        guard
            let envelope = try? PatrickWatchWire.Envelope.decode(data),
            let acknowledgement = envelope.acknowledgement
        else {
            lastAcknowledgement = "iPhone returned an invalid acknowledgement."
            return
        }
        lastAcknowledgement = acknowledgement.detail
    }

    private func receive(_ data: Data) -> Data? {
        do {
            let envelope = try PatrickWatchWire.Envelope.decode(data)

            if envelope.kind == .acknowledgement {
                guard let acknowledgement = envelope.acknowledgement else {
                    lastAcknowledgement = "iPhone sent an empty acknowledgement."
                    return nil
                }
                lastAcknowledgement = acknowledgement.detail
                return nil
            }

            guard !processedIDs.contains(envelope.id.uuidString) else {
                return try PatrickWatchWire.Envelope.acknowledgement(
                    for: envelope.id,
                    accepted: true,
                    detail: "Duplicate already applied on watch"
                ).encoded()
            }

            var effectiveSettings = latestSettings
                ?? PatrickWatchWire.Settings.initial(
                    theme: currentTheme?() ?? .cel
                )
            var update = AppliedState()
            var staleState = false

            if let settings = envelope.settings {
                let localExperience = effectiveSettings.experience ?? PatrickExperienceState.load(from: defaults)
                if settings.revision >= effectiveSettings.revision {
                    effectiveSettings = settings
                    update.theme = settings.theme.watchTheme
                    update.sleepMode = settings.sleepMode
                    update.previewState = settings.previewState
                } else {
                    staleState = true
                }
                if let incoming = settings.experience, incoming.isNewer(than: localExperience) {
                    effectiveSettings.experience = incoming; update.experience = incoming
                } else { effectiveSettings.experience = localExperience }
            }

            if let timer = envelope.timer {
                setTimer(timer)
            }

            if let command = envelope.command {
                apply(
                    command,
                    to: &effectiveSettings,
                    stateAllowed: !staleState || update.experience != nil,
                    actionAllowed: abs(envelope.sentAt.timeIntervalSinceNow) <= 120,
                    update: &update
                )
            }

            if update.theme != nil
                || update.sleepMode != nil
                || update.previewState != nil
                || update.experience != nil || update.careAction != nil || update.playSound
            {
                latestSettings = effectiveSettings
                persist(effectiveSettings)
                defaults.set(
                    effectiveSettings.sleepMode.rawValue,
                    forKey: "patrickSleepMode"
                )
                defaults.set(
                    effectiveSettings.previewState.rawValue,
                    forKey: "patrickPreviewState"
                )
                defaults.set(
                    effectiveSettings.revision,
                    forKey: "patrickSettingsRevision"
                )
                onControlApplied?(update)
            }

            var ids = processedIDs
            ids.append(envelope.id.uuidString)
            processedIDs = ids

            return try PatrickWatchWire.Envelope.acknowledgement(
                for: envelope.id,
                accepted: true,
                detail: staleState
                    ? "Ignored stale state on Apple Watch"
                    : "Applied on Apple Watch"
            ).encoded()
        } catch {
            lastAcknowledgement = error.localizedDescription
            return nil
        }
    }

    private func apply(
        _ command: PatrickWatchWire.Command,
        to settings: inout PatrickWatchWire.Settings,
        stateAllowed: Bool,
        actionAllowed: Bool,
        update: inout AppliedState
    ) {
        switch command.name {
        case .setTheme:
            if stateAllowed, let theme = command.theme {
                settings.theme = theme
                update.theme = theme.watchTheme
            }
        case .setSleepMode:
            if stateAllowed, let mode = command.sleepMode {
                settings.sleepMode = mode
                update.sleepMode = mode
            }
        case .setPreviewState:
            if stateAllowed, let state = command.previewState {
                settings.previewState = state
                update.previewState = state
            }
        case .playThemeSound:
            update.playSound = actionAllowed
        case .openWatchFace:
            guard actionAllowed else { return }
            requestedRoute = command.deepLink
            onOpenFace?()
            NotificationCenter.default.post(
                name: .patrickWatchRouteRequested,
                object: requestedRoute
            )
        case .startTimer:
            if let timer = command.timer {
                setTimer(timer)
            }
        case .stopTimer:
            setTimer(command.timer)
        case .updateExperience:
            if stateAllowed && actionAllowed { update.careAction = command.careAction }
        }
    }

    private func setTimer(_ timer: PatrickWatchWire.TimerSnapshot?) {
        latestTimer = timer
        if let timer {
            defaults.set(Self.encodeStored(timer), forKey: Self.timerKey)
        } else {
            defaults.removeObject(forKey: Self.timerKey)
        }
    }

    private func persist(_ settings: PatrickWatchWire.Settings) {
        defaults.set(Self.encodeStored(settings), forKey: Self.settingsKey)
    }

    private static func encodeStored<T: Encodable>(_ value: T) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(value)
    }

    private static func decodeStored<T: Decodable>(
        _ type: T.Type,
        data: Data?
    ) -> T? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func sendAcknowledgement(_ data: Data) {
        if session.isReachable {
            session.sendMessageData(
                data,
                replyHandler: nil,
                errorHandler: { [weak self] _ in
                    Task { @MainActor in
                        self?.session.transferUserInfo([
                            PatrickWatchWire.transportKey: data,
                        ])
                    }
                }
            )
        } else {
            session.transferUserInfo([PatrickWatchWire.transportKey: data])
        }
    }
}

extension PatrickWatchReceiver: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if let error {
                lastAcknowledgement = error.localizedDescription
                return
            }
            guard activationState == .activated else { return }

            if let data = session.receivedApplicationContext[
                PatrickWatchWire.transportKey
            ] as? Data,
               let acknowledgement = receive(data)
            {
                sendAcknowledgement(acknowledgement)
            }

            if let pendingEnvelope {
                self.pendingEnvelope = nil
                deliver(pendingEnvelope)
            } else {
                publishCurrentSnapshot()
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        Task { @MainActor [weak self] in
            if let reply = self?.receive(messageData) {
                replyHandler(reply)
            }
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data
    ) {
        Task { @MainActor [weak self] in
            guard
                let self,
                let acknowledgement = receive(messageData)
            else {
                return
            }
            sendAcknowledgement(acknowledgement)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        guard let data = userInfo[PatrickWatchWire.transportKey] as? Data else {
            return
        }
        Task { @MainActor [weak self] in
            guard
                let self,
                let acknowledgement = receive(data)
            else {
                return
            }
            sendAcknowledgement(acknowledgement)
        }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        guard
            let data = applicationContext[PatrickWatchWire.transportKey] as? Data
        else {
            return
        }
        Task { @MainActor [weak self] in
            guard
                let self,
                let acknowledgement = receive(data)
            else {
                return
            }
            sendAcknowledgement(acknowledgement)
        }
    }
}

extension Notification.Name {
    static let patrickWatchRouteRequested = Notification.Name(
        "com.chans.patrickface.companion.watchkitapp.route-requested"
    )
}
#endif
