import AppIntents
import SwiftUI
import UIKit
import UserNotifications

/// Hidden field-test page. Normal tabs never present this.
struct PatrickFieldTestScreen: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var model: AppModel
    @State private var logText = ""
    @State private var seenNumber = 0
    @State private var rapidTask: Task<Void, Never>?
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section("记录") {
                    Text(logText.isEmpty ? "还没有记录。" : logText)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    ShareLink(item: logText.isEmpty ? "还没有记录。" : logText) {
                        Label("分享记录", systemImage: "square.and.arrow.up")
                    }
                    Button("复制记录") {
                        UIPasteboard.general.string = logText
                    }
                    Button("清空记录", role: .destructive) {
                        PatrickFieldTestLog.clear()
                        reload()
                    }
                    Button("刷新记录") { reload() }
                }

                Section("1. 实时活动快速更新") {
                    Text("本地更新，不用推送。活动上的大数字是系统留下的最新序号。记录里是发出去的序号。看完按下面的按钮，把眼睛看见的数字写进记录。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    rapidButton("每 1 秒，持续 30 秒", interval: 1)
                    rapidButton("每 2 秒，持续 30 秒", interval: 2)
                    rapidButton("每 5 秒，持续 30 秒", interval: 5)
                    Stepper("我看见的数字：\(seenNumber)", value: $seenNumber, in: 0...999)
                    Button("记下我看见的数字") {
                        PatrickFieldTestLog.append("眼睛看见的序号是 \(seenNumber)。", topic: "实时活动")
                        reload()
                    }
                    Button("看看现在的实测实时活动") {
                        _ = PatrickFieldTestStarter.describeFieldTests()
                        reload()
                    }
                    Button("结束实测实时活动") {
                        Task {
                            await PatrickFieldTestStarter.endFieldTests()
                            reload()
                        }
                    }
                    .disabled(busy)
                }

                Section("2. 锁屏控件") {
                    Text("iOS 18 以上：到控制中心或锁屏，添加「实测开关」和「实测开始实时活动」。点开关会写一条记录。入口关掉时不会记住开关。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("3. 从后台开始实时活动") {
                    Text("推送启动（push-to-start）要 APNs，免费 Apple 账号没有推送权限，这里不做。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("从控件试一次") {
                        Task {
                            _ = await PatrickFieldTestStarter.start(origin: "control-widget-manual")
                            reload()
                        }
                    }
                    Text("锁屏上的「实测开始实时活动」走的是同一个控件意图。捷径里搜「实测：从捷径开始实时活动」或「实测：从控件开始实时活动」。没有加进原来的十个快捷短语。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("提交一次后台刷新") {
                        _ = PatrickFieldTestBackground.scheduleSoon()
                        reload()
                    }
                }

                Section("4. 预定两分钟后的实时活动") {
                    Text("用 iOS 26 的预定开始。系统低于 26 时只写一条做不到，不改最低系统。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("预定 2 分钟后开始") {
                        _ = PatrickFieldTestStarter.scheduleTwoMinutesAhead()
                        reload()
                    }
                }

                Section("5. 两分钟后的闹钟") {
                    Text("iOS 26 的 AlarmKit。请另测一次：静音开关打开。免费账号签名大约 7 天后失效，失效后重签再打开这个 App，看记录里的「下次启动」能不能判断它响过。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("预约 2 分钟后的闹钟") {
                        Task {
                            _ = await PatrickFieldTestAlarm.scheduleTwoMinutes()
                            reload()
                        }
                    }
                    Button("现在核对闹钟") {
                        Task {
                            _ = await PatrickFieldTestAlarm.reconcile(reason: "手动核对", logIfUnchanged: true)
                            reload()
                        }
                    }
                }

                Section("6. 待机夜间红色") {
                    Text("添加小组件「实测夜览」，放进待机。夜间模式会把强调色染成红的。看派大星变成什么样。这个小组件只画图。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("7. 通知扩展内存") {
                    Text("默认安装包不带这个扩展，免得多占一个免费 App ID。展开通知时如果没有小动画，就是没打进去。打开构建开关再签名才会出现，并多占 1 个 App ID。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("发一条带动画类别的本地通知") {
                        Task { await scheduleAnimationNotification() }
                    }
                }

                Section("8. 手表") {
                    Text("问一句配对的手表。它只回系统版本，不改角色。免费账号现在签不上手表时，这里会失败，这是预期。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("问手表") {
                        model.watchSync.sendFieldTestPing()
                        reload()
                    }
                }

                Section {
                    Button("关掉实测入口", role: .destructive) {
                        PatrickFieldTestGate.setEnabled(false)
                        dismiss()
                    }
                }
            }
            .navigationTitle("实测")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            PatrickFieldTestLog.append("打开了实测页。", topic: "页面")
            reload()
        }
        .task(id: busy) {
            guard busy else { return }
            while !Task.isCancelled && busy {
                reload()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func rapidButton(_ title: String, interval: TimeInterval) -> some View {
        Button(title) {
            rapidTask?.cancel()
            busy = true
            rapidTask = Task {
                await PatrickFieldTestStarter.runRapid(interval: interval)
                busy = false
                reload()
            }
        }
        .disabled(busy)
    }

    private func reload() {
        logText = PatrickFieldTestLog.exportText()
    }

    private func scheduleAnimationNotification() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
            PatrickFieldTestLog.append(
                granted ? "通知授权是允许。" : "通知授权没有给。",
                topic: "通知扩展"
            )
        } else if settings.authorizationStatus != .authorized && settings.authorizationStatus != .provisional {
            PatrickFieldTestLog.append("通知授权不是允许，发不出去。", topic: "通知扩展")
            reload()
            return
        }
        let category = UNNotificationCategory(
            identifier: PatrickFieldTestNotificationKind.categoryID,
            actions: [],
            intentIdentifiers: []
        )
        let existing = await center.notificationCategories()
        center.setNotificationCategories(existing.union([category]))
        let content = UNMutableNotificationContent()
        content.title = "实测动画"
        content.body = "长按或展开，看小动画和剩余内存。默认安装包没有扩展。"
        content.categoryIdentifier = PatrickFieldTestNotificationKind.categoryID
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false)
        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: "patrick.fieldtest.animation.\(UUID().uuidString)",
                    content: content,
                    trigger: trigger
                )
            )
            PatrickFieldTestLog.append(
                "两秒后会有一条本地通知。默认包没有通知扩展，展开后不会播动画，也没有扩展内存数字。要测内存，把 PATRICK_FIELD_TEST_NOTIFICATION_EXTENSION 设成 YES 再签名。那会从 4 个 App ID 变成 5 个。免费账号 7 天内上限 10 个。",
                topic: "通知扩展"
            )
        } catch {
            PatrickFieldTestLog.append("通知没发出去。\(error.localizedDescription)", topic: "通知扩展")
        }
        reload()
    }
}

/// Not one of the ten suggested shortcuts. Shortcuts can still find it by name.
struct PatrickFieldTestShortcutStartIntent: AppIntent {
    static var title: LocalizedStringResource = "实测：从捷径开始实时活动"
    static var description = IntentDescription("隐藏实测。入口关掉时不会开始实时活动。")
    static var openAppWhenRun = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = await PatrickFieldTestStarter.start(origin: "shortcut-siri")
        return .result(dialog: "\(line)")
    }
}
