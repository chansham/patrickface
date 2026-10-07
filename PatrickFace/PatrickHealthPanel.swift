import SwiftUI
import HealthKit

/// Optional foreground reads only. No observer, workout, upload, WC or value persistence.
@MainActor final class PatrickHealthReader: ObservableObject {
    @Published private(set) var selected: Set<PatrickHealthMetric>
    @Published private(set) var autoRefreshOnOpen: Bool
    @Published private(set) var results: [PatrickHealthMetric: PatrickHealthResult] = [:]
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var busy = false
    @Published private(set) var message = "先選擇想看的項目，再主動授權讀取。"
    private let store = HKHealthStore()
    private let preferences: UserDefaults
    private var previouslyRequested: Set<PatrickHealthMetric>
    private var gate = PatrickHealthReadGate()
    private var queries: [UUID: HKQuery] = [:]
    private var cancellations: [UUID: () -> Void] = [:]
    private static let selectionKey = "patrick.health.selected.v1"
    private static let requestedKey = "patrick.health.requested.v1"
    private static let automaticKey = "patrick.health.refresh-on-open.v1"

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        selected = Set((preferences.stringArray(forKey: Self.selectionKey) ?? []).compactMap(PatrickHealthMetric.init(rawValue:)))
        previouslyRequested = Set((preferences.stringArray(forKey: Self.requestedKey) ?? []).compactMap(PatrickHealthMetric.init(rawValue:)))
        autoRefreshOnOpen = preferences.bool(forKey: Self.automaticKey)
        gate.setSelected(selected)
    }
    func setSelected(_ metric: PatrickHealthMetric, enabled: Bool) {
        if enabled { selected.insert(metric) } else { selected.remove(metric) }
        gate.setSelected(selected); clearQueriesAndValues()
        preferences.set(selected.map(\.rawValue).sorted(), forKey: Self.selectionKey)
        message = "選項已更新。新增項目需按授權讀取；不會自動開啟權限視窗。"
    }
    func setAutomatic(_ value: Bool) {
        autoRefreshOnOpen = value
        preferences.set(value, forKey: Self.automaticKey)
    }
    func setPresentationActive(_ active: Bool) {
        guard gate.active != active else { return }
        gate.setActive(active); clearQueriesAndValues()
        if !active { message = "離開健康頁或暫停顯示時，已清除本頁資料。" }
    }
    func clearDisplayedData() {
        gate.invalidate(); clearQueriesAndValues()
        message = "本頁數值已清除；不會刪除健康 App 的紀錄。"
    }
    /// Only this explicit button action requests authorization.
    func requestAndRead() async {
        guard gate.active, !busy, !selected.isEmpty else { return }
        guard HKHealthStore.isHealthDataAvailable() else { message = "這台裝置無法讀取健康資料。"; return }
        let metrics = selected, token = beginRead()
        do {
            let types: Set<HKObjectType> = Set(metrics.map { Self.sampleType(for: $0) as HKObjectType })
            try await store.requestAuthorization(toShare: [], read: types)
            guard isCurrent(token) else { return }
            // Completion is not proof of read permission. Remember only that the user asked.
            previouslyRequested.formUnion(metrics)
            preferences.set(previouslyRequested.map(\.rawValue).sorted(), forKey: Self.requestedKey)
            await load(metrics, token: token)
        } catch {
            guard isCurrent(token) else { return }
            busy = false; message = "本次讀取未完成，可稍後再試；不會把失敗當成零。"
        }
    }
    /// Never requests authorization; newly selected types remain unread.
    func refreshSelectedWithoutPrompt() async {
        guard gate.active, !busy else { return }
        let metrics = PatrickHealthReadGate.refreshable(selected: selected, previouslyRequested: previouslyRequested)
        guard !metrics.isEmpty else { message = "尚未主動請求所選項目的讀取權限。"; return }
        guard HKHealthStore.isHealthDataAvailable() else { message = "這台裝置無法讀取健康資料。"; return }
        await load(metrics, token: beginRead())
    }
    private func beginRead() -> UInt64 {
        gate.invalidate(); clearQueriesAndValues(); busy = true
        message = "正在讀取已保存的樣本…"
        return gate.generation
    }
    private func isCurrent(_ token: UInt64) -> Bool { gate.active && gate.generation == token }
    private func load(_ metrics: Set<PatrickHealthMetric>, token: UInt64) async {
        let now = Date.now
        for metric in PatrickHealthMetric.allCases where metrics.contains(metric) {
            guard gate.accepts(token, metric: metric) else { return }
            do {
                let reading: PatrickHealthReading?
                let window = metric.queryWindow(at: now)
                switch metric {
                case .steps: reading = try await readSteps(in: window)
                case .sleep: reading = try await readSleep(in: window)
                default: reading = try await latest(metric, in: window)
                }
                guard gate.accepts(token, metric: metric) else { return }
                results[metric] = reading.map(PatrickHealthResult.reading) ?? .noSamples
            } catch {
                guard gate.accepts(token, metric: metric) else { return }
                results[metric] = .unavailable
            }
        }
        guard isCurrent(token) else { return }
        busy = false; refreshedAt = .now
        message = "只顯示可讀到的紀錄，不代表即時量測、壓力或疾病判斷。"
    }
    private func clearQueriesAndValues() {
        let pendingQueries = Array(queries.values), pendingCancellations = Array(cancellations.values)
        queries.removeAll(); cancellations.removeAll()
        pendingQueries.forEach { store.stop($0) }
        // Stopping a HealthKit query does not guarantee our continuation completes.
        pendingCancellations.forEach { $0() }
        results.removeAll(); refreshedAt = nil; busy = false
    }
    private func execute<Value: Sendable>(_ makeQuery: (@escaping @Sendable (Result<Value, Error>) -> Void) -> HKQuery) async throws -> Value {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let query = makeQuery { [weak self] result in
                Task { @MainActor in
                    guard let self, let _ = self.cancellations.removeValue(forKey: id) else { return }
                    self.queries.removeValue(forKey: id)
                    continuation.resume(with: result)
                }
            }
            cancellations[id] = { continuation.resume(throwing: CancellationError()) }
            queries[id] = query; store.execute(query)
        }
    }
    private static func sampleType(for metric: PatrickHealthMetric) -> HKSampleType {
        switch metric {
        case .steps: HKQuantityType(.stepCount)
        case .heartRate: HKQuantityType(.heartRate)
        case .hrvSDNN: HKQuantityType(.heartRateVariabilitySDNN)
        case .restingHeartRate: HKQuantityType(.restingHeartRate)
        case .respiratoryRate: HKQuantityType(.respiratoryRate)
        case .wristTemperature: HKQuantityType(.appleSleepingWristTemperature)
        case .sleep: HKCategoryType(.sleepAnalysis)
        }
    }
    private static func unit(for metric: PatrickHealthMetric) -> HKUnit {
        switch metric {
        case .steps: .count()
        case .hrvSDNN: .secondUnit(with: .milli)
        case .wristTemperature: .degreeCelsius()
        case .sleep: .hour()
        default: HKUnit.count().unitDivided(by: .minute())
        }
    }
    private func readSteps(in window: DateInterval) async throws -> PatrickHealthReading? {
        let type = HKQuantityType(.stepCount)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        return try await execute { finish in
            HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                options: [.cumulativeSum, .separateBySource]) { _, result, error in
                if let error { finish(.failure(error)); return }
                guard let quantity = result?.sumQuantity() else { finish(.success(nil)); return }
                let sources = (result?.sources ?? []).map { PatrickHealthSource(name: $0.name, bundleID: $0.bundleIdentifier, deviceName: nil) }
                finish(.success(PatrickHealthReading(value: quantity.doubleValue(for: .count()),
                    start: window.start, end: window.end, sources: sources, isAggregate: true)))
            }
        }
    }
    private func latest(_ metric: PatrickHealthMetric, in window: DateInterval) async throws -> PatrickHealthReading? {
        let type = Self.sampleType(for: metric), unit = Self.unit(for: metric)
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictEndDate)
        return try await execute { finish in
            HKSampleQuery(sampleType: type, predicate: predicate, limit: 1,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, results, error in
                if let error { finish(.failure(error)); return }
                guard let sample = results?.first as? HKQuantitySample else { finish(.success(nil)); return }
                let source = PatrickHealthSource(name: sample.sourceRevision.source.name,
                    bundleID: sample.sourceRevision.source.bundleIdentifier, deviceName: sample.device?.name)
                finish(.success(PatrickHealthReading(value: sample.quantity.doubleValue(for: unit),
                    start: sample.startDate, end: sample.endDate, sources: [source], sampleCount: 1)))
            }
        }
    }
    private func readSleep(in window: DateInterval) async throws -> PatrickHealthReading? {
        let type = HKCategoryType(.sleepAnalysis)
        // Keep crossing-midnight samples; the interval union clips both ends.
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: [])
        return try await execute { finish in
            HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { finish(.failure(error)); return }
                let samples: [PatrickSleepInterval] = (results as? [HKCategorySample] ?? []).map { sample in
                    let asleep = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                        HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                        HKCategoryValueSleepAnalysis.asleepREM.rawValue].contains(sample.value)
                    let source = PatrickHealthSource(name: sample.sourceRevision.source.name,
                        bundleID: sample.sourceRevision.source.bundleIdentifier, deviceName: sample.device?.name)
                    return PatrickSleepInterval(id: sample.uuid, start: sample.startDate, end: sample.endDate, asleep: asleep, source: source)
                }
                finish(.success(PatrickSleepSummary.reading(samples, in: window)))
            }
        }
    }
}

@MainActor struct PatrickHealthPanel: View {
    @StateObject private var reader = PatrickHealthReader()
    @State private var visible = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var wristDown
    var onStartBreathing: (() -> Void)? = nil
    var body: some View {
        List {
            selectionSection
            readSection
            resultsSection
            restSection
            privacySection
        }
        .navigationTitle("健康摘要")
        .onAppear { visible = true; resumePresentation() }
        .onDisappear { visible = false; reader.setPresentationActive(false) }
        .onChange(of: scenePhase) { _, phase in
            // A permission sheet can make the app inactive; preserve that explicit request.
            if phase == .background { reader.setPresentationActive(false) }
            else if phase == .active { resumePresentation() }
        }
        .onChange(of: wristDown) { _, down in
            if down { reader.setPresentationActive(false) } else { resumePresentation() }
        }
    }
    private var selectionSection: some View {
        Section("只選想看的項目") {
            ForEach(PatrickHealthMetric.allCases) { metric in
                Toggle(metric.title, isOn: Binding(get: { reader.selected.contains(metric) },
                    set: { reader.setSelected(metric, enabled: $0) }))
            }
            Toggle("開頁刷新已選項", isOn: Binding(get: { reader.autoRefreshOnOpen }, set: reader.setAutomatic))
            Text("只刷新你曾主動請求的項目；不自動彈權限視窗。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var readSection: some View {
        Section("本機讀取") {
            Button(reader.busy ? "讀取中…" : "授權並讀取所選項目") { Task { await reader.requestAndRead() } }
                .disabled(reader.busy || reader.selected.isEmpty)
            Button("重新整理，不詢問權限") { Task { await reader.refreshSelectedWithoutPrompt() } }
                .disabled(reader.busy || reader.selected.isEmpty)
            Button("清除本頁數值") { reader.clearDisplayedData() }
            Text(reader.message).font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var resultsSection: some View {
        Section("資料與來源") {
            ForEach(PatrickHealthMetric.allCases.filter { reader.selected.contains($0) }) { metric in metricResult(metric) }
            if let date = reader.refreshedAt {
                Text("整理時間：\(date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    @ViewBuilder private func metricResult(_ metric: PatrickHealthMetric) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(metric.title).font(.headline)
            switch reader.results[metric] {
            case .reading(let value):
                Text("\(metric.formatted(value.value)) \(metric.unit)")
                Text(value.isAggregate ? "統計區間" : "樣本時間").font(.caption)
                Text(value.interval.start.formatted(date: .abbreviated, time: .shortened)).font(.caption)
                if value.interval.duration > 0 {
                    Text("至 \(value.interval.end.formatted(date: .abbreviated, time: .shortened))").font(.caption)
                }
                ForEach(value.sources, id: \.self) { source in Text("來源：\(source.label)").font(.caption) }
                if value.sources.isEmpty { Text("來源未由 HealthKit 回傳").font(.caption) }
                if metric == .sleep, let count = value.sampleCount {
                    Text("\(count) 筆睡眠時段，跨來源重疊只計一次。這不是健康 App 的完整夜間分期報告。")
                        .font(.caption)
                }
            case .noSamples:
                Text(metric == .steps ? "今日尚無可讀資料" : metric == .sleep ? "近 24 小時尚無可讀睡眠" : "最近 7 日尚無可讀資料")
            case .unavailable: Text("本次讀取未完成，可重試")
            case nil: Text("尚未讀取")
            }
            Text(metric.note).font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var restSection: some View {
        if let onStartBreathing {
            Section("照自己的感受休息") {
                Text("想停一停時，可以主動安排一分鐘呼吸休息。無需達到任何健康數字。")
                    .font(.footnote)
                Button("呼吸休息 1 分鐘") { reader.clearDisplayedData(); onStartBreathing() }
            }
        }
    }
    private var privacySection: some View {
        Section("資料留在這裡") {
            Text("只讀取你選擇的資料；不寫入健康、不跨裝置傳送數值、不上傳，也不依數值自動改心情。")
            Text("沒有樣本時無法分辨未授權、同步未完成或尚無紀錄。離頁、背景或改選會清掉本頁數值；只記住選項。")
        }.font(.footnote).foregroundStyle(.secondary)
    }
    private func resumePresentation() {
        guard visible, scenePhase == .active, !wristDown else { return }
        reader.setPresentationActive(true)
        if reader.autoRefreshOnOpen { Task { await reader.refreshSelectedWithoutPrompt() } }
    }
}
