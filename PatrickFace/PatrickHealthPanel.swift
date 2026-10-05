import SwiftUI
import HealthKit

/// Optional read-only samples. No workout session, background observer or uploads.
@MainActor
final class PatrickHealthReader: ObservableObject {
    struct Reading: Sendable { var value: Double; var date: Date }
    @Published private(set) var steps: Double?
    @Published private(set) var heartRate: Reading?
    @Published private(set) var hrv: Reading?
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var busy = false
    @Published private(set) var message = "按下讀取後，才請求健康資料權限。"
    private let store = HKHealthStore()

    func requestAndRead() async {
        guard !busy else { return }
        guard HKHealthStore.isHealthDataAvailable() else { message = "這台裝置無法讀取健康資料"; return }
        busy = true; defer { busy = false }
        let stepType = HKQuantityType(.stepCount)
        let hrType = HKQuantityType(.heartRate)
        let hrvType = HKQuantityType(.heartRateVariabilitySDNN)
        do {
            try await store.requestAuthorization(toShare: [], read: Set([stepType, hrType, hrvType]))
            // A successful permission request is not proof of read permission.
            steps = nil; heartRate = nil; hrv = nil
            async let today = readSteps(stepType)
            async let hr = latest(hrType, unit: HKUnit.count().unitDivided(by: .minute()))
            async let variability = latest(hrvType, unit: .secondUnit(with: .milli))
            (steps, heartRate, hrv) = try await (today, hr, variability)
            refreshedAt = .now
            message = "只顯示已保存的樣本，不代表即時量測或你的心情。"
        } catch { message = "暫時無法讀取，稍後可重試：\(error.localizedDescription)" }
    }

    private func readSteps(_ type: HKQuantityType) async throws -> Double? {
        let now = Date.now
        let predicate = HKQuery.predicateForSamples(withStart: Calendar.current.startOfDay(for: now), end: now, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: .count())) }
            }
            store.execute(query)
        }
    }

    private func latest(_ type: HKQuantityType, unit: HKUnit) async throws -> Reading? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, results, error in
                if let error { continuation.resume(throwing: error) }
                else if let sample = results?.first as? HKQuantitySample {
                    continuation.resume(returning: Reading(value: sample.quantity.doubleValue(for: unit), date: sample.endDate))
                } else { continuation.resume(returning: nil) }
            }
            store.execute(query)
        }
    }
}

@MainActor struct PatrickHealthPanel: View {
    @StateObject private var reader = PatrickHealthReader()
    var body: some View {
        List {
            Section("自選健康摘要") {
                Button(reader.busy ? "讀取中…" : "允許並讀取／重新整理") { Task { await reader.requestAndRead() } }
                    .disabled(reader.busy)
                Text("今日步數：\(reader.steps.map { String(Int($0)) } ?? "尚無資料")")
                reading("最近心率", reader.heartRate, unit: "次／分")
                reading("最近HRV", reader.hrv, unit: "毫秒")
                if let date = reader.refreshedAt { Text("整理時間：\(date.formatted(date: .abbreviated, time: .shortened))").font(.caption) }
                Text(reader.message).font(.footnote).foregroundStyle(.secondary)
                Text("沒有樣本時無法分辨未授權或尚無紀錄。數值不會自動改心情，也不會傳到手機或網路。").font(.footnote)
            }
        }.navigationTitle("健康摘要")
    }
    private func reading(_ title: String, _ value: PatrickHealthReader.Reading?, unit: String) -> some View {
        VStack(alignment: .leading) {
            Text("\(title)：\(value.map { String(format: "%.0f", $0.value) + " " + unit } ?? "尚無資料")")
            if let value { Text(value.date.formatted(date: .abbreviated, time: .shortened)).font(.caption).foregroundStyle(.secondary) }
        }
    }
}
