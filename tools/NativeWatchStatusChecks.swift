import Foundation

@main struct NativeWatchStatusChecks {
    static var count = 0
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        precondition(value(), message); count += 1
    }
    static func main() throws {
        let suite = "patrick.native-watch-status-checks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = PatrickWatchStatusStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_800_000_000.125)
        let observation = PatrickWatchStatusObservation(batteryLevel: 0.765,
                                                       chargingState: .charging, at: now)
        check(store.receipt == nil, "First launch must show unknown, not assumed 100% or charging")
        check(observation.observedAt == now, "Timestamp must retain sub-second precision")
        let decoded = try PatrickWatchStatusObservation.decode(observation.encoded())
        check(decoded == observation, "Battery wire payload preserves observation identity and time")
        defaults.set(Data([1, 2, 3]), forKey: "patrick.timer.v1")
        defaults.set(Data([4, 5, 6]), forKey: "patrick.settings.v1")
        defaults.set(87, forKey: "patrickSettingsRevision")
        check(store.accept(observation, at: now.addingTimeInterval(2)) == .accepted, "Accept valid sample")
        let first = store.receipt!
        check(first.receivedAt == now.addingTimeInterval(2), "Receipt time is independent of observation time")
        check(first.freshness(at: now.addingTimeInterval(300)) == .recent, "Five-minute boundary included")
        check(first.freshness(at: now.addingTimeInterval(301)) == .stale, "Old charging sample must become stale")
        check(first.freshness(at: now.addingTimeInterval(-1)) == .clockMismatch, "Backwards phone clock is unknown")
        check(store.accept(observation, at: now.addingTimeInterval(900)) == .duplicate, "Context/message duplicate ignored")
        check(store.receipt == first, "Duplicate must not freshen receipt time")
        let older = PatrickWatchStatusObservation(batteryLevel: 0.9, chargingState: .full,
                                                 at: now.addingTimeInterval(-100))
        check(store.accept(older, at: now.addingTimeInterval(950)) == .older, "Delayed old state cannot overwrite new state")
        check(store.receipt == first, "Ignored old state leaves both timestamps intact")
        let simultaneous = PatrickWatchStatusObservation(batteryLevel: 0.5, chargingState: .unplugged, at: now)
        check(store.accept(simultaneous, at: now.addingTimeInterval(950)) == .older, "Equal-time conflict cannot regress state")
        let later = PatrickWatchStatusObservation(batteryLevel: 0.76, chargingState: .unplugged,
                                                 at: now.addingTimeInterval(30))
        check(store.accept(later, at: now.addingTimeInterval(1000)) == .accepted, "Later observation may arrive late")
        check(store.receipt!.freshness(at: now.addingTimeInterval(1000)) == .stale, "Late reception must not make stale data recent")
        let reloaded = PatrickWatchStatusStore(defaults: defaults, at: now.addingTimeInterval(1000))
        check(reloaded.receipt == store.receipt, "Relaunch preserves observed/received timestamps")
        let future = PatrickWatchStatusObservation(batteryLevel: 0.8, chargingState: .charging,
                                                  at: now.addingTimeInterval(9000))
        check(store.accept(future, at: now.addingTimeInterval(1000)) == .clockAhead, "Far-future timestamp cannot lock out observations")
        check(store.receipt == reloaded.receipt, "Rejected future sample leaves old status unchanged")
        let slightlyAhead = PatrickWatchStatusObservation(batteryLevel: nil, chargingState: .unknown,
                                                         at: now.addingTimeInterval(1010))
        check(store.accept(slightlyAhead, at: now.addingTimeInterval(1000)) == .accepted, "Small clock skew may be retained")
        check(store.receipt!.freshness(at: now.addingTimeInterval(1000)) == .clockMismatch, "Small clock skew never shown as recent")
        check(store.receipt!.observation.batteryLevel == nil, "Unknown battery remains unknown")
        let slightReload = PatrickWatchStatusStore(defaults: defaults, at: now.addingTimeInterval(1000))
        check(slightReload.receipt == store.receipt, "Small clock skew remains explicit after relaunch")
        check(slightReload.receipt?.freshness(at: now.addingTimeInterval(1000)) == .clockMismatch,
              "Relaunch never turns a future observation into a recent one")
        let corruptReceipt = PatrickWatchStatusReceipt(observation: future, receivedAt: now)
        defaults.set(try JSONEncoder().encode(corruptReceipt), forKey: PatrickWatchStatusStore.storageKey)
        let badReload = PatrickWatchStatusStore(defaults: defaults, at: now.addingTimeInterval(1000))
        check(badReload.receipt == nil, "Persisted observation after receipt by hours is rejected")
        check(defaults.data(forKey: PatrickWatchStatusStore.storageKey) == nil, "Invalid persisted receipt removed")
        let futureReceipt = PatrickWatchStatusReceipt(observation: future, receivedAt: future.observedAt)
        defaults.set(try JSONEncoder().encode(futureReceipt), forKey: PatrickWatchStatusStore.storageKey)
        check(PatrickWatchStatusStore(defaults: defaults, at: now).receipt == nil,
              "Both timestamps in far future after clock correction cannot pin the store")
        let corrected = PatrickWatchStatusObservation(batteryLevel: 0.7, chargingState: .unplugged,
                                                     at: now.addingTimeInterval(50))
        check(store.accept(corrected, at: now.addingTimeInterval(51)) == .accepted,
              "In-process phone clock correction recovers from old future receipt")
        check(store.receipt!.observation == corrected, "New correctly timed observation replaces impossible future receipt")
        for level in [-1.0, 1.1, .infinity, .nan] {
            let unknown = PatrickWatchStatusObservation(batteryLevel: level, chargingState: .unknown, at: now)
            check(unknown.batteryLevel == nil, "Unavailable/invalid battery normalizes to nil, never zero")
        }
        for level in [0.0, 1.0] {
            check(PatrickWatchStatusObservation(batteryLevel: level, chargingState: .unplugged, at: now).batteryLevel == level,
                  "Real empty/full charge values retained")
        }
        var corrupt = observation
        corrupt.batteryLevel = 2
        check(store.accept(corrupt, at: now) == .invalid, "Decoded out-of-range level rejected")
        corrupt = observation; corrupt.observedAtMS = .nan
        check(store.accept(corrupt, at: now) == .invalid, "Non-finite timestamp rejected")
        corrupt = observation; corrupt.version = 2
        check(store.accept(corrupt, at: now) == .invalid, "Unsupported status schema rejected without affecting envelope protocol")
        var sampler = PatrickWatchStatusSampler()
        check(sampler.sample(batteryLevel: 0.75, chargingState: .charging, foreground: false, at: now) == nil,
              "Background cannot fabricate a fresh observation")
        check(sampler.latest == nil, "Background does not seed pending status")
        check(sampler.sample(batteryLevel: 0.75, chargingState: .charging, foreground: true, at: now) != nil,
              "First foreground sample published")
        for seconds in stride(from: 5, through: 55, by: 5) {
            check(sampler.sample(batteryLevel: 0.75, chargingState: .charging, foreground: true,
                                 at: now.addingTimeInterval(Double(seconds))) == nil,
                  "Repeated unchanged face tick does not send status")
        }
        check(sampler.latest?.observedAt == now, "Suppressed tick does not relabel the sent observation timestamp")
        check(sampler.sample(batteryLevel: 0.75, chargingState: .charging, foreground: true,
                             at: now.addingTimeInterval(60)) != nil, "One minute permits a fresh observation heartbeat")
        check(sampler.sample(batteryLevel: 0.75, chargingState: .unplugged, foreground: true,
                             at: now.addingTimeInterval(61)) != nil, "Unplug is immediately observable")
        check(sampler.sample(batteryLevel: 0.76, chargingState: .unplugged, foreground: true,
                             at: now.addingTimeInterval(62)) != nil, "Changed battery percentage is immediately observable")
        let worn = sampler.sample(batteryLevel: 0.76, chargingState: .unplugged, foreground: true, onWrist: true, at: now.addingTimeInterval(130))
        check(worn?.onWrist == true, "A foreground sample is on the wrist, including later Always On")
        let off = sampler.sample(batteryLevel: nil, chargingState: .unknown, foreground: false, onWrist: false, at: now.addingTimeInterval(131))
        check(off?.onWrist == false, "Leaving the foreground reports one off-wrist sample")
        check(sampler.sample(batteryLevel: nil, chargingState: .unknown, foreground: false, onWrist: false, at: now.addingTimeInterval(132)) == nil,
              "Off-wrist is reported once")
        check(sampler.sample(batteryLevel: -1, chargingState: .unknown, foreground: true,
                             at: now.addingTimeInterval(63))?.batteryLevel == nil, "Unknown new sample must not reuse stale charge")
        let statusData = try observation.encoded(), envelopeData = Data([7, 8, 9])
        let statusContext = PatrickWatchStatusTransport.merging(key: PatrickWatchStatusObservation.transportKey,
            data: statusData, into: ["patrick.envelope.v1": envelopeData])
        check(statusContext["patrick.envelope.v1"] as? Data == envelopeData, "Status context preserves current settings envelope")
        let settingsContext = PatrickWatchStatusTransport.merging(key: "patrick.envelope.v1",
            data: Data([9, 8, 7]), into: statusContext)
        check(settingsContext[PatrickWatchStatusObservation.transportKey] as? Data == statusData,
              "Next settings context preserves latest battery observation")
        check(settingsContext.count == 2, "Latest-state context contains two bounded channels")
        let contextGate = PatrickWatchContextReplayGate(defaults: defaults)
        check(!contextGate.alreadyApplied(envelopeData), "First context still delivers its settings")
        contextGate.rememberApplied(envelopeData)
        check(contextGate.alreadyApplied(envelopeData), "Status heartbeat cannot replay unchanged settings or timer")
        let restoredGate = PatrickWatchContextReplayGate(defaults: defaults)
        check(restoredGate.alreadyApplied(envelopeData), "Context replay suppression survives phone restart")
        check(!restoredGate.alreadyApplied(Data([9, 8, 7])), "New settings context still applies")
        contextGate.reset()
        check(!PatrickWatchContextReplayGate(defaults: defaults).alreadyApplied(envelopeData),
              "Watch switch resets prior context identity")
        check(defaults.data(forKey: "patrick.timer.v1") == Data([1, 2, 3]), "No timer contamination")
        check(defaults.data(forKey: "patrick.settings.v1") == Data([4, 5, 6]), "No settings contamination")
        check(defaults.integer(forKey: "patrickSettingsRevision") == 87, "No settings revision increments")
        store.reset(at: now.addingTimeInterval(1100))
        check(store.receipt == nil && PatrickWatchStatusStore(defaults: defaults, at: now.addingTimeInterval(1100)).receipt == nil,
              "Device switch/local reset clears status persistently")
        check(store.accept(later, at: now.addingTimeInterval(1101)) == .beforeReset,
              "Cached context cannot resurrect charge immediately after local reset")
        let afterReset = PatrickWatchStatusStore(defaults: defaults, at: now.addingTimeInterval(1101))
        check(afterReset.accept(later, at: now.addingTimeInterval(1101)) == .beforeReset,
              "Reset cutoff also blocks old context after relaunch")
        let newDeviceSample = PatrickWatchStatusObservation(batteryLevel: 0.5, chargingState: .charging,
                                                            at: now.addingTimeInterval(1102))
        check(afterReset.accept(newDeviceSample, at: now.addingTimeInterval(1103)) == .accepted,
              "A new foreground sample after reset is accepted")
        print("PASS: \(count) Watch status checks (Foundation logic only; no WatchConnectivity or Apple UI execution).")
    }
}
