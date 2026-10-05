import Combine
import Foundation
import WatchConnectivity

enum WatchLinkState: Equatable {
    case unsupported
    case activating
    case noPairedWatch
    case watchAppMissing
    case reachable
    case backgroundDelivery
    case demo
    case failed(String)

    var title: String {
        switch self {
        case .unsupported: "Unavailable"
        case .activating: "Activating"
        case .noPairedWatch: "No paired watch"
        case .watchAppMissing: "Watch app not installed"
        case .reachable: "Watch reachable"
        case .backgroundDelivery: "Queued for delivery"
        case .demo: "Demo watch connected"
        case .failed: "Sync issue"
        }
    }

    var detail: String {
        switch self {
        case .unsupported:
            "WatchConnectivity is not available on this device."
        case .activating:
            "Establishing the official companion channel."
        case .noPairedWatch:
            "Pair an Apple Watch to enable device sync."
        case .watchAppMissing:
            "Install the Patrick watch app built as this app's companion."
        case .reachable:
            "Interactive commands can be delivered now."
        case .backgroundDelivery:
            "Durable state will arrive when watchOS next permits delivery."
        case .demo:
            "Commands are acknowledged locally without a watch."
        case let .failed(message):
            message
        }
    }
}

@MainActor
final class WatchSyncService: NSObject, ObservableObject {
    static let shared = WatchSyncService()

    @Published private(set) var linkState: WatchLinkState = .activating
    @Published private(set) var lastAcknowledgement: String?
    @Published private(set) var lastDeliveryAt: Date?
    @Published private(set) var lastEnvelopeID: UUID?

    var onSettingsReceived: ((PatrickSettings) -> Void)?
    var onTimerReceived: ((PatrickTimerSnapshot) -> Void)?
    var onCommandReceived: ((PatrickCommandPayload) -> Void)?

    private let store: PatrickSharedStore
    private var session: WCSession?
    private var demoMode = false
    private var pendingDeliveries: [(PatrickMessageEnvelope, PatrickMessageEnvelope?)] = []

    init(store: PatrickSharedStore = .shared) {
        self.store = store
        super.init()
        activateIfSupported()
    }

    func setDemoMode(_ enabled: Bool) {
        demoMode = enabled
        if enabled {
            linkState = .demo
        } else {
            activateIfSupported()
            refreshLinkState()
        }
    }

    func send(
        command: PatrickCommandPayload,
        settings: PatrickSettings? = nil
    ) {
        let envelope = PatrickMessageEnvelope.command(command, settings: settings)
        deliver(envelope, updateContextWith: settings.map {
            PatrickMessageEnvelope.snapshot(settings: $0, timer: command.timer)
        })
    }

    func syncSnapshot(
        settings: PatrickSettings,
        timer: PatrickTimerSnapshot? = nil
    ) {
        let envelope = PatrickMessageEnvelope.snapshot(
            settings: settings,
            timer: timer
        )
        deliver(envelope, updateContextWith: envelope)
    }

    private func activateIfSupported() {
        guard WCSession.isSupported() else {
            session = nil
            if !demoMode { linkState = .unsupported }
            return
        }

        let session = WCSession.default
        self.session = session
        session.delegate = self
        if session.activationState != .activated {
            linkState = .activating
            session.activate()
        } else {
            refreshLinkState()
        }
    }

    private func deliver(
        _ envelope: PatrickMessageEnvelope,
        updateContextWith contextEnvelope: PatrickMessageEnvelope?
    ) {
        lastEnvelopeID = envelope.id

        if demoMode {
            linkState = .demo
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(350))
                self?.lastDeliveryAt = .now
                self?.lastAcknowledgement = "Mock watch accepted \(envelope.id.uuidString.prefix(8))."
            }
            return
        }

        guard let session else {
            linkState = .unsupported
            return
        }

        guard session.activationState == .activated else {
            pendingDeliveries.append((envelope, contextEnvelope))
            pendingDeliveries = Array(pendingDeliveries.suffix(20))
            linkState = .activating
            return
        }

        if let contextEnvelope {
            do {
                try session.updateApplicationContext([
                    PatrickMessageEnvelope.transportKey: try contextEnvelope.encoded(),
                ])
            } catch {
                lastAcknowledgement = "Latest-state context failed: \(error.localizedDescription)"
            }
        }

        do {
            let data = try envelope.encoded()
            if session.isReachable {
                session.sendMessageData(
                    data,
                    replyHandler: { [weak self] reply in
                        Task { @MainActor in
                            self?.handleReplyData(reply)
                        }
                    },
                    errorHandler: { [weak self] error in
                        Task { @MainActor in
                            self?.queueBackground(data, after: error)
                        }
                    }
                )
                linkState = .reachable
            } else {
                session.transferUserInfo([
                    PatrickMessageEnvelope.transportKey: data,
                ])
                linkState = .backgroundDelivery
            }
        } catch {
            linkState = .failed(error.localizedDescription)
        }
    }

    private func queueBackground(_ data: Data, after error: Error) {
        guard let session else {
            linkState = .failed(error.localizedDescription)
            return
        }
        session.transferUserInfo([PatrickMessageEnvelope.transportKey: data])
        linkState = .backgroundDelivery
        lastAcknowledgement = "Interactive delivery failed; command queued."
    }

    private func receive(_ data: Data) -> Data? {
        do {
            let envelope = try PatrickMessageEnvelope.decode(data)
            if envelope.kind == .acknowledgement {
                lastDeliveryAt = .now
                if let acknowledgement = envelope.acknowledgement {
                    lastAcknowledgement = acknowledgement.detail
                } else {
                    lastAcknowledgement = "Watch sent an empty acknowledgement."
                }
                return nil
            }

            guard store.markMessageProcessed(envelope.id) else {
                return try? PatrickMessageEnvelope.acknowledgement(
                    for: envelope.id,
                    accepted: true,
                    detail: "Duplicate already applied"
                ).encoded()
            }

            lastDeliveryAt = .now
            if let settings = envelope.settings {
                // The model merges by revision/experience timestamp before persisting.
                if let onSettingsReceived { onSettingsReceived(settings) }
                else {
                    var merged = store.loadSettings()
                    let localExperience = store.loadExperience()
                    if settings.revision >= merged.revision { merged = settings }
                    merged.experience = settings.experience.flatMap { $0.isNewer(than: localExperience) ? $0 : nil } ?? localExperience
                    store.saveSettings(merged)
                    if let experience = merged.experience { store.saveExperience(experience) }
                }
            }
            if let timer = envelope.timer {
                let effective = PatrickTimerSnapshot.resolving(timer, experience: store.loadExperience())
                store.saveTimer(effective)
                onTimerReceived?(effective)
            }
            if let command = envelope.command {
                var current = command
                let expired = abs(envelope.sentAt.timeIntervalSinceNow) > 120
                if expired {
                    current.careAction = nil
                }
                if !(expired && (command.name == .playThemeSound || command.name == .openWatchFace)) { onCommandReceived?(current) }
            }

            return try? PatrickMessageEnvelope.acknowledgement(
                for: envelope.id,
                accepted: true,
                detail: "Applied on iPhone"
            ).encoded()
        } catch {
            linkState = .failed(error.localizedDescription)
            return nil
        }
    }

    private func sendAcknowledgement(_ data: Data) {
        guard let session else { return }
        if session.isReachable {
            session.sendMessageData(
                data,
                replyHandler: nil,
                errorHandler: { [weak self] _ in
                    Task { @MainActor in
                        self?.session?.transferUserInfo([
                            PatrickMessageEnvelope.transportKey: data,
                        ])
                    }
                }
            )
        } else {
            session.transferUserInfo([
                PatrickMessageEnvelope.transportKey: data,
            ])
        }
    }

    private func handleReplyData(_ data: Data) {
        guard let reply = try? PatrickMessageEnvelope.decode(data) else {
            lastAcknowledgement = "Watch replied with an invalid envelope."
            return
        }
        lastDeliveryAt = .now
        if let acknowledgement = reply.acknowledgement {
            lastAcknowledgement = acknowledgement.detail
        } else {
            lastAcknowledgement = "Watch replied without an acknowledgement."
        }
        refreshLinkState()
    }

    private func refreshLinkState() {
        guard !demoMode else {
            linkState = .demo
            return
        }
        guard let session, session.activationState == .activated else {
            linkState = .activating
            return
        }
        guard session.isPaired else {
            linkState = .noPairedWatch
            return
        }
        guard session.isWatchAppInstalled else {
            linkState = .watchAppMissing
            return
        }
        linkState = session.isReachable ? .reachable : .backgroundDelivery
    }
}

extension WatchSyncService: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            if let error {
                self?.linkState = .failed(error.localizedDescription)
            } else {
                self?.refreshLinkState()
                if activationState == .activated, let self {
                    let pending = self.pendingDeliveries; self.pendingDeliveries = []
                    for (envelope, context) in pending { self.deliver(envelope, updateContextWith: context) }
                }
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.linkState = .activating
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshLinkState()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.refreshLinkState()
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
        guard let data = userInfo[PatrickMessageEnvelope.transportKey] as? Data else {
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
            let data = applicationContext[PatrickMessageEnvelope.transportKey] as? Data
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
