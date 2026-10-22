import BackgroundTasks
import Foundation

/// Registers a background-refresh task. Nothing is submitted until the
/// field-test screen asks. The handler refuses to start an activity when the
/// hidden switch is off.
enum PatrickFieldTestBackground {
    static let identifier = "com.chans.patrickface.companion.fieldtest.refresh"
    private static var didRegister = false

    static func register() {
        guard !didRegister else { return }
        didRegister = true
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            guard let refresh = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            let job = Task {
                _ = await PatrickFieldTestStarter.start(origin: "background-refresh")
            }
            refresh.expirationHandler = {
                job.cancel()
                PatrickFieldTestLog.append("后台刷新被系统中途停掉。", topic: "后台刷新")
            }
            Task {
                await job.value
                refresh.setTaskCompleted(success: true)
            }
        }
    }

    static func scheduleSoon() -> String {
        guard PatrickFieldTestGate.isEnabled() else {
            return PatrickFieldTestLog.append(
                "实测入口是关的，没有提交后台刷新。",
                topic: "后台刷新"
            ).message
        }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date().addingTimeInterval(60)
        do {
            try BGTaskScheduler.shared.submit(request)
            return PatrickFieldTestLog.append(
                "已提交后台刷新，最早大约 1 分钟后。系统自己决定什么时候跑，可能要很久。把 App 划到后台，并打开「设置 → 通用 → 后台 App 刷新」。跑完再打开实测页看记录。这一条只试本地开始实时活动，不是推送。",
                topic: "后台刷新"
            ).message
        } catch {
            return PatrickFieldTestLog.append(
                "提交后台刷新失败。\(error.localizedDescription)",
                topic: "后台刷新"
            ).message
        }
    }
}
