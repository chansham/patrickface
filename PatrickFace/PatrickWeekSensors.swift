import CoreMotion
import Foundation

extension Notification.Name {
    static let patrickRideChanged = Notification.Name("patrick.ride.changed")
    static let patrickWaterChanged = Notification.Name("patrick.water.changed")
}

/// Ride, overnight motion, and water. Missing permission or the water entitlement leaves the flags alone.
final class PatrickWeekSensors: NSObject, CMWaterSubmersionManagerDelegate {
    static let shared = PatrickWeekSensors()

    private let activity = CMMotionActivityManager()
    private let recorder = CMSensorRecorder()
    private var water: CMWaterSubmersionManager?
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        if CMMotionActivityManager.isActivityAvailable() {
            activity.startActivityUpdates(to: .main) { motion in
                let riding = motion?.automotive == true && motion?.confidence != .low
                NotificationCenter.default.post(name: .patrickRideChanged, object: nil, userInfo: ["riding": riding])
            }
        }
        if CMSensorRecorder.isAccelerometerRecordingAvailable() {
            switch CMSensorRecorder.authorizationStatus() {
            case .authorized, .notDetermined:
                recorder.recordAccelerometer(forDuration: 12 * 60 * 60)
            default:
                break
            }
        }
        guard CMWaterSubmersionManager.waterSubmersionAvailable else { return }
        let manager = CMWaterSubmersionManager()
        manager.delegate = self
        water = manager
    }

    /// Caps the walk so a full night of samples cannot stall the watch. A short read still tells the story.
    func tossCount(from start: Date, to end: Date) -> Int {
        guard let list = recorder.accelerometerData(from: start, to: end) else { return 0 }
        var magnitudes: [Double] = []
        let enumerator = NSFastEnumerationIterator(list)
        while let object = enumerator.next() {
            guard let sample = object as? CMRecordedAccelerometerData else { continue }
            let acceleration = sample.acceleration
            let magnitude = (acceleration.x * acceleration.x + acceleration.y * acceleration.y + acceleration.z * acceleration.z).squareRoot()
            if magnitude.isFinite { magnitudes.append(magnitude) }
            if magnitudes.count >= 8000 { break }
        }
        return PatrickNightMotion.tosses(magnitudes)
    }

    func manager(_ manager: CMWaterSubmersionManager, didUpdate event: CMWaterSubmersionEvent) {
        if event.state == .unknown { return }
        let submerged = event.state == .submerged
        NotificationCenter.default.post(name: .patrickWaterChanged, object: nil, userInfo: ["submerged": submerged])
    }

    func manager(_ manager: CMWaterSubmersionManager, didUpdate measurement: CMWaterSubmersionMeasurement) {}

    func manager(_ manager: CMWaterSubmersionManager, errorOccurred error: Error) {
        water = nil
    }
}
