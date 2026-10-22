import Foundation
import HealthKit

/// Writes one State of Mind sample. The watch already has the HealthKit entitlement.
/// The phone does not, so it only queues `pendingMindRaw` for this writer.
@MainActor
final class PatrickMoodRecord {
    static let shared = PatrickMoodRecord()
    private let store = HKHealthStore()

    func write(raw: String) async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard let sample = Self.sample(raw: raw) else { return false }
        let share = Set<HKSampleType>([HKSampleType.stateOfMindType()])
        let allowed = await withCheckedContinuation { continuation in
            store.requestAuthorization(toShare: share, read: share) { granted, _ in
                continuation.resume(returning: granted)
            }
        }
        guard allowed else { return false }
        return await withCheckedContinuation { continuation in
            store.save(sample) { success, _ in continuation.resume(returning: success) }
        }
    }

    static func sample(raw: String) -> HKStateOfMind? {
        let valence: Double
        let label: HKStateOfMind.Label
        switch raw {
        case "veryPleasant": valence = 0.8; label = .happy
        case "pleasant": valence = 0.4; label = .content
        case "neutral": valence = 0; label = .calm
        case "unpleasant": valence = -0.4; label = .sad
        case "veryUnpleasant": valence = -0.8; label = .disappointed
        default: return nil
        }
        return HKStateOfMind(date: Date(), kind: .momentaryEmotion, valence: valence,
                             labels: [label], associations: [], metadata: nil)
    }
}
