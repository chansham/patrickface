import AppIntents
import Foundation

enum PatrickRoutineStepChoice: String, AppEnum, Sendable {
    case focus = "sleep-focus", alarm = "existing-alarm", patrick = "patrick-state", home = "home-scene"
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "晚安步驟")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .focus: "睡眠專注", .alarm: "指定鬧鐘", .patrick: "派大星睡前狀態", .home: "晚安燈光"
    ]
    var stepID: PatrickRoutineRun.StepID { PatrickRoutineRun.StepID(rawValue: rawValue)! }
}
enum PatrickRoutineOutcomeChoice: String, AppEnum, Sendable {
    case succeeded, failed, skipped
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "步驟結果")
    static var caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .succeeded: "已完成", .failed: "未完成", .skipped: "未選用"
    ]
    var status: PatrickRoutineRun.Status { PatrickRoutineRun.Status(rawValue: rawValue)! }
}
enum PatrickRoutineIntentError: Error, LocalizedError {
    case missingRun, invalidReceipt, notRetryable, useLocalAction
    var errorDescription: String? {
        switch self {
        case .missingRun: "找不到這次流程。請先開始晚安流程紀錄，並傳入它回傳的編號。"
        case .invalidReceipt: "回報未採用：步驟可能已結束，或重試次數不相符。已完成的步驟保持原結果。"
        case .notRetryable: "這一步不是失敗狀態，或已達重試上限。尚無回報的步驟不會自動重做。"
        case .useLocalAction: "請使用「執行晚安中的派大星步驟」，由 App 實際套用後記錄結果。"
        }
    }
}

struct BeginPatrickRoutineIntent: AppIntent {
    static var title: LocalizedStringResource = "開始晚安流程紀錄"
    static var description = IntentDescription("放在組合捷徑最前面，將回傳的流程編號傳給後續動作。只開始紀錄，不切換專注、不設定鬧鐘。")
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let id = await PatrickRoutineExecutor.begin()
        return .result(value: id.uuidString)
    }
}

struct RecordPatrickRoutineStepIntent: AppIntent {
    static var title: LocalizedStringResource = "回報晚安步驟結果"
    static var description = IntentDescription("接在系統動作之後，紀錄捷徑提供的結果；沒有回報會保持未知。不獨立驗證 Focus、鬧鐘或手錶。重試後請傳入新的次數，不能將派大星步驟直接標為成功。")
    static var openAppWhenRun = false
    @Parameter(title: "流程編號") var executionID: String
    @Parameter(title: "步驟") var step: PatrickRoutineStepChoice
    @Parameter(title: "結果") var outcome: PatrickRoutineOutcomeChoice
    @Parameter(title: "執行次數", default: 1) var attempt: Int
    @Parameter(title: "說明", default: "") var note: String
    static var parameterSummary: some ParameterSummary {
        Summary("回報\(\.$executionID)的\(\.$step)：\(\.$outcome)") { \.$attempt; \.$note }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = try await PatrickRoutineExecutor.report(executionID, step: step.stepID,
            status: outcome.status, attempt: attempt, note: note)
        return .result(value: summary)
    }
}

struct ApplyPatrickGoodnightStepIntent: AppIntent {
    static var title: LocalizedStringResource = "執行晚安中的派大星步驟"
    static var description = IntentDescription("套用 App 睡前狀態並記錄本機結果。保留衣服、計時及音效偏好；不是手錶已收到的證明。同一次成功步驟不會重做。")
    static var openAppWhenRun = false
    @Parameter(title: "流程編號") var executionID: String
    @Parameter(title: "執行次數", default: 1) var attempt: Int
    static var parameterSummary: some ParameterSummary {
        Summary("執行\(\.$executionID)的派大星睡前步驟") { \.$attempt }
    }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = try await PatrickRoutineExecutor.applyPatrick(executionID, attempt: attempt)
        return .result(value: summary)
    }
}

struct PreparePatrickRoutineRetryIntent: AppIntent {
    static var title: LocalizedStringResource = "準備重試晚安失敗步驟"
    static var description = IntentDescription("只為選定的失敗步驟建立下一次回報編號。將回傳次數傳給後續執行與回報動作；這個動作本身不執行系統設定，亦不重做成功步驟。")
    static var openAppWhenRun = false
    @Parameter(title: "流程編號") var executionID: String
    @Parameter(title: "失敗步驟") var step: PatrickRoutineStepChoice
    static var parameterSummary: some ParameterSummary { Summary("準備重試\(\.$executionID)的\(\.$step)") }
    func perform() async throws -> some IntentResult & ReturnsValue<Int> {
        let attempt = try await PatrickRoutineExecutor.retry(executionID, step: step.stepID)
        return .result(value: attempt)
    }
}

struct ReadPatrickRoutineResultIntent: AppIntent {
    static var title: LocalizedStringResource = "讀取晚安流程結果"
    static var description = IntentDescription("回傳每步已收到的結果。捷徑中途停止時，沒有回報的步驟仍顯示尚無回報。")
    static var openAppWhenRun = false
    @Parameter(title: "流程編號") var executionID: String
    static var parameterSummary: some ParameterSummary { Summary("讀取\(\.$executionID)的晚安結果") }
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let summary = try await PatrickRoutineExecutor.result(executionID)
        return .result(value: summary)
    }
}

@MainActor enum PatrickRoutineExecutor {
    static func begin() -> UUID { PatrickRoutineStore.shared.start().id }
    private static func run(_ id: String) throws -> PatrickRoutineRun {
        guard let uuid = UUID(uuidString: id), let run = PatrickRoutineStore.shared.load().first(where: { $0.id == uuid })
        else { throw PatrickRoutineIntentError.missingRun }
        return run
    }
    static func result(_ id: String) throws -> String {
        let run = try run(id)
        let steps = run.steps.map { step in
            let status: String
            switch step.status { case .pending: status = "尚無回報"; case .succeeded: status = "已回報完成"; case .failed: status = "未完成"; case .skipped: status = "未選用" }
            return "\(step.stepID.title)：\(status)"
        }.joined(separator: "；")
        return run.summary + "。" + steps + "。手錶專注與派大星狀態尚未確認。"
    }
    static func report(_ id: String, step: PatrickRoutineRun.StepID, status: PatrickRoutineRun.Status,
                       attempt: Int, note: String) throws -> String {
        guard step != .patrick else { throw PatrickRoutineIntentError.useLocalAction }
        let run = try run(id)
        let receipt = PatrickRoutineRun.Receipt(receiptID: UUID(), executionID: run.id, stepID: step,
            attempt: attempt, status: status, source: .shortcut, note: String(note.prefix(240)),
            receivedAtMS: Date.now.timeIntervalSince1970 * 1000)
        var outcome = PatrickRoutineRun.ApplyResult.invalid
        guard PatrickRoutineStore.shared.update(id: run.id, { outcome = $0.apply(receipt) }) != nil
        else { throw PatrickRoutineIntentError.invalidReceipt }
        // Identical retries are harmless; conflicting settled results stay visible.
        if outcome == .alreadyResolved,
           let existing = run.steps.first(where: { $0.stepID == step }),
           existing.attempt == attempt, existing.status == status { return try result(id) }
        guard outcome == .applied else { throw PatrickRoutineIntentError.invalidReceipt }
        return try result(id)
    }
    static func applyPatrick(_ id: String, attempt: Int) throws -> String {
        let run = try run(id)
        guard let step = run.steps.first(where: { $0.stepID == .patrick }), step.attempt == attempt
        else { throw PatrickRoutineIntentError.invalidReceipt }
        if step.status == .succeeded { return try result(id) }
        guard step.status == .pending else { throw PatrickRoutineIntentError.invalidReceipt }
        let settings = PatrickIntentExecutor.setSleepMode(.on)
        let status: PatrickRoutineRun.Status = settings.sleepMode == .on ? .succeeded : .failed
        let receipt = PatrickRoutineRun.Receipt(receiptID: UUID(), executionID: run.id, stepID: .patrick,
            attempt: attempt, status: status, source: .localApp,
            note: "iPhone App 已套用；手錶尚未確認。", receivedAtMS: Date.now.timeIntervalSince1970 * 1000)
        var outcome = PatrickRoutineRun.ApplyResult.invalid
        guard PatrickRoutineStore.shared.update(id: run.id, { outcome = $0.apply(receipt) }) != nil
        else { throw PatrickRoutineIntentError.invalidReceipt }
        guard outcome == .applied else { throw PatrickRoutineIntentError.invalidReceipt }
        return try result(id)
    }
    static func retry(_ id: String, step: PatrickRoutineRun.StepID) throws -> Int {
        let run = try run(id)
        var attempt: Int?
        guard PatrickRoutineStore.shared.update(id: run.id, { attempt = $0.retry(step) }) != nil
        else { throw PatrickRoutineIntentError.notRetryable }
        guard let attempt else { throw PatrickRoutineIntentError.notRetryable }
        return attempt
    }
}
