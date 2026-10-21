import AVFoundation
import Foundation
import SoundAnalysis

extension Notification.Name {
    static let patrickSoundCue = Notification.Name("patrickSoundCue")
}

/// A few seconds of the microphone while the app is in front. The analyzer does
/// not keep this observer alive, so the process holds `shared`. Not `@MainActor`:
/// `SNResultsObserving` is called off the main actor.
final class PatrickSoundListener: NSObject, SNResultsObserving {
    static let shared = PatrickSoundListener()

    private var engine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private var request: SNRequest?
    private var window: Task<Void, Never>?
    private var listening = false
    private var starting = false
    private var tapped = false
    private var sessionActive = false
    private var denied = false
    private var generation = 0
    private var lastListenAt: Date?
    private var blockedUntil: Date?
    private var delivered = false
    private let deliveryLock = NSLock()

    /// `foreground == false` stops immediately. A cooldown only refuses a new
    /// window; it does not cut one that is already running.
    func setForeground(_ foreground: Bool, enabled: Bool) {
        DispatchQueue.main.async {
            guard foreground, enabled else {
                if self.listening || self.starting || self.sessionActive {
                    self.generation += 1
                    self.stop()
                }
                return
            }
            self.startIfIdle()
        }
    }

    private func startIfIdle() {
        guard !listening, !starting, !denied else { return }
        let now = Date()
        if let blockedUntil, now < blockedUntil { return }
        guard PatrickSoundTheater.mayListen(enabled: true, foreground: true, lastAt: lastListenAt, now: now) else { return }
        starting = true
        generation += 1
        let token = generation
        Task {
            let allowed = await AVAudioApplication.requestRecordPermission()
            DispatchQueue.main.async {
                guard token == self.generation else { return }
                guard allowed else {
                    self.denied = true
                    self.starting = false
                    return
                }
                self.install(now: now, token: token)
            }
        }
    }

    private func install(now: Date, token: Int) {
        guard token == generation else {
            starting = false
            return
        }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.record, mode: .default, options: [])
            try session.setActive(true)
            sessionActive = true
        } catch {
            starting = false
            blockedUntil = Date().addingTimeInterval(30)
            return
        }
        let engine = AVAudioEngine()
        self.engine = engine
        let format = engine.inputNode.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            self.engine = nil
            starting = false
            blockedUntil = Date().addingTimeInterval(60)
            deactivate()
            return
        }
        let stream = SNAudioStreamAnalyzer(format: format)
        do {
            let created = try SNClassifySoundRequest(classifierIdentifier: .version1)
            try stream.add(created, withObserver: self)
            request = created
        } catch {
            self.engine = nil
            starting = false
            blockedUntil = Date().addingTimeInterval(60)
            deactivate()
            return
        }
        analyzer = stream
        engine.inputNode.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard time.sampleTime >= 0, let analyzer = self?.analyzer else { return }
            analyzer.analyze(buffer, atAudioFramePosition: time.sampleTime)
        }
        tapped = true
        do {
            engine.prepare()
            try engine.start()
        } catch {
            cleanupEngine()
            starting = false
            blockedUntil = Date().addingTimeInterval(30)
            return
        }
        listening = true
        starting = false
        lastListenAt = now
        deliveryLock.lock()
        delivered = false
        deliveryLock.unlock()
        let windowSeconds = PatrickSoundTheater.windowSeconds
        window = Task { [weak self] in
            try? await Task.sleep(for: .seconds(windowSeconds))
            guard !Task.isCancelled else { return }
            DispatchQueue.main.async { self?.stop() }
        }
    }

    private func stop() {
        starting = false
        listening = false
        cleanupEngine()
    }

    private func cleanupEngine() {
        window?.cancel()
        window = nil
        if let engine {
            if tapped {
                engine.inputNode.removeTap(onBus: 0)
                tapped = false
            }
            if engine.isRunning { engine.stop() }
        }
        if let request { analyzer?.remove(request) }
        request = nil
        analyzer = nil
        engine = nil
        deactivate()
    }

    private func deactivate() {
        guard sessionActive else { return }
        sessionActive = false
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func publish(_ cue: PatrickSoundCue) {
        deliveryLock.lock()
        if delivered {
            deliveryLock.unlock()
            return
        }
        delivered = true
        deliveryLock.unlock()
        NotificationCenter.default.post(name: .patrickSoundCue, object: nil, userInfo: [
            "kind": cue.kind.rawValue,
            "outfit": cue.outfitID,
            "line": cue.line,
            "seconds": cue.seconds
        ])
        DispatchQueue.main.async { self.stop() }
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        for item in classification.classifications {
            guard let cue = PatrickSoundTheater.cue(identifier: item.identifier, confidence: Double(item.confidence)) else { continue }
            publish(cue)
            return
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        DispatchQueue.main.async { self.stop() }
    }

    func requestDidComplete(_ request: SNRequest) {}
}
