import Foundation

/// Foundation-only checks; run on a machine with Swift, no Apple UI SDK needed:
/// swiftc PatrickFace/PatrickAnimationCatalog.swift PatrickFace/PatrickAnimationPolicy.swift PatrickFace/PatrickAlivePresence.swift tools/NativeAnimationChecks.swift -o /tmp/patrick-animation-checks
/// /tmp/patrick-animation-checks animation/catalog.json
@main
struct NativeAnimationChecks {
    static var count = 0
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }

    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let awake = PatrickAnimationContext(active: true)
        var asleep = awake; asleep.sleeping = true
        var policy = PatrickAnimationPolicy()
        require(policy.transition(to: awake, at: start) == nil, "Awake entry is not a scene")
        require(policy.transition(to: asleep, at: start) == "yawn", "Sleep entry should yawn once")
        policy.didStart("yawn", at: start)
        require(policy.transition(to: asleep, at: start.addingTimeInterval(900)) == nil, "Remaining asleep must never loop")
        require(policy.transition(to: awake, at: start.addingTimeInterval(100)) == "wake", "Sleep exit should request wake once")
        require(policy.transition(to: asleep, at: start.addingTimeInterval(599)) == nil, "Yawn cooldown should prevent a second entry")
        _ = policy.transition(to: awake, at: start.addingTimeInterval(599))
        require(policy.transition(to: asleep, at: start.addingTimeInterval(600)) == "yawn", "Cooldown boundary should allow a new entry")

        for flag in 0..<4 {
            var quiet = awake
            switch flag {
            case 0: quiet.active = false
            case 1: quiet.wristDown = true
            case 2: quiet.reduceMotion = true
            default: quiet.lowPower = true
            }
            require(!quiet.allowsMotion && !quiet.allowsIdle, "Quiet condition allowed motion")
            quiet.sleeping = true
            var quietPolicy = PatrickAnimationPolicy()
            require(quietPolicy.transition(to: quiet, at: start) == nil, "Quiet sleep entry should remain still")
            require(quietPolicy.transition(to: asleep, at: start.addingTimeInterval(30)) == nil, "Waking wrist must not replay a quiet scene")
            var unseenPolicy = PatrickAnimationPolicy()
            _ = unseenPolicy.transition(to: awake, at: start)
            quiet.sleeping = false
            _ = unseenPolicy.transition(to: quiet, at: start.addingTimeInterval(10))
            var resumed = awake; resumed.completedTimerID = "expired-while-quiet"
            require(unseenPolicy.transition(to: resumed, at: start.addingTimeInterval(70)) == nil,
                    "Completion first observed after an unpolled quiet interval must not perform")
            require(unseenPolicy.transition(to: resumed, at: start.addingTimeInterval(71)) == nil,
                    "Quiet completion must remain consumed on the next foreground tick")
            resumed.completedTimerID = "new-foreground-completion"
            require(unseenPolicy.transition(to: resumed, at: start.addingTimeInterval(90)) == "celebrate",
                    "A new completion during continuous foreground must still perform")
        }

        var visibility = PatrickCompletionVisibility()
        require(!visibility.update(allowsMotion: true), "Cold entry must settle existing deadlines first")
        require(visibility.update(allowsMotion: true), "Continuous foreground admits fresh completions")
        require(!visibility.update(allowsMotion: false), "Settings sheet, wrist down or background is quiet")
        require(!visibility.update(allowsMotion: true), "Quiet resume must settle missed deadlines first")
        require(visibility.update(allowsMotion: true), "Quiet resume must not swallow later foreground completions")

        var scenePolicy = PatrickAnimationPolicy()
        _ = scenePolicy.transition(to: awake, at: start)
        var focus = awake; focus.focusing = true
        require(scenePolicy.transition(to: focus, at: start) == "focus", "Focus entry missing")
        require(scenePolicy.transition(to: focus, at: start) == nil, "Focus repeated")
        var done = awake; done.completedTimerID = "timer-one"
        require(scenePolicy.transition(to: done, at: start) == "celebrate", "Timer completion missing")
        scenePolicy.didStart("celebrate", at: start)
        _ = scenePolicy.transition(to: awake, at: start)
        require(scenePolicy.transition(to: done, at: start) == nil, "Same timer celebrated again")
        require(awake.allowsIdle && asleep.allowsIdle && !focus.allowsIdle, "Sleep pajamas need their authored idle; focus remains quiet")
        require(PatrickAnimationPolicy.idleInterval == 10...22, "Idle random interval changed")
        require(PatrickAnimationPolicy.idleIDs.count == 3, "Three idle choices are required")
        var idlePolicy = PatrickAnimationPolicy()
        idlePolicy.didStart("idle-blink-normal", at: start)
        require(idlePolicy.idleCandidates(from: PatrickAnimationPolicy.idleIDs) == ["idle-blink-slow", "idle-blink-double"],
                "Next idle must exclude the previous variant")
        require(idlePolicy.idleCandidates(from: ["idle-blink-normal"]).isEmpty,
                "Only available idle must not repeat consecutively")
        idlePolicy.didStart("idle-blink-slow", at: start)
        require(idlePolicy.idleCandidates(from: PatrickAnimationPolicy.idleIDs).contains("idle-blink-normal"),
                "A different idle should allow the earlier variant again")

        var timerTracker = PatrickAnimationTimerTracker()
        let end = start.addingTimeInterval(30)
        require(timerTracker.update(id: "focus-one", running: true, paused: false, endsAt: end, at: start).focusing,
                "Running focus timer not detected")
        require(timerTracker.update(id: nil, running: false, paused: false, endsAt: nil, at: end.addingTimeInterval(1)).completedTimerID == "focus-one",
                "Protocol v1 clearing an expired timer lost completion")
        _ = timerTracker.update(id: "focus-two", running: true, paused: false, endsAt: end, at: start)
        require(timerTracker.update(id: nil, running: false, paused: false, endsAt: nil, at: start.addingTimeInterval(10)).completedTimerID == nil,
                "Early timer cancellation celebrated")
        require(timerTracker.update(id: nil, running: false, paused: false, endsAt: nil, at: end).completedTimerID == nil,
                "Cancelled timer reappeared at its old deadline")
        var quietTracker = PatrickAnimationTimerTracker()
        _ = quietTracker.update(id: "quiet-v1", running: true, paused: false, endsAt: end, at: start)
        require(quietTracker.update(id: "quiet-v1", running: true, paused: false, endsAt: end,
                                    at: end.addingTimeInterval(1), allowCompletion: false).completedTimerID == nil,
                "Legacy timer first seen expired after quiet must be consumed silently")
        require(quietTracker.update(id: "quiet-v1", running: true, paused: false, endsAt: end,
                                    at: end.addingTimeInterval(2)).completedTimerID == nil,
                "Legacy timer cannot reappear inside its 60-second detection window")
        let nextEnd = end.addingTimeInterval(30)
        _ = quietTracker.update(id: "visible-v1", running: true, paused: false, endsAt: nextEnd, at: end.addingTimeInterval(3))
        require(quietTracker.update(id: "visible-v1", running: true, paused: false, endsAt: nextEnd,
                                    at: nextEnd).completedTimerID == "visible-v1", "A different visible legacy timer still completes")

        let base: [String: Any] = [
            "id": "yawn", "title": "哈欠", "category": "scene",
            "atlas": "animation/yawn-v1/atlas-eyes-v2.png", "columns": 4, "rows": 2,
            "frameCount": 8, "width": 1774, "height": 887,
            "durationsMs": Array(repeating: 170, count: 8), "anchorNormalized": [0.5, 0.5],
        ]
        func decode(_ object: [String: Any]) throws -> PatrickAnimationClip {
            try JSONDecoder().decode(PatrickAnimationClip.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let clip = try decode(base)
        require(clip.unavailableReason == nil, "Odd-sized atlas should be accepted")
        require(clip.scale == 1, "Missing scale must default to a fixed 1")
        require(clip.cellAspectRatio == 1, "Square cell ratio changed")
        var portrait = base; portrait["width"] = 1200; portrait["height"] = 800
        let portraitClip = try decode(portrait)
        require(portraitClip.cellAspectRatio == 0.75, "Source cell aspect must be preserved")
        require(clip.bundledAtlasPath == "yawn-v1/atlas-eyes-v2.png", "Bundle prefix mapping failed")
        require(clip.pixelBounds(for: 0)?.width == 444, "First fractional cell rounding failed")
        require(clip.pixelBounds(for: 1)?.width == 443, "Second fractional cell rounding failed")
        let last = clip.pixelBounds(for: 7)!
        require(last.x + last.width == 1774 && last.y + last.height == 887, "Grid does not reach the atlas edge")
        var twice = base
        twice["frameCount"] = 16
        twice["frameIndices"] = Array(0..<8) + Array(0..<8)
        twice["durationsMs"] = Array(repeating: 170, count: 16)
        let repeated = try decode(twice)
        require(repeated.unavailableReason == nil, "Playback count must be independent of atlas cell count")
        require(repeated.pixelBounds(for: 8)?.x == clip.pixelBounds(for: 0)?.x, "Repeated frame index ignored")
        for path in ["../old.png", "/old.png", "C:/old.png", "https://example.com/old.png"] {
            var invalid = base; invalid["atlas"] = path
            let decoded = try decode(invalid)
            require(decoded.unavailableReason != nil, "Unsafe atlas path accepted")
        }
        var missing = base; missing["atlas"] = NSNull()
        let missingClip = try decode(missing)
        require(missingClip.unavailableReason != nil, "Missing action must remain unavailable")

        let sourceHash = String(repeating: "a", count: 64)
        let sidecarHash = String(repeating: "b", count: 64)
        let reference: [String: Any] = ["path": "animation/test/regions-v1.json", "sha256": sidecarHash, "version": 1]
        var contourBase = base
        contourBase["atlas"] = "animation/test/source.png"
        contourBase["sha256"] = sourceHash
        contourBase["width"] = 10; contourBase["height"] = 10
        contourBase["frameCount"] = 2; contourBase["durationsMs"] = [100, 120]
        contourBase["frameIndices"] = [0, 0]
        // Grid dimensions have no role when an explicit contour sidecar exists.
        contourBase["columns"] = 0; contourBase["rows"] = 0
        contourBase["frameRegions"] = reference
        let contourClip = try decode(contourBase)
        require(contourClip.unavailableReason == nil, "Contour playback incorrectly requires a regular grid")
        require(contourClip.cellAspectRatio == 1, "Contour output must use the shared square canvas")
        require(contourClip.pixelBounds(for: 0) == nil, "Declared contours must never fall back to grid cropping")
        require(contourClip.frameRegions?.bundledPath == "test/regions-v1.json", "Sidecar bundle prefix mapping failed")
        let regionFrame: [String: Any] = [
            "sourceBounds": [2, 3, 3, 2], "anchorSource": [3, 5],
            "placement": [3, 4], "translation": [1, 1],
            // The gap in row 4 belongs to another shape/background, not this frame.
            "rows": [[3, 2, 5], [4, 2, 3, 4, 5]],
        ]
        let regionBase: [String: Any] = [
            "schemaVersion": 1,
            "source": ["path": "animation/test/source.png", "sha256": sourceHash, "width": 10, "height": 10],
            "canvas": ["width": 8, "height": 8, "anchorPixels": [4, 6], "anchorNormalized": [0.5, 0.75]],
            "frames": [regionFrame],
        ]
        func decodeRegions(_ object: [String: Any]) throws -> PatrickFrameRegions {
            try JSONDecoder().decode(PatrickFrameRegions.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let regions = try decodeRegions(regionBase)
        require(regions.unavailableReason(for: contourClip) == nil, "Valid masked contour or repeated frame index rejected")
        require(regions.frames.count == 1 && contourClip.sourceIndices == [0, 0], "Playback indices must map contour frames")
        require(regions.frames[0].rows[1] == [4, 2, 3, 4, 5], "Disconnected runs must survive decoding")
        require(regions.frames[0].placement != regions.frames[0].translation, "Placement is not whole-atlas translation")

        func rejectRegions(_ object: [String: Any], _ message: String) throws {
            let decoded = try decodeRegions(object)
            require(decoded.unavailableReason(for: contourClip) != nil, message)
        }
        var invalidRegion = regionBase; invalidRegion["schemaVersion"] = 2
        try rejectRegions(invalidRegion, "Unknown contour schema accepted")
        let invalidSources: [[String: Any]] = [
            ["path": "animation/other.png", "sha256": sourceHash, "width": 10, "height": 10],
            ["path": "animation/test/source.png", "sha256": sidecarHash, "width": 10, "height": 10],
            ["path": "animation/test/source.png", "sha256": sourceHash, "width": 11, "height": 10],
        ]
        for replacement in invalidSources {
            invalidRegion = regionBase; invalidRegion["source"] = replacement
            try rejectRegions(invalidRegion, "Mismatched contour source accepted")
        }
        let invalidCanvases: [[String: Any]] = [
            ["width": 8, "height": 7, "anchorPixels": [4, 6], "anchorNormalized": [0.5, 0.75]],
            ["width": 8, "height": 8, "anchorPixels": [4, 6], "anchorNormalized": [0.5, 0.88]],
        ]
        for replacement in invalidCanvases {
            invalidRegion = regionBase; invalidRegion["canvas"] = replacement
            try rejectRegions(invalidRegion, "Invalid canvas or inconsistent pixel anchor accepted")
        }
        func rejectFrame(_ changes: [String: Any], _ message: String) throws {
            var frame = regionFrame
            for (key, value) in changes { frame[key] = value }
            var object = regionBase; object["frames"] = [frame]
            try rejectRegions(object, message)
        }
        try rejectFrame(["translation": [3, 4]], "BBox placement mistaken for atlas translation")
        try rejectFrame(["placement": [4, 4]], "Placement/translation mismatch accepted")
        try rejectFrame(["sourceBounds": [9, 3, 3, 2]], "Source crop beyond PNG accepted")
        try rejectFrame(["placement": [7, 4]], "Masked crop beyond canvas accepted")
        try rejectFrame(["rows": []], "Missing ownership mask accepted")
        try rejectFrame(["rows": [[3, 2, 4, 3, 5]]], "Overlapping ownership runs accepted")
        try rejectFrame(["rows": [[3, 2, 6]]], "Ownership run outside frame accepted")
        try rejectFrame(["rows": [[4, 2, 5], [3, 2, 5]]], "Unordered source rows accepted")
        try rejectFrame(["rows": [[3, 2, 5, 4]]], "Incomplete ownership run accepted")
        var outOfRange = contourBase; outOfRange["frameIndices"] = [0, 1]
        let invalidIndices = try decode(outOfRange)
        require(regions.unavailableReason(for: invalidIndices) != nil, "Playback index beyond contour frame count accepted")
        for path in ["animation/../regions.json", "/regions.json", "C:/regions.json", "a\\regions.json", "a//regions.json"] {
            var invalid = contourBase
            var unsafeReference = reference; unsafeReference["path"] = path
            invalid["frameRegions"] = unsafeReference
            let decoded = try decode(invalid)
            require(decoded.unavailableReason != nil && decoded.pixelBounds(for: 0) == nil, "Unsafe contour path accepted or fell back to grid")
        }
        let invalidDescriptors: [[String: Any]] = [["version": 2], ["sha256": "invalid"]]
        for changes in invalidDescriptors {
            var invalid = contourBase
            var invalidReference = reference
            for (key, value) in changes { invalidReference[key] = value }
            invalid["frameRegions"] = invalidReference
            let decoded = try decode(invalid)
            require(decoded.unavailableReason != nil, "Invalid contour descriptor accepted")
        }

        checkAliveLayer()

        if CommandLine.arguments.count > 1 {
            let url = URL(fileURLWithPath: CommandLine.arguments[1])
            let catalog = try JSONDecoder().decode(PatrickAnimationCatalog.self, from: Data(contentsOf: url))
            require(Set(catalog.clips.map(\.id)).count == catalog.clips.count, "Duplicate catalog IDs")
            for actual in catalog.clips where actual.atlas != nil {
                require(actual.unavailableReason == nil, "Invalid catalog clip: \(actual.id)")
                if let reference = actual.frameRegions, let path = reference.bundledPath {
                    let sidecarURL = url.deletingLastPathComponent().appendingPathComponent(path)
                    let sidecar = try JSONDecoder().decode(PatrickFrameRegions.self, from: Data(contentsOf: sidecarURL))
                    require(sidecar.unavailableReason(for: actual) == nil, "Invalid catalog contour: \(actual.id)")
                }
            }
            for id in PatrickBlinkGate.eyeAnimatingClipIDs {
                require(catalog.clips.contains { $0.id == id }, "Eye-animating clip missing from catalog: \(id)")
            }
            for id in ["idle-blink-normal", "idle-blink-slow", "idle-blink-double"] {
                let clip = catalog.clips.first { $0.id == id }
                let hook = PatrickBlinkArt.hook(for: id)
                require(clip != nil && hook != nil, "Blink resting clip lost its closed-eye hook")
                require(clip?.sourceIndices.contains(hook?.closedSourceIndex ?? -1) == true, "Closed-eye index is not in \(id)")
                require(clip?.atlas?.contains("blink-v2") == true, "Closed-eye still must stay on the blink atlas")
                require(clip?.sourceIndices.first == 0, "Open resting frame of \(id) changed")
            }
            for id in ["pet", "focus", "yawn", "feed", "exercise", "charging", "bedtime-mint", "bedtime-moon", "celebrate", "bath"] {
                require(PatrickBlinkArt.hook(for: id) == nil, "\(id) must not reuse another outfit's closed frame")
            }
        }
        print("PASS: \(count) native animation policy/catalog/contour/alive checks (Foundation only; no graphics or file-hash execution).")
    }

    static func checkAliveLayer() {
        require(PatrickBreathPose.period >= 3 && PatrickBreathPose.period <= 6, "Breath cycle should last a few seconds")
        require(PatrickBreathPose.verticalAmplitude > 0.01 && PatrickBreathPose.verticalAmplitude <= 0.02, "Vertical breath left the 1–2% band")
        require(PatrickBreathPose.pose(at: 0, enabled: false) == .neutral, "Reduce Motion and Always On hold the authored scale")
        require(PatrickBreathPose.pose(at: .nan, enabled: true) == .neutral, "A bad clock must not scale the character")
        let rest = PatrickBreathPose.pose(at: 0, enabled: true)
        require(rest.scaleX == 1 && rest.scaleY == 1, "Breath starts on the foot-anchored rest scale")
        let peak = PatrickBreathPose.pose(at: PatrickBreathPose.period / 2, enabled: true)
        require(abs(peak.scaleY - (1 + PatrickBreathPose.verticalAmplitude)) < 0.000000001, "Inhale peak moved")
        require(abs(peak.scaleX - (1 - PatrickBreathPose.horizontalAmplitude)) < 0.000000001, "Squash peak moved")
        var lowestX = 1.0
        var highestY = 1.0
        let steps = Int((PatrickBreathPose.period / 0.05).rounded())
        for step in 0...steps {
            let pose = PatrickBreathPose.pose(at: Double(step) * 0.05, enabled: true)
            require(pose.scaleY >= 1 && pose.scaleY <= 1.02, "Vertical breath left 1.00–1.02")
            require(pose.scaleX <= 1 && pose.scaleX >= 0.99, "Horizontal squash left 0.99–1.00")
            lowestX = min(lowestX, pose.scaleX)
            highestY = max(highestY, pose.scaleY)
        }
        require(highestY > 1.01 && lowestX < 1, "Breath pose never leaves rest")
        let authoredFoot = PatrickAlivePlacement.footAnchor([0.5, 0.8803571428571428])
        require(authoredFoot.x == 0.5 && authoredFoot.y == 0.8803571428571428, "Foot anchor should be the authored point")
        let clampedFoot = PatrickAlivePlacement.footAnchor([2, -1])
        require(clampedFoot.x == 1 && clampedFoot.y == 0, "Foot anchor must stay inside the image")
        let fallbackFoot = PatrickAlivePlacement.footAnchor([0.5])
        require(fallbackFoot.x == 0.5 && fallbackFoot.y == 1, "A missing foot anchor falls back to the bottom")

        require(PatrickBlinkClock.interval == 3...6, "Blink gap left 3–6 seconds")
        require(PatrickBlinkClock.doubleBlinkProbability > 0.1 && PatrickBlinkClock.doubleBlinkProbability < 0.35, "Double blink should stay occasional")
        require(PatrickBlinkClock.closedHold > PatrickAliveCadence.sampleInterval, "8 Hz sampling can skip the closed lid")
        require(PatrickBlinkClock.doubleGap > PatrickAliveCadence.sampleInterval, "8 Hz sampling can fuse a double blink")
        require(PatrickBlinkClock.clampedGap(0) == 3 && PatrickBlinkClock.clampedGap(100) == 6, "Blink gap must stay inside 3–6 seconds")
        require(PatrickBlinkArt.missingArt.contains("blink-v2") && PatrickBlinkArt.missingArt.contains("眼皮"), "Missing-art note lost the lid hook")
        require(PatrickBlinkArt.hook(for: "idle-blink-normal")?.closedSourceIndex == 3, "Closed lid should be blink-v2 frame 4")
        require(PatrickBlinkArt.hook(for: "pet") == nil, "Classic outfit has no closed-eye still")

        let t0 = 10_000.0
        var rolls = 0
        func take(_ gap: TimeInterval, _ isDouble: Bool) -> PatrickBlinkRoll {
            rolls += 1
            return PatrickBlinkRoll(gap: gap, isDouble: isDouble)
        }
        rolls = 0
        let single = PatrickBlinkClock.unarmed.advanced(to: t0, allow: true) { take(3, false) }
        require(rolls == 1, "Arming the first blink rolled more than once")
        require(single.nextStart == t0 + 3 && !single.isDouble && !single.suspended, "Single blink did not wait the lower gap")
        require(!single.eyesClosed(at: single.nextStart - 0.001, allow: true), "Eyes closed before the blink")
        require(single.eyesClosed(at: single.nextStart, allow: true), "Eyes stayed open at the blink start")
        require(single.eyesClosed(at: single.nextStart + PatrickBlinkClock.closedHold - 0.001, allow: true), "Closed hold ended early")
        require(!single.eyesClosed(at: single.nextStart + PatrickBlinkClock.closedHold, allow: true), "Eyes stayed closed after the hold")
        require(!single.eyesClosed(at: single.nextStart + 0.02, allow: false), "Reduce Motion or wrist-down still closed the eyes")
        let secondWindow = single.nextStart + PatrickBlinkClock.closedHold + PatrickBlinkClock.doubleGap
        require(!single.eyesClosed(at: secondWindow + 0.02, allow: true), "A single blink grew a second close")
        rolls = 0
        let waiting = single.advanced(to: single.nextStart + 0.02, allow: true) { take(6, true) }
        require(rolls == 0 && waiting == single, "An in-flight blink must not roll the next one")

        rolls = 0
        let doubled = PatrickBlinkClock.unarmed.advanced(to: t0, allow: true) { take(6, true) }
        let start = t0 + 6
        let second = start + PatrickBlinkClock.closedHold + PatrickBlinkClock.doubleGap
        require(doubled.eyesClosed(at: start + 0.01, allow: true), "Double blink missed the first close")
        require(!doubled.eyesClosed(at: start + PatrickBlinkClock.closedHold + 0.01, allow: true), "Double blink has no open gap")
        require(doubled.eyesClosed(at: second + 0.01, allow: true), "Double blink missed the second close")
        require(!doubled.eyesClosed(at: second + PatrickBlinkClock.closedHold, allow: true), "Double blink did not reopen")
        rolls = 0
        let chained = doubled.advanced(to: doubled.windowEnd, allow: true) { take(4, false) }
        require(rolls == 1 && chained.nextStart == start + 4, "The next blink must be one 3–6 s gap after the previous start")
        require(!chained.eyesClosed(at: doubled.windowEnd, allow: true), "Chaining blinked again immediately")

        rolls = 0
        let paused = chained.advanced(to: chained.nextStart + 30, allow: false) { take(3, true) }
        require(rolls == 0 && paused.suspended, "A pause consumed a blink")
        require(!paused.eyesClosed(at: chained.nextStart + 0.01, allow: false), "A paused clock still closed the eyes")
        let resumed = paused.advanced(to: chained.nextStart + 30, allow: true) { take(5, false) }
        require(rolls == 1 && resumed.nextStart == chained.nextStart + 30 + 5, "Waking up must wait one fresh gap, not replay missed blinks")
        require(!resumed.eyesClosed(at: chained.nextStart + 30, allow: true), "Resume blinked on the same frame")

        rolls = 0
        let stale = PatrickBlinkClock(nextStart: t0, isDouble: false, suspended: false)
        let caughtUp = stale.advanced(to: t0 + 60, allow: true) { take(3, false) }
        require(rolls == 2 && caughtUp.nextStart == t0 + 60 + 3, "A long stall must arm one future blink, not a burst")
        require(!caughtUp.eyesClosed(at: t0 + 60, allow: true), "Catch-up closed the eyes at the stall")

        require(!PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: true, reduceMotion: false, playing: false, clipID: nil, hasRestingClosedFrame: true), "Always On still blinked")
        require(!PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: true, playing: false, clipID: nil, hasRestingClosedFrame: true), "Reduce Motion still blinked")
        require(!PatrickBlinkGate.allows(motionAllowed: false, luminanceReduced: false, reduceMotion: false, playing: false, clipID: nil, hasRestingClosedFrame: true), "A quiet face still blinked")
        require(!PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: false, playing: false, clipID: nil, hasRestingClosedFrame: false), "A missing closed frame still blinked")
        require(PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: false, playing: false, clipID: nil, hasRestingClosedFrame: true), "Resting still with a closed frame should blink")
        require(!PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: false, playing: true, clipID: "idle-blink-normal", hasRestingClosedFrame: true, closedFrameTracksCurrentClip: true), "Procedural blink fought an eye clip")
        require(!PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: false, playing: true, clipID: "yawn", hasRestingClosedFrame: true, closedFrameTracksCurrentClip: true), "Procedural blink fought the yawn")
        require(!PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: false, playing: true, clipID: "pet", hasRestingClosedFrame: true), "Resting closed frame replaced a playing clip")
        require(PatrickBlinkGate.allows(motionAllowed: true, luminanceReduced: false, reduceMotion: false, playing: true, clipID: "pet", hasRestingClosedFrame: true, closedFrameTracksCurrentClip: true), "A future tracking lid should be allowed on a clip that does not animate the eyes")
    }
}
