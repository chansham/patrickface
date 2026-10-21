import SwiftUI
import HealthKit

/// Optional foreground reads only. No observer, workout, upload, WC or value persistence.
@MainActor final class PatrickHealthReader: ObservableObject {
    @Published private(set) var selected: Set<PatrickHealthMetric>
    @Published private(set) var autoRefreshOnOpen: Bool
    @Published private(set) var trendsEnabled: Bool
    @Published private(set) var results: [PatrickHealthMetric: PatrickHealthResult] = [:]
    @Published private(set) var trendGroups: [PatrickHealthTrendMetric: [PatrickHealthTrendSourceGroup]] = [:]
    @Published private(set) var trendFailures: Set<PatrickHealthTrendMetric> = []
    @Published private(set) var selectedTrendSources: [PatrickHealthTrendMetric: String] = [:]
    @Published private(set) var trendReadAt: Date?
    @Published private(set) var refreshedAt: Date?
    @Published private(set) var busy = false
    @Published private(set) var message = "先選擇想看的項目，再主動授權讀取。"
    private let store = HKHealthStore()
    private let preferences: UserDefaults
    private var previouslyRequested: Set<PatrickHealthMetric>
    private var gate = PatrickHealthReadGate()
    private var queries: [UUID: HKQuery] = [:]
    private var cancellations: [UUID: () -> Void] = [:]
    private var trendHistoryStart: Date?
    private static let selectionKey = "patrick.health.selected.v1"
    private static let requestedKey = "patrick.health.requested.v1"
    private static let automaticKey = "patrick.health.refresh-on-open.v1"
    private static let trendsKey = "patrick.health.trends-opt-in.v1"

    init(preferences: UserDefaults = .standard) {
        self.preferences = preferences
        selected = Set((preferences.stringArray(forKey: Self.selectionKey) ?? []).compactMap(PatrickHealthMetric.init(rawValue:)))
        previouslyRequested = Set((preferences.stringArray(forKey: Self.requestedKey) ?? []).compactMap(PatrickHealthMetric.init(rawValue:)))
        autoRefreshOnOpen = preferences.bool(forKey: Self.automaticKey)
        trendsEnabled = preferences.bool(forKey: Self.trendsKey)
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
    func setTrendsEnabled(_ value: Bool) {
        trendsEnabled = value
        preferences.set(value, forKey: Self.trendsKey)
        gate.invalidate(); clearQueriesAndValues()
        message = value ? "已開啟比較選項。下次按讀取，才查詢已選項目的近 28 天歷史。" : "已關閉比較並清除本頁歷史數值。"
    }
    func selectTrendSource(_ source: String, metric: PatrickHealthTrendMetric) {
        guard trendsEnabled, gate.active else { return }
        selectedTrendSources[metric] = source.isEmpty ? nil : source
    }
    func trendResult(for metric: PatrickHealthTrendMetric) -> PatrickHealthTrendResult? {
        guard trendsEnabled, let now = trendReadAt, let key = selectedTrendSources[metric],
              let group = trendGroups[metric]?.first(where: { $0.id == key && $0.comparable }),
              let historyStart = trendHistoryStart else { return nil }
        return PatrickHealthTrend.evaluate(PatrickHealthTrendInput(nowMS: PatrickHealthTrendAggregation.ms(now),
            historyStartMS: PatrickHealthTrendAggregation.ms(historyStart), points: group.points)).first { $0.metric == metric }
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
        let now = Date.now, calendar = Calendar.current
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
        if trendsEnabled {
            for metric in PatrickHealthTrendMetric.allCases where metrics.contains(Self.summaryMetric(for: metric)) {
                let summaryMetric = Self.summaryMetric(for: metric)
                guard gate.accepts(token, metric: summaryMetric), trendsEnabled else { return }
                do {
                    let groups = try await readTrend(metric, at: now, calendar: calendar)
                    guard gate.accepts(token, metric: summaryMetric), trendsEnabled else { return }
                    trendGroups[metric] = groups
                } catch {
                    guard gate.accepts(token, metric: summaryMetric), trendsEnabled else { return }
                    trendFailures.insert(metric)
                }
            }
            guard isCurrent(token), trendsEnabled else { return }
            trendHistoryStart = PatrickHealthTrendAggregation.historyWindow(at: now, calendar: calendar)?.start
            trendReadAt = now
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
        trendGroups.removeAll(); trendFailures.removeAll(); selectedTrendSources.removeAll(); trendReadAt = nil; trendHistoryStart = nil
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
    static func summaryMetric(for metric: PatrickHealthTrendMetric) -> PatrickHealthMetric {
        switch metric {
        case .sleepHours: .sleep
        case .restingHeartRate: .restingHeartRate
        case .hrvSDNN: .hrvSDNN
        }
    }
    private func readTrend(_ metric: PatrickHealthTrendMetric, at now: Date, calendar: Calendar) async throws -> [PatrickHealthTrendSourceGroup] {
        guard let window = PatrickHealthTrendAggregation.historyWindow(at: now, calendar: calendar) else { return [] }
        let type = Self.sampleType(for: Self.summaryMetric(for: metric))
        let predicate = HKQuery.predicateForSamples(withStart: window.start, end: now,
            options: metric == .sleepHours ? [] : .strictEndDate)
        return try await execute { finish in
            // No arbitrary cap: a truncated set must never masquerade as a daily median or baseline.
            HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                sortDescriptors: nil) { _, samples, error in
                if let error { finish(.failure(error)); return }
                finish(.success(PatrickHealthTrendSnapshot.groups(metric: metric,
                    samples: samples ?? [], now: now, calendar: calendar)))
            }
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
    @State private var feeling = "未選擇"
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var wristDown
    var onStartBreathing: (() -> Void)? = nil
    var body: some View {
        List {
            selectionSection
            readSection
            resultsSection
            trendSection
            restSection
            privacySection
        }
        .navigationTitle("健康摘要")
        .onAppear { visible = true; resumePresentation() }
        .onDisappear { visible = false; feeling = "未選擇"; reader.setPresentationActive(false) }
        .onChange(of: scenePhase) { _, phase in
            // A permission sheet can make the app inactive; preserve that explicit request.
            if phase == .background { feeling = "未選擇"; reader.setPresentationActive(false) }
            else if phase == .active { resumePresentation() }
        }
        .onChange(of: wristDown) { _, down in
            if down { feeling = "未選擇"; reader.setPresentationActive(false) } else { resumePresentation() }
        }
    }
    private var selectionSection: some View {
        Section("只選想看的項目") {
            ForEach(PatrickHealthMetric.allCases) { metric in
                Toggle(metric.title, isOn: Binding(get: { reader.selected.contains(metric) },
                    set: { feeling = "未選擇"; reader.setSelected(metric, enabled: $0) }))
            }
            Toggle("開頁刷新已選項", isOn: Binding(get: { reader.autoRefreshOnOpen }, set: reader.setAutomatic))
            Text("只刷新你曾主動請求的項目；不自動彈權限視窗。")
                .font(.footnote).foregroundStyle(.secondary)
            Toggle("比較自己的近期紀錄", isOn: Binding(get: { reader.trendsEnabled },
                set: { feeling = "未選擇"; reader.setTrendsEnabled($0) }))
            Text("預設關閉。開啟後，下次讀取會查近 28 天已選的睡眠、靜止心率與 HRV；只在本頁暫存。")
                .font(.footnote).foregroundStyle(.secondary)
        }
    }
    private var readSection: some View {
        Section("本機讀取") {
            Button(reader.busy ? "讀取中…" : "授權並讀取所選項目") { Task { await reader.requestAndRead() } }
                .disabled(reader.busy || reader.selected.isEmpty)
            Button("重新整理，不詢問權限") { Task { await reader.refreshSelectedWithoutPrompt() } }
                .disabled(reader.busy || reader.selected.isEmpty)
            Button("清除本頁數值") { feeling = "未選擇"; reader.clearDisplayedData() }
            Text(reader.message).font(.footnote).foregroundStyle(.secondary)
        }
    }
    @ViewBuilder private var trendSection: some View {
        if reader.trendsEnabled {
            Section("同一來源，和自己比較") {
                if let date = reader.trendReadAt {
                    Text("本次讀取快照：\(date.formatted(date: .abbreviated, time: .shortened))。新紀錄需重新整理；本頁不持續監測。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("只比較你選定的同一裝置來源；取近 28 天已完成日值的中位數，至少需要 7 日，不含本次窗口。缺少紀錄不補零。這是本 App 的比較方式，不是 Apple 基準或壓力評分。")
                    .font(.footnote).foregroundStyle(.secondary)
                ForEach(PatrickHealthTrendMetric.allCases, id: \.self) { metric in
                    if reader.selected.contains(PatrickHealthReader.summaryMetric(for: metric)) { trendMetric(metric) }
                }
            }
        }
    }
    @ViewBuilder private func trendMetric(_ metric: PatrickHealthTrendMetric) -> some View {
        let summary = PatrickHealthReader.summaryMetric(for: metric)
        VStack(alignment: .leading, spacing: 5) {
            Text(metric == .sleepHours ? "記錄到的睡眠時段"
                : metric == .hrvSDNN ? "HRV · 每日樣本中位值" : "靜止心率 · 每日樣本中位值").font(.headline)
            if reader.trendFailures.contains(metric) {
                Text("歷史讀取未完成；本次不比較，請重試。")
            } else if let groups = reader.trendGroups[metric] {
                if groups.isEmpty { Text("近 28 天沒有可用的非手動紀錄。無法由此判斷是否已授權。") }
                else {
                    Picker("選擇比較來源", selection: Binding(get: { reader.selectedTrendSources[metric] ?? "" },
                        set: { reader.selectTrendSource($0, metric: metric) })) {
                        Text("先選一個來源").tag("")
                        ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                            Text("\(index + 1). \(group.label)\(sourceDates(group))").tag(group.id)
                        }
                    }
                    if let key = reader.selectedTrendSources[metric], let group = groups.first(where: { $0.id == key }) {
                        Text("來源：\(group.label)").font(.caption)
                        Text("可讀記錄\(sourceDates(group))").font(.caption)
                        if let issue = group.issue {
                            switch issue {
                            case .missingDeviceIdentity: Text("缺少可區分裝置的識別，暫不跨日比較；不能把同型號當成同一隻手錶。")
                            case .invalidSamples: Text("這個來源包含格式或數值異常的紀錄，本次不比較；不會偷偷改用舊值。")
                            case .conflictingSampleID: Text("同一筆紀錄出現互相衝突的內容，本次不選其中一筆作比較。")
                            }
                        }
                        else if let result = reader.trendResult(for: metric) { trendComparison(result, summary: summary) }
                    }
                }
            } else { Text("開啟選項後，按上方讀取歷史。") }
            Text(metric == .sleepHours
                ? "以本地中午至翌日中午為一個記錄窗口；到中午才納入已結束窗口，不代表完整一夜，也不含臥床或清醒。"
                : "每天取可讀樣本中位數；當日截至樣本時間可能只有部分紀錄，與之前日值的量測時段、情境未必相同。數字升降不單獨表示健康好壞。")
                .font(.caption).foregroundStyle(.secondary)
            Text("排除標示為手動輸入的紀錄；未標示不等於已驗證為感測器量測。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func sourceDates(_ group: PatrickHealthTrendSourceGroup) -> String {
        guard let first = group.firstRecordedAt, let last = group.lastRecordedAt else { return " · 無可比較日期" }
        return " · \(first.formatted(date: .abbreviated, time: .omitted))–\(last.formatted(date: .abbreviated, time: .omitted))"
    }
    @ViewBuilder private func trendComparison(_ result: PatrickHealthTrendResult, summary: PatrickHealthMetric) -> some View {
        if let current = result.current {
            Text("\(result.metric == .sleepHours ? "本次記錄窗口" : "當日截至樣本時間")：\(trendNumber(current.value)) \(summary.unit)")
            Text("窗口：\(Date(timeIntervalSince1970: current.dayStartMS / 1000).formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
            Text("至 \(Date(timeIntervalSince1970: current.dayEndMS / 1000).formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
            Text("最後樣本：\(Date(timeIntervalSince1970: current.observedAtMS / 1000).formatted(date: .abbreviated, time: .shortened))")
                .font(.caption)
        }
        Text("基準資料：\(result.baselineCount) 日（至少 7 日）").font(.caption)
        switch result.state {
        case .ready:
            if let baseline = result.baseline, let delta = result.delta {
                Text("之前日值中位數：\(trendNumber(baseline)) \(summary.unit)")
                Text("相差：\(delta > 0 ? "+" : "")\(trendNumber(delta)) \(summary.unit)")
            }
        case .building: Text("同一來源的歷史日數還不夠，先累積紀錄。")
        case .stale: Text("在本次讀取時，最新可比較紀錄已超過 36 小時，這次不比較。")
        case .noData: Text("沒有可比較的日值；有衝突或不完整紀錄時也不猜測。")
        }
    }
    private func trendNumber(_ value: Double) -> String { String(format: "%.1f", value) }
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
                Picker("現在感覺", selection: $feeling) {
                    ForEach(["未選擇", "有點累", "還不錯", "說不準"], id: \.self) { Text($0).tag($0) }
                }
                Text(feeling == "有點累" ? "派大星陪你慢一點。想停一下的話，可以自己按一分鐘呼吸休息。"
                    : feeling == "還不錯" ? "那就照自己的節奏。想留一分鐘給自己，也可以休息一下。"
                    : "先聽自己的感受。想停一停時，可以主動安排一分鐘呼吸休息。")
                    .font(.footnote)
                Text("感受只留在這次頁面，不影響健康數字，也不會自動開始活動。")
                    .font(.caption).foregroundStyle(.secondary)
                Button("呼吸休息 1 分鐘") { feeling = "未選擇"; reader.clearDisplayedData(); onStartBreathing() }
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
