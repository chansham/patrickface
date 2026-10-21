import Foundation
import HealthKit

/// Writes a real workout while an exercise countdown is running.
/// Authorization failure leaves the countdown in place and records nothing.
@MainActor
final class PatrickWorkoutCompanion: NSObject, HKWorkoutSessionDelegate, HKLiveWorkoutBuilderDelegate {
    static let shared = PatrickWorkoutCompanion()

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastMeters = 0.0
    private var buzzedKilometer = 0
    private var announcedZone: Int?
    var onZone: ((Int) -> Void)?
    var onKilometer: ((Int) -> Void)?

    func begin(_ kind: PatrickActivityKind) async -> Bool {
        guard let activity = Self.activityType(for: kind) else { return false }
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        let read: Set<HKObjectType> = [HKObjectType.workoutType(), HKQuantityType(.heartRate), HKQuantityType(.distanceWalkingRunning)]
        let allowed = await requestShare(share, read: read)
        guard allowed else { return false }
        if session != nil { await end() }
        lastMeters = 0
        buzzedKilometer = 0
        announcedZone = nil
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = activity
        configuration.locationType = kind == .walking || kind == .running ? .outdoor : .indoor
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date()
            session.startActivity(with: start)
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                builder.beginCollection(withStart: start) { _, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            return true
        } catch {
            self.session = nil
            self.builder = nil
            return false
        }
    }

    func end() async {
        guard let session, let builder else { return }
        self.session = nil
        self.builder = nil
        session.end()
        let end = Date()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            builder.endCollection(withEnd: end) { _, _ in
                builder.finishWorkout { _, _ in continuation.resume() }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.session = nil
            self.builder = nil
        }
    }

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heart = HKQuantityType(.heartRate)
        let distance = HKQuantityType(.distanceWalkingRunning)
        let bpm = collectedTypes.contains(heart)
            ? workoutBuilder.statistics(for: heart)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            : nil
        let meters = collectedTypes.contains(distance)
            ? workoutBuilder.statistics(for: distance)?.sumQuantity()?.doubleValue(for: .meter())
            : nil
        let beats = bpm
        let walked = meters
        Task { @MainActor in
            self.consume(bpm: beats, meters: walked)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    private func requestShare(_ types: Set<HKSampleType>, read: Set<HKObjectType>) async -> Bool {
        let status = store.authorizationStatus(for: HKObjectType.workoutType())
        if status == .sharingAuthorized { return true }
        return await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: types, read: read) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
    }

    private func consume(bpm: Double?, meters: Double?) {
        if let bpm, let zone = PatrickHeartZone.zone(beatsPerMinute: bpm), zone.rawValue != announcedZone {
            announcedZone = zone.rawValue
            onZone?(zone.rawValue)
        }
        if let meters {
            if let km = PatrickKilometerMarks.crossed(previousMeters: lastMeters, meters: meters), km > buzzedKilometer {
                buzzedKilometer = km
                onKilometer?(km)
            }
            lastMeters = max(lastMeters, meters)
        }
    }

    static func activityType(for kind: PatrickActivityKind) -> HKWorkoutActivityType? {
        switch kind {
        case .walking: .walking
        case .running: .running
        case .strength: .traditionalStrengthTraining
        case .exercise: .other
        case .focus, .breathing: nil
        }
    }
}
