import CoreLocation
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Hong Kong Observatory open data. No key. A failed read leaves the last card alone.
enum PatrickObservatoryClient {
    static func fetch() async -> PatrickObservatoryReading? {
        async let warnings = load("warnsum")
        async let reading = load("rhrread")
        let warnData = await warnings
        let readData = await reading
        guard warnData != nil || readData != nil else { return nil }
        let codes = warnData.map { PatrickDayPlan.warnings(from: $0) } ?? []
        let pair = readData.map { PatrickDayPlan.temperatureAndRain(from: $0) } ?? (nil, nil)
        return PatrickObservatoryReading(warningCodes: codes, temperatureC: pair.0, rainfallMM: pair.1)
    }

    private static func load(_ dataType: String) async -> Data? {
        var parts = URLComponents(string: "https://data.weather.gov.hk/weatherAPI/opendata/weather.php")
        parts?.queryItems = [URLQueryItem(name: "dataType", value: dataType), URLQueryItem(name: "lang", value: "tc")]
        guard let url = parts?.url else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return try? await URLSession.shared.data(for: request).0
    }
}

/// One sentence. On-device Foundation Models when the OS offers them; otherwise the fixed line.
enum PatrickButlerModel {
    static func reply(to phrase: PatrickButlerPhrase, name: String) async -> String {
        let fallback = PatrickDayPlan.butlerSentence(phrase, name: name, modelText: nil)
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return fallback }
        let session = LanguageModelSession(instructions: "你是派大星。只用一句繁體中文，最多 40 字。不要提到餵食、飽足、親密、疾病或壓力。")
        let prompt = "\(name)對你說：\(hint(phrase))。用一句話回應。"
        if let response = try? await session.respond(to: prompt),
           let accepted = PatrickDayPlan.acceptButler(response.content) {
            return accepted
        }
        #endif
        return fallback
    }

    private static func hint(_ phrase: PatrickButlerPhrase) -> String {
        switch phrase {
        case .leaving: "我出門了"
        case .arrived: "我回來了"
        case .nap: "午睡 25 分鐘"
        case .goodNight: "晚安"
        case .tired: "我累了"
        }
    }
}

/// Evening and Sunday lines. The model is optional; the fixed sentence is the guarantee.
enum PatrickJournalModel {
    static func evening(events: [String]) async -> String? {
        await sentence("今天的行程是：\(events.joined(separator: "、"))。用一句話記下，不要安排任務。")
    }

    static func weekly(lines: [String]) async -> String? {
        await sentence("這週留下的句子是：\(lines.suffix(8).joined(separator: "，"))。用一句話回顧，不要打分。")
    }

    private static func sentence(_ prompt: String) async -> String? {
        #if canImport(FoundationModels)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return nil }
        let session = LanguageModelSession(instructions: "你是派大星。只用一句繁體中文，最多 80 字。不要提到餵食、飽足、親密、照顧、任務、打卡、分數、疾病或診斷。")
        if let response = try? await session.respond(to: prompt) {
            return PatrickJournalVoice.accept(response.content)
        }
        #endif
        return nil
    }
}

/// When-in-use only. Background arrival is not reliable without Always location,
/// which this app does not request. 「我回來了」 is the path that always records it.
@MainActor
final class PatrickHomeMonitor: NSObject, CLLocationManagerDelegate {
    static let shared = PatrickHomeMonitor()
    private let manager = CLLocationManager()
    var onArrive: ((Date) -> Void)?
    var onLeave: ((Date) -> Void)?

    func update(latitude: Double?, longitude: Double?) {
        manager.delegate = self
        let existing = manager.monitoredRegions.filter { $0.identifier == "patrick.home" }
        guard let latitude, let longitude, (-90...90).contains(latitude), (-180...180).contains(longitude) else {
            existing.forEach { manager.stopMonitoring(for: $0) }
            return
        }
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            let region = CLCircularRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                          radius: 150, identifier: "patrick.home")
            region.notifyOnEntry = true
            region.notifyOnExit = true
            if existing.isEmpty { manager.startMonitoring(for: region) }
        default:
            break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        guard region.identifier == "patrick.home" else { return }
        Task { @MainActor in self.onArrive?(Date()) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        guard region.identifier == "patrick.home" else { return }
        Task { @MainActor in self.onLeave?(Date()) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {}
}
