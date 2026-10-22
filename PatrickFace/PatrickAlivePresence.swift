import Foundation

/// Subtle life between animation clips. Timing is pure Foundation so it can be
/// tested without SwiftUI, a display link, or a frame loop.
///
/// Breathing is a 1.5% vertical stretch with a smaller horizontal squash.
/// The view scales around the character's foot anchor, so the extra height
/// grows upward and the feet stay put. The digital clock is a later sibling
/// and is never part of this transform.
///
/// Blinking swaps in an existing closed-eye drawing only when
/// `PatrickBlinkArt` has a same-atlas still for the resting clip. There is
/// no eyes-only lid overlay. See `PatrickBlinkArt.missingArt`.
enum PatrickAliveCadence {
    /// Eight updates a second while the face is awake. Slow enough for a
    /// four-second breath, and shorter than the blink hold so a sample lands
    /// inside every close. `TimelineView` owns the schedule; nothing polls.
    static let sampleInterval: TimeInterval = 0.125
}

struct PatrickBreathPose: Equatable, Sendable {
    var scaleX: Double
    var scaleY: Double

    /// A few seconds, starting and ending on the authored scale.
    static let period: TimeInterval = 4
    /// Peak inhale. Stays inside the requested 1–2% vertical band.
    static let verticalAmplitude = 0.015
    /// Slight squash while the body is taller, so the breath is not a uniform zoom.
    static let horizontalAmplitude = 0.008

    static let neutral = PatrickBreathPose(scaleX: 1, scaleY: 1)

    /// `time` is any monotonic clock (seconds). Disabled poses stay at rest,
    /// which is what Always On, Reduce Motion, and low power should show.
    static func pose(at time: TimeInterval, enabled: Bool) -> PatrickBreathPose {
        guard enabled, period > 0, time.isFinite else { return neutral }
        let lift = (1 - cos(time / period * 2 * .pi)) / 2
        return PatrickBreathPose(
            scaleX: 1 - horizontalAmplitude * lift,
            scaleY: 1 + verticalAmplitude * lift
        )
    }
}

/// Foot point inside the character image. Unit space matches SwiftUI:
/// x grows right, y grows down. Scaling around this point keeps the feet still.
enum PatrickAlivePlacement {
    static func footAnchor(_ anchor: [Double]) -> (x: Double, y: Double) {
        guard anchor.count == 2, anchor.allSatisfy(\.isFinite) else { return (0.5, 1) }
        return (min(1, max(0, anchor[0])), min(1, max(0, anchor[1])))
    }
}

struct PatrickBlinkRoll: Equatable, Sendable {
    var gap: TimeInterval
    var isDouble: Bool

    static func random() -> PatrickBlinkRoll {
        var generator = SystemRandomNumberGenerator()
        return PatrickBlinkRoll(
            gap: Double.random(in: PatrickBlinkClock.interval, using: &generator),
            isDouble: Double.random(in: 0..<1, using: &generator) < PatrickBlinkClock.doubleBlinkProbability
        )
    }
}

/// One scheduled blink. `nextStart == 0` means "not armed yet".
/// A pause drops the in-flight blink. The next allowed sample waits one fresh
/// 3–6 s gap, so a long Always On interval cannot dump a burst of blinks.
struct PatrickBlinkClock: Equatable, Sendable {
    var nextStart: TimeInterval
    var isDouble: Bool
    var suspended: Bool

    static let unarmed = PatrickBlinkClock(nextStart: 0, isDouble: false, suspended: false)
    static let interval: ClosedRange<TimeInterval> = 3...6
    /// About one blink in five is a double. The rest are single.
    static let doubleBlinkProbability = 0.2
    /// Longer than `PatrickAliveCadence.sampleInterval`, so an 8 Hz timeline
    /// cannot step over the closed lid.
    static let closedHold: TimeInterval = 0.16
    /// Open gap between the two closes. Also longer than the sample interval,
    /// so a double blink cannot collapse into one long close.
    static let doubleGap: TimeInterval = 0.18

    static func clampedGap(_ gap: TimeInterval) -> TimeInterval {
        guard gap.isFinite else { return interval.lowerBound }
        return min(interval.upperBound, max(interval.lowerBound, gap))
    }

    var windowEnd: TimeInterval {
        let singleEnd = nextStart + Self.closedHold
        guard isDouble else { return singleEnd }
        return singleEnd + Self.doubleGap + Self.closedHold
    }

    func eyesClosed(at now: TimeInterval, allow: Bool) -> Bool {
        guard allow, !suspended, nextStart > 0, now.isFinite else { return false }
        if (nextStart..<(nextStart + Self.closedHold)).contains(now) { return true }
        guard isDouble else { return false }
        let second = nextStart + Self.closedHold + Self.doubleGap
        return (second..<(second + Self.closedHold)).contains(now)
    }

    /// `roll` is called only when a new blink is armed, never on an open wait.
    func advanced(to now: TimeInterval, allow: Bool, roll: () -> PatrickBlinkRoll) -> PatrickBlinkClock {
        guard now.isFinite else { return self }
        if !allow {
            var paused = self
            paused.suspended = true
            return paused
        }
        if suspended || nextStart == 0 {
            return armed(at: now, roll: roll())
        }
        if now < windowEnd { return self }
        let chained = armed(at: nextStart, roll: roll())
        if now < chained.windowEnd { return chained }
        return armed(at: now, roll: roll())
    }

    func armed(at anchor: TimeInterval, roll: PatrickBlinkRoll) -> PatrickBlinkClock {
        PatrickBlinkClock(
            nextStart: anchor + Self.clampedGap(roll.gap),
            isDouble: roll.isDouble,
            suspended: false
        )
    }
}

enum PatrickBlinkGate {
    /// Clips whose drawings already move the eyelids. A procedural blink stays
    /// off while one of these is playing, even if a future overlay could track
    /// the current frame. Playback of any other clip also stays open unless
    /// `closedFrameTracksCurrentClip` is set, because today's closed drawing
    /// is a resting still, not a lid that follows the action.
    static let eyeAnimatingClipIDs: Set<String> = [
        "idle-blink-normal", "idle-blink-slow", "idle-blink-double",
        "yawn", "wake", "bedtime-mint", "bedtime-moon",
        "focus", "exercise", "charging", "charging-classic", "feed",
    ]

    static func animatesEyes(_ clipID: String?) -> Bool {
        guard let clipID else { return false }
        return eyeAnimatingClipIDs.contains(clipID)
    }

    static func allows(
        motionAllowed: Bool,
        luminanceReduced: Bool,
        reduceMotion: Bool,
        playing: Bool,
        clipID: String?,
        hasRestingClosedFrame: Bool,
        closedFrameTracksCurrentClip: Bool = false
    ) -> Bool {
        guard motionAllowed, !luminanceReduced, !reduceMotion, hasRestingClosedFrame else { return false }
        guard playing else { return true }
        if animatesEyes(clipID) { return false }
        return closedFrameTracksCurrentClip
    }
}

/// Where a closed-eye drawing can be swapped onto the current resting still.
/// The index is a source-atlas index, not a playback index.
enum PatrickBlinkArt {
    struct Hook: Equatable, Sendable {
        var closedSourceIndex: Int
        var note: String
    }

    /// blink-v2 frames 4 and 5 (source indices 3 and 4) are the fully closed
    /// pink lids on the star-pajama pillow pose. Index 3 is the one the
    /// runtime holds. The same eight drawings are shared by the slow and
    /// double idle clips. Hat, pillow, and shirt are not pixel-locked, so the
    /// swap is a blink with a small body difference, not a clean lid overlay.
    static func hook(for clipID: String) -> Hook? {
        switch clipID {
        case "idle-blink-normal", "idle-blink-slow", "idle-blink-double":
            return Hook(
                closedSourceIndex: 3,
                note: "blink-v2 source index 3 (frame 4), the first fully closed lid. Index 4 is the other closed drawing and is not swapped in."
            )
        default:
            return nil
        }
    }

    /// Shown in review notes. Not drawn into the watch face.
    static let missingArt = "沒有可疊在任意造型上的閉眼眼皮圖層。目前唯一用得上的閉眼原畫是 blink-v2 第4格（來源索引3；第5格也是閉眼），而且只在星星抱枕睡衣的待機靜幀 idle-blink-normal、idle-blink-slow、idle-blink-double 上整格替換。其他圖集裡的閉眼格同時改了手、毯子、啞鈴或整段姿勢，不能蓋到另一套衣服上。缺的畫：每套造型待機靜幀各自的閉眼靜幀，或對齊該靜幀眼睛的眼皮遮罩；身體、帽子和道具要保持不動。"
}
