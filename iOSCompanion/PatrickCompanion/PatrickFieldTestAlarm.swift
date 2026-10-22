import Foundation

#if canImport(AlarmKit)
import AlarmKit
import SwiftUI
#endif

/// Schedules one AlarmKit alarm two minutes ahead and, on a later launch,
/// writes down whatever the system still tells us.
@MainActor
enum PatrickFieldTestAlarm {
    static func scheduleTwoMinutes() async -> String {
        guard PatrickFieldTestGate.isEnabled() else {
            return note("实测入口是关的，没有预约闹钟。", topic: "闹钟")
        }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await PatrickFieldTestAlarmKit.schedule()
        }
        return note("这台系统低于 iOS 26，没有 AlarmKit。最低系统仍是 iOS 17。", topic: "闹钟")
        #else
        return note("编译这个包的 SDK 没有 AlarmKit。", topic: "闹钟")
        #endif
    }

    /// Called once per process, the first time the app becomes active.
    /// Does nothing when nobody has scheduled a field-test alarm.
    static func noteLaunch() {
        guard PatrickFieldTestAlarmRecord.load() != nil else { return }
        Task {
            _ = await reconcile(reason: "下次启动", logIfUnchanged: true)
        }
    }

    static func reconcile(reason: String, logIfUnchanged: Bool) async -> String {
        guard let record = PatrickFieldTestAlarmRecord.load() else {
            return note("没有实测闹钟记录。", topic: "闹钟")
        }
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            return await PatrickFieldTestAlarmKit.reconcile(
                record: record,
                reason: reason,
                logIfUnchanged: logIfUnchanged
            )
        }
        #endif
        return note(
            "\(reason)：记录还在，但这台系统读不了 AlarmKit。预约于 \(stamp(record.scheduledAt))，预定响铃 \(stamp(record.fireAt))。",
            topic: "闹钟"
        )
    }

    static func note(_ message: String, topic: String) -> String {
        PatrickFieldTestLog.append(message, topic: topic)
        return message
    }

    static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}

#if canImport(AlarmKit)
@available(iOS 26.0, *)
@MainActor
private enum PatrickFieldTestAlarmKit {
    static func schedule() async -> String {
        do {
            var auth = AlarmManager.shared.authorizationState
            if auth == .notDetermined {
                auth = try await AlarmManager.shared.requestAuthorization()
            }
            guard auth == .authorized else {
                return PatrickFieldTestAlarm.note(
                    "闹钟授权不是允许（\(auth)）。没有预约。",
                    topic: "闹钟"
                )
            }
            let id = UUID()
            let scheduledAt = Date()
            let fireAt = scheduledAt.addingTimeInterval(120)
            let stop = AlarmButton(
                text: "停止",
                textColor: .white,
                systemImageName: "stop.circle"
            )
            let alert = AlarmPresentation.Alert(title: "实测闹钟", stopButton: stop)
            let attributes = AlarmAttributes<PatrickFieldTestAlarmMetadata>(
                presentation: AlarmPresentation(alert: alert),
                tintColor: .pink
            )
            let configuration = AlarmManager.AlarmConfiguration<PatrickFieldTestAlarmMetadata>(
                schedule: .fixed(fireAt),
                attributes: attributes
            )
            let alarm = try await AlarmManager.shared.schedule(id: id, configuration: configuration)
            let state = String(describing: alarm.state)
            var record = PatrickFieldTestAlarmRecord(
                id: alarm.id.uuidString,
                scheduledAt: scheduledAt,
                fireAt: fireAt,
                lastState: state,
                sawAlerting: state.lowercased().contains("alert")
            )
            record.save()
            return PatrickFieldTestAlarm.note(
                "已预约。id=\(record.id) 状态 \(state)。写下预约时间 \(PatrickFieldTestAlarm.stamp(scheduledAt))，预定响铃 \(PatrickFieldTestAlarm.stamp(fireAt))。请把静音开关打开再看一次，AlarmKit 设计上会穿过静音，这里只记录，不当成已经响过。免费账号签名大约 7 天后失效；失效后重签再打开，看「下次启动」那一行能不能判断它响过。推送没有做。",
                topic: "闹钟"
            )
        } catch {
            return PatrickFieldTestAlarm.note("预约失败。\(error.localizedDescription)", topic: "闹钟")
        }
    }

    static func reconcile(
        record: PatrickFieldTestAlarmRecord,
        reason: String,
        logIfUnchanged: Bool
    ) async -> String {
        var record = record
        let alarms = AlarmManager.shared.alarms
        let match = alarms.first { $0.id.uuidString == record.id }
        let now = Date()
        let message: String
        if let match {
            let state = String(describing: match.state)
            let saw = record.sawAlerting || state.lowercased().contains("alert")
            let changed = state != record.lastState || saw != record.sawAlerting
            record.lastState = state
            record.sawAlerting = saw
            record.save()
            if !logIfUnchanged && !changed {
                return "状态没变：\(state)"
            }
            message = "\(reason)：闹钟还在。状态 \(state)。\(saw ? "见过响起中的状态。" : "还没见过响起中的状态。")预约 \(PatrickFieldTestAlarm.stamp(record.scheduledAt))，预定响铃 \(PatrickFieldTestAlarm.stamp(record.fireAt))，这次查看 \(PatrickFieldTestAlarm.stamp(now))。"
        } else if now >= record.fireAt {
            message = "\(reason)：预定时间已过，列表里没有这只闹钟。系统没有单独告诉我它响过没有。上次记下的状态是 \(record.lastState)。\(record.sawAlerting ? "之前见过响起中，先记成响过。" : "之前没见过响起中，不能分辨是响完被关掉，还是签名过期后被系统清掉。")预约 \(PatrickFieldTestAlarm.stamp(record.scheduledAt))，预定响铃 \(PatrickFieldTestAlarm.stamp(record.fireAt))，这次查看 \(PatrickFieldTestAlarm.stamp(now))。"
        } else {
            message = "\(reason)：还没到点，可是列表里没有这只闹钟。预约 \(PatrickFieldTestAlarm.stamp(record.scheduledAt))，预定响铃 \(PatrickFieldTestAlarm.stamp(record.fireAt))。"
        }
        return PatrickFieldTestAlarm.note(message, topic: "闹钟")
    }
}

@available(iOS 26.0, *)
private struct PatrickFieldTestAlarmMetadata: AlarmMetadata {}
#endif
