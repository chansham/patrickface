import AVFoundation
import Combine
import Foundation
import UIKit

@MainActor
final class ThemeSoundPlayer {
    private var engine: AVAudioEngine?
    private var player: AVAudioPlayerNode?
    private var playbackID: UUID?
    private var cancellables = Set<AnyCancellable>()

    init() {
        // UIKit notifications also protect legacy callers outside the new page.
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .merge(with: NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange),
                   NotificationCenter.default.publisher(for: UIAccessibility.reduceMotionStatusDidChangeNotification))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in Task { @MainActor in self?.stop() } }
            .store(in: &cancellables)
    }

    /// Generates a short original two-note cue at runtime. No copyrighted audio
    /// or microphone input is bundled or recorded.
    @discardableResult
    func play(for theme: PatrickTheme, allowEffects: Bool) throws -> Bool {
        stop()
        guard allowEffects, UIApplication.shared.applicationState == .active,
              !UIAccessibility.isReduceMotionEnabled, !ProcessInfo.processInfo.isLowPowerModeEnabled else { return false }

        let sampleRate = 44_100.0
        let duration = 0.48
        let frameCount = AVAudioFrameCount(sampleRate * duration)
        guard
            let format = AVAudioFormat(
                standardFormatWithSampleRate: sampleRate,
                channels: 1
            ),
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: frameCount
            ),
            let channel = buffer.floatChannelData?[0]
        else {
            throw ThemeSoundError.couldNotCreateBuffer
        }

        buffer.frameLength = frameCount
        let notes: (Double, Double) = theme == .cel1999
            ? (523.25, 659.25)
            : (392.00, 493.88)

        for frame in 0 ..< Int(frameCount) {
            let time = Double(frame) / sampleRate
            let frequency = time < duration / 2 ? notes.0 : notes.1
            let attack = min(1, time / 0.025)
            let release = min(1, max(0, (duration - time) / 0.10))
            let envelope = attack * release * 0.16
            channel[frame] = Float(sin(2 * .pi * frequency * time) * envelope)
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        try engine.start()

        self.engine = engine
        self.player = player
        let playbackID = UUID()
        self.playbackID = playbackID
        player.scheduleBuffer(buffer, at: nil)
        player.play()

        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(650))
            guard self?.playbackID == playbackID else { return }
            self?.stop()
        }
        return true
    }

    func stop() {
        playbackID = nil
        player?.stop()
        engine?.stop()
        player = nil
        engine = nil
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
}

enum ThemeSoundError: LocalizedError {
    case couldNotCreateBuffer

    var errorDescription: String? {
        "The local theme sound buffer could not be created."
    }
}
