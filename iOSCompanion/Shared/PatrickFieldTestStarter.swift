import ActivityKit
import Foundation

struct PatrickFieldTestActivityAttributes: ActivityAttributes, Sendable {
    struct ContentState: Codable, Hashable, Sendable {
        var sequence: Int
        var label: String
    }

    var kind: String
    var startedAt: Date
}

/// Local Live Activity operations for the hidden field-test screen.
/// Production timer activities use a different attributes type and are left alone.
@MainActor
enum PatrickFieldTestStarter {
    static func start(origin: String) async -> String {
        guard PatrickFieldTestGate.isEnabled() else {
            return log("来源 \(origin)：实测入口是关的，没有开始实时活动。", topic: "实时活动")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return log("来源 \(origin)：系统设置里的实时活动是关的。", topic: "实时活动")
        }
        let attributes = PatrickFieldTestActivityAttributes(kind: origin, startedAt: Date())
        let state = PatrickFieldTestActivityAttributes.ContentState(sequence: 0, label: origin)
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil
            )
            return log(
                "来源 \(origin)：本地开始成功。id=\(activity.id) 序号 0 状态 \(activity.activityState)。没有用推送。",
                topic: "实时活动"
            )
        } catch {
            return log(
                "来源 \(origin)：本地开始失败。\(error.localizedDescription)",
                topic: "实时活动"
            )
        }
    }

    /// Asks ActivityKit to show a field-test activity about two minutes from now.
    /// Uses the iOS 26 scheduled-start call. The app's minimum system stays iOS 17.
    static func scheduleTwoMinutesAhead() -> String {
        guard PatrickFieldTestGate.isEnabled() else {
            return log("预定实时活动：实测入口是关的，没有提交。", topic: "预定实时活动")
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return log("预定实时活动：系统设置里的实时活动是关的。", topic: "预定实时活动")
        }
        if #available(iOS 26.0, *) {
            return scheduleAvailable()
        }
        return log("这台系统低于 iOS 26，没有预定开始接口。最低系统仍是 iOS 17。", topic: "预定实时活动")
    }

    @available(iOS 26.0, *)
    private static func scheduleAvailable() -> String {
        let scheduledAt = Date()
        let start = scheduledAt.addingTimeInterval(120)
        let attributes = PatrickFieldTestActivityAttributes(kind: "scheduled", startedAt: scheduledAt)
        let state = PatrickFieldTestActivityAttributes.ContentState(sequence: 0, label: "预定")
        let alert = AlertConfiguration(
            title: "实测",
            body: "预定的实时活动到点了",
            sound: .default
        )
        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: nil),
                pushType: nil,
                style: .standard,
                alertConfiguration: alert,
                start: start
            )
            let formatter = ISO8601DateFormatter()
            return log(
                "已提交预定。id=\(activity.id) 状态 \(activity.activityState) 开始时间 \(formatter.string(from: start))。请锁屏等两分钟，看它会不会自己出现。没有用推送。",
                topic: "预定实时活动"
            )
        } catch {
            return log("预定失败。\(error.localizedDescription)", topic: "预定实时活动")
        }
    }

    static func runRapid(interval: TimeInterval) async {
        guard PatrickFieldTestGate.isEnabled() else {
            log("快速更新：实测入口是关的，没有开始。", topic: "实时活动")
            return
        }
        let plan = PatrickFieldTestRapidPlan.sequences(interval: interval)
        let label = "每\(Int(interval))秒"
        log(
            "\(label) 这一轮准备发送序号 \(plan.first.map(String.init) ?? "0")…\(plan.last.map(String.init) ?? "0")，共 \(plan.count) 次。没有打开更频繁的实时活动权限，系统可能把靠得太近的更新并掉。屏幕上的数字才是留下来的那一次。",
            topic: "实时活动"
        )
        await endFieldTests()
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("快速更新：系统设置里的实时活动是关的。", topic: "实时活动")
            return
        }
        let attributes = PatrickFieldTestActivityAttributes(kind: label, startedAt: Date())
        guard let first = plan.first else { return }
        let opening = PatrickFieldTestActivityAttributes.ContentState(sequence: first, label: label)
        let activity: Activity<PatrickFieldTestActivityAttributes>
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: opening, staleDate: nil),
                pushType: nil
            )
        } catch {
            log("快速更新没有开始。\(error.localizedDescription)", topic: "实时活动")
            return
        }
        log("已发送序号 \(first)。id=\(activity.id) 状态 \(activity.activityState)。", topic: "实时活动")
        for sequence in plan.dropFirst() {
            if Task.isCancelled {
                log("快速更新被停掉。最后发出的序号见上一条。", topic: "实时活动")
                return
            }
            try? await Task.sleep(for: .seconds(interval))
            if Task.isCancelled { return }
            let state = PatrickFieldTestActivityAttributes.ContentState(sequence: sequence, label: label)
            await activity.update(ActivityContent(state: state, staleDate: nil))
            log(
                "已发送序号 \(sequence)。活动状态 \(activity.activityState)。这只说明发出去了，不说明锁屏上已经画出这个数字。",
                topic: "实时活动"
            )
        }
        log(
            "\(label) 发送结束。请看实时活动上的数字，再按「记下我看见的数字」。两条对得上，才算这一号真的出现了。",
            topic: "实时活动"
        )
    }

    static func endFieldTests() async {
        let activities = Activity<PatrickFieldTestActivityAttributes>.activities
        guard !activities.isEmpty else { return }
        for activity in activities {
            let state = activity.content.state
            await activity.end(ActivityContent(state: state, staleDate: nil), dismissalPolicy: .immediate)
        }
        log("结束了 \(activities.count) 条实测实时活动。陪伴计时那条没有动。", topic: "实时活动")
    }

    static func describeFieldTests() -> String {
        let activities = Activity<PatrickFieldTestActivityAttributes>.activities
        if activities.isEmpty {
            return log("现在没有实测实时活动。", topic: "实时活动")
        }
        let parts = activities.map { activity in
            "id=\(activity.id) 状态 \(activity.activityState) 序号 \(activity.content.state.sequence) 标签 \(activity.content.state.label)"
        }
        return log(parts.joined(separator: " | "), topic: "实时活动")
    }

    @discardableResult
    private static func log(_ message: String, topic: String) -> String {
        PatrickFieldTestLog.append(message, topic: topic)
        return message
    }
}
