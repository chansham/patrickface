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
    @Published private(set) var lastWatchStatus: PatrickWatchStatusReceipt?
    @Published private(set) var watchStatusIssue: String?

    var onSettingsReceived: ((PatrickSettings) -> Void)?
    var onTimerReceived: ((PatrickTimerSnapshot) -> Void)?
    var onCommandReceived: ((PatrickCommandPayload) -> Void)?

    private let store: PatrickSharedStore
    private let watchStatusStore: PatrickWatchStatusStore
    private let watchContextReplayGate = PatrickWatchContextReplayGate()
    private var session: WCSession?
    private var demoMode = false
    private var pendingDeliveries: [(PatrickMessageEnvelope, PatrickMessageEnvelope?)] = []

    init(store: PatrickSharedStore = .shared, watchStatusStore: PatrickWatchStatusStore = PatrickWatchStatusStore()) {
        self.store = store
        self.watchStatusStore = watchStatusStore
        self.lastWatchStatus = watchStatusStore.receipt
        super.init()
        activateIfSupported()
    }

    /// Phone schedules only when the watch is unpaired, unworn, or its heartbeat is stale.
    func alertOwner(at date: Date = .now) -> PatrickAlertDevice {
        let paired = self.session?.activationState == .activated && self.session?.isPaired == true && self.session?.isWatchAppInstalled == true
        let observation = lastWatchStatus?.observation
        let worn = PatrickAlertOwner.isWorn(onWrist: observation?.onWrist, observedAt: observation?.observedAt, at: date, paired: paired)
        return PatrickAlertOwner.choose(paired: paired, worn: worn)
    }

    func clearWatchStatus() {
        watchStatusStore.reset()
        watchContextReplayGate.reset()
        lastWatchStatus = nil
        watchStatusIssue = nil
    }

    private func receiveWatchStatus(_ data: Data) {
        guard !demoMode, let session, session.activationState == .activated, session.isPaired else { return }
        guard let observation = try? PatrickWatchStatusObservation.decode(data) else {
            watchStatusIssue = "手錶狀態資料無法讀取；保留最後一次有效觀測。"
            return
        }
        switch watchStatusStore.accept(observation) {
        case .accepted:
            lastWatchStatus = watchStatusStore.receipt
            watchStatusIssue = nil
            NotificationCenter.default.post(name: .patrickWatchWornChanged, object: nil)
        case .duplicate, .older, .beforeReset:
            break // A late delivery cannot refresh the displayed observation age.
        case .invalid:
            watchStatusIssue = "手錶狀態資料無效；保留最後一次有效觀測。"
        case .clockAhead:
            watchStatusIssue = "手錶觀測時間比手機超前；請檢查兩台裝置的時間。"
        }
    }

    func setDemoMode(_ enabled: Bool) {
        demoMode = enabled
        if enabled {
            linkState = .demo
        } else {
            activateIfSupported()
            refreshLinkState()
            if let data = session?.receivedApplicationContext[PatrickMessageEnvelope.watchStatusTransportKey] as? Data {
                receiveWatchStatus(data)
            }
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
                let local = store.loadSettings()
                let merge = PatrickSettingsMerge.resolve(localExperience: store.loadExperience(), incomingExperience: settings.experience,
                    localRevision: local.revision, incomingRevision: settings.revision,
                    localSleepMode: local.sleepMode.rawValue, incomingSleepMode: settings.sleepMode.rawValue)
                var merged = merge.acceptsLegacySettings ? settings : local
                merged.experience = merge.experience
                merged.sleepMode = PatrickSleepMode(rawValue: merge.sleepModeRawValue) ?? .automatic
                // Pass the resolved pair to the model; an older outer mode
                // must not disagree with the winning modern scene.
                if let onSettingsReceived { onSettingsReceived(merged) }
                else {
                    store.saveSettings(merged)
                    if let experience = merged.experience { store.saveExperience(experience) }
                }
            }
            if let timer = envelope.timer {
                let effective = PatrickTimerSnapshot.resolving(timer, experience: store.loadExperience())
                store.saveTimer(effective)
                onTimerReceived?(effective)
            }
            if let command = envelope.command,
               !(command.name == .setSleepMode && envelope.settings?.experience != nil) {
                var current = command
                let expired = abs(envelope.sentAt.timeIntervalSinceNow) > 120
                if expired {
                    current.careAction = nil
                }
                let staleSound = command.name == .playThemeSound && !PatrickImmediateSoundPolicy.isFresh(envelope.sentAt)
                if !staleSound && !(expired && (command.name == .playThemeSound || command.name == .openWatchFace)) { onCommandReceived?(current) }
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
            clearWatchStatus()
            linkState = .noPairedWatch
            return
        }
        guard session.isWatchAppInstalled else {
            linkState = .watchAppMissing
            return
        }
        linkState = session.isReachable ? .reachable : .backgroundDelivery
    }

    /// Field-test ping. Older watches ignore the extra key. Theme and timer stay put.
    func sendFieldTestPing() {
        guard !demoMode else {
            PatrickFieldTestLog.append("示范模式没有真手表，没有发送。角色和计时都没动。", topic: "手表")
            return
        }
        guard let session, session.activationState == .activated else {
            PatrickFieldTestLog.append("手表会话还没准备好，没有发送。", topic: "手表")
            return
        }
        guard session.isReachable else {
            PatrickFieldTestLog.append("手表现在连不上。没有改角色、主题或计时。", topic: "手表")
            return
        }
        let body = PatrickFieldTestPing.Body(
            id: UUID(),
            sentAt: Date(),
            role: "phone",
            system: "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)",
            note: "问候"
        )
        guard let data = PatrickFieldTestPing.encode(body) else {
            PatrickFieldTestLog.append("问候没有编出来。", topic: "手表")
            return
        }
        session.sendMessage(
            [PatrickFieldTestPing.transportKey: data],
            replyHandler: { reply in
                let text: String
                if let replyData = reply[PatrickFieldTestPing.transportKey] as? Data,
                   let decoded = PatrickFieldTestPing.decode(replyData) {
                    text = "手表回了。\(decoded.system)。\(decoded.note)"
                } else {
                    text = "手表有回应，但内容读不出来。"
                }
                PatrickFieldTestLog.append(text, topic: "手表")
            },
            errorHandler: { error in
                PatrickFieldTestLog.append(
                    "问候失败。\(error.localizedDescription)。没有改角色。",
                    topic: "手表"
                )
            }
        )
        PatrickFieldTestLog.append("已向手表发出问候，等回应。", topic: "手表")
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
                    if let data = session.receivedApplicationContext[PatrickMessageEnvelope.watchStatusTransportKey] as? Data {
                        self.receiveWatchStatus(data)
                    }
                    let pending = self.pendingDeliveries; self.pendingDeliveries = []
                    for (envelope, context) in pending { self.deliver(envelope, updateContextWith: context) }
                }
            }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor [weak self] in
            // A watch switch must not display the previous watch's charge.
            self?.clearWatchStatus()
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
        didReceiveMessage message: [String: Any]
    ) {
        guard let data = message[PatrickMessageEnvelope.watchStatusTransportKey] as? Data else { return }
        Task { @MainActor [weak self] in self?.receiveWatchStatus(data) }
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
        if let data = applicationContext[PatrickMessageEnvelope.watchStatusTransportKey] as? Data {
            Task { @MainActor [weak self] in self?.receiveWatchStatus(data) }
        }
        guard
            let data = applicationContext[PatrickMessageEnvelope.transportKey] as? Data
        else {
            return
        }
        Task { @MainActor [weak self] in
            guard
                let self,
                !watchContextReplayGate.alreadyApplied(data),
                let acknowledgement = receive(data)
            else {
                return
            }
            watchContextReplayGate.rememberApplied(data)
            // Status heartbeats preserve the last settings envelope. A
            // repeated context must not create another queued ACK while the
            // watch is unreachable. Commands have their own durable channel.
            if session.isReachable {
                session.sendMessageData(acknowledgement, replyHandler: nil, errorHandler: nil)
            }
        }
    }
}
