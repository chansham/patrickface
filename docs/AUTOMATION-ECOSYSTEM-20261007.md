# 鬧鐘、捷徑與雙端事件：2026-10-07

本輪交付的是明確事件入口：一個「回報派大星起床事件」捷徑動作，可選「鬧鐘已停止」或「我起床了」；兩端另有手動起床按鈕。它使用既有 `wake` 動作，保留衣服、作息、計時與照顧數值。背景只保存回報；畫面當下可見、訊息新鮮且允許動態才播放。沒有替使用者建立自動化、申請新權限或操作手機。

## Apple 能力與界限

查核使用 Apple 現行文件，並核对與本專案 SDK 世代相符的 iOS 26 捷徑指南。現行指南也列出 iOS 27；本次沒有把新的指南版本當成我們已編譯或真機驗證的版本。

| 需求 | 官方能力 | 本專案處理 |
|---|---|---|
| App 自己建立醒來鬧鐘 | AlarmKit 自 iOS／iPadOS 26.0 提供排程、重複、停止等能力；官方平台清單沒有 watchOS。每 App 要取得授權，需 `NSAlarmKitUsageDescription`。 | **尚未實作排程器**。現有專案紀錄的 Apple 建置環境為 SDK 26.5，具備這一代 API 不等於已接上、授權或測試。 |
| 自訂鬧鐘聲音 | AlarmKit 可用 ActivityKit 的 named sound，檔案放 main bundle 或 App 資料的 `Library/Sounds`。 | 現有短音效是前景回饋；未當成系統鬧鐘鈴聲。本輪不增加 AlarmKit 權限或偽造鬧鐘。 |
| 鬧鐘顯示於 Watch | Apple 說 AlarmKit 鬧鐘在響起時，已配對的 iPhone 可讓它顯示於 Apple Watch。 | 這是系統鬧鐘介面，不代表 Patrick Watch App 被打開、腕下常駐、播放逐幀人物，亦未查得自訂聲音必然在 Watch 原樣播放的保證。 |
| 攔截系統 Clock 的所有鬧鐘 | `AlarmManager.alarms` 只返回目前 client 的鬧鐘。 | 不讀 Clock 鬧鐘庫、不攔截其他 App，不更換系統停止畫面。使用者可另接 Clock 的捷徑事件。 |

上述依據：[AlarmKit 平台與功能](https://developer.apple.com/documentation/alarmkit)、[AlarmKit 授權文字](https://developer.apple.com/documentation/bundleresources/information-property-list/nsalarmkitusagedescription)、[Apple 的 AlarmKit 講解](https://developer.apple.com/videos/play/wwdc2025/230/)、[自訂音效檔案](https://developer.apple.com/documentation/activitykit/alertconfiguration/alertsound/named(_:))、[僅目前 client 的鬧鐘](https://developer.apple.com/documentation/alarmkit/alarmmanager/alarms)。Watch 的配對呈現及自訂聲音是兩項能力，不能由前者推定後者已受保證。

## 可由使用者建立的捷徑接法

這是日後裝置驗收的配方，未在使用者裝置執行。安裝 App 後的捷徑動作名稱、鎖屏是否允許、觸發成功與雙端收到時間仍要逐項實測。

| iPhone 自動化事件 | 接到本 App 的動作 | 必須保留的語義 |
|---|---|---|
| Clock「鬧鐘／已停止」：任何或指定鬧鐘 | 回報派大星起床事件 → 鬧鐘已停止 | 是捷徑回報，不是本 App 偵測、停止或修改該鬧鐘。 |
| 睡眠「起床」 | 回報派大星起床事件 → 我起床了 | 是設定的起床觸發，不证明人已醒；睡眠觸發需要已設定的睡眠時程。 |
| 睡眠「開始就寢」 | 設定派大星情境 → 睡前 | 明確設定場景；沒有讀取人的睡眠狀態。 |
| 所選 Focus 開／關 | 設定派大星情境 → 專注／依時間 | 任意 Focus 不等於睡覺；要由使用者選好对应場景。 |
| iPhone 充電器接上／拔下 | 設定派大星情境 → 充電小劇場／依時間 | 是手機充電事件，不偽裝成 Watch 充電感測；Watch 自身電池仍用原有裝置資料。 |
| Apple Watch Workout 開始／結束 | 設定情境或使用陪伴計時／控制陪伴計時 | 需已配對 Watch；本 App 倒數不等於建立、暫停或結束 Apple 健身訓練。 |
| iPhone 讀取已登記 NFC 標籤 | 照顧派大星、設定情境等已有動作 | NFC 標籤識別觸發不是门禁卡模擬。沒有把 Watch 變成任意讀卡器，亦不承諾 NFC 可解鎖手機或打開鎖屏 App。 |

Apple 的 [iOS 26 事件觸發指南](https://support.apple.com/guide/shortcuts/event-triggers-apd932ff833f/9.0/ios/26)列出鬧鐘停止／稍後提醒、睡眠與 Watch Workout；[設定觸發指南](https://support.apple.com/guide/shortcuts/apde31e9638b/9.0/ios/26)涵蓋 Focus、充電器與 NFC。觸發可以自動執行的種類與個別動作條件仍要對照 [自動化執行設定](https://support.apple.com/guide/shortcuts/apdfbdbd7123/ios)。新增 App Intent 不會自行安裝一份個人自動化。

## 事件契約與安靜規則

`PatrickAutomationEvent` 是 optional v1 command 欄位，舊訊息繼續可解碼，沒有改 protocol version 或舊日期格式：

```json
{"id":"UUID","kind":"alarm-stopped | wake-up","source":"shortcut | manual","occurredAtMS":1800000000375}
```

- 來源端把事件寫入既有日記一次，不增加飽足／親密，不修改 scene、sleep、outfit、timer。日記與狀態用既有 snapshot 同步。
- 每裝置另留最近100個事件 UUID；不同 WC envelope 裝著同一事件也不能重播。它與來源日記的去重、WC envelope 的去重分開。
- 時間必須有限且大於零；未來時間拒絕，不入 receipt。播放有效年齡是 **0–3,000 ms，包含邊界**。
- 背景、腕下、畫面被選單蓋住、低耗電、減少動態或過期：收件即消耗 UUID，只留回報文字；不排一個回前景要演的動作。
- 每次由安靜恢復可見，建立新的可見起點；更早產生的事件即使還在3秒內也不補播。重啟只讀 receipt IDs，不恢復播放許可。
- snapshot 沒有播放命令。先收到 snapshot 再收到 command 不因 envelope 共用 ID 而漏掉新事件；同事件從兩種传輸重到則由 UUID 去重。
- 使用既有 `eventClips["wake"]`：自動衣服按既有動作映射，固定衣服沒有起床圖就顯示缺少動作，不為了假裝成功而強換衣服。音效沿既有前景、開關和安靜護欄。

新 App Intent 不強制開 App。現行 [App Intents 執行模式](https://developer.apple.com/documentation/appintents/configuring-the-runtime-behavior-of-your-app-intents)也說系統會依執行位置與狀況決定前景／背景；一個背景 action 不是常駐服務。這裡保留相容的 `openAppWhenRun=false`，不為此新增較新 SDK API。

## Watch ↔ iPhone 實際傳輸保證範圍

現有 `WatchSyncService`／`PatrickWatchReceiver` 的處理：可達時即時 `sendMessageData`；互動傳送失敗或對方不可達時使用 `transferUserInfo`；最新狀態使用 `updateApplicationContext`，新值會取代尚未送出的舊狀態。收到 command 與 snapshot 都以 revision／experience 時間合併，不把延迟的資料視為新的視覺事件。

Apple 說背景傳送由系統排程，**不是即時**；`isReachable` 成立才適合互動傳送。Watch 到可達 iPhone 的訊息可以喚起 iPhone 處理，不代表反方向可以強制喚醒並打開 Watch UI。[WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)、[官方雙端範例與實機測試要求](https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity)。

本專案自身還有更窄的限制：啟用前 Phone 只暫留最後20筆待送，Watch 只暫留一個最新 envelope，這些暫存不是持久訊息佇列。程序結束、取消配對、未安裝、狀態被後值取代或超過容量時不能承諾所有事件必達。ack 只表示對方處理資料，不表示動畫／聲音／系統鬧鐘真的呈現；Demo ack 是本機模擬，不能當成真錶成功。

新增事件有獨立3秒期限；既有較寬的 legacy 命令有效時間不會延長它。離線後收到的新狀態可更新日記，視覺效果不追補。本輪沒有宣稱真機長時間連線、背景可靠度、鎖屏捷徑、NFC 或系統鬧鐘已驗收；相機遙控另作能力研究，未在此事件鏈中加入未授權的拍攝。

## 驗證

- 共用案例：`tools/fixtures/automation-events.json`，包含即時、3秒邊界、重複、quiet→active、不曾前景輪詢的延遲抵達、未來時間／回撥、重啟。
- Foundation：`tools/NativeAutomationChecks.swift`，加測 epoch毫秒存檔、日記一次、設定與照顧不變、無限／NaN拒絕、receipt上限。
- `tools/build_apple_simulators.sh` 接入純邏輯檢查及既有 Apple build 流程。Windows 此刻没有 Swift／Apple SDK，**本機來源檢查不等於 Swift 編譯通過**；Apple CI 與實機結果由 root 另記錄。
- Web automation lab 是隔離試驗，不更改主預覽資料，也不冒充 iPhone 已安裝個人自動化。

本輪 Windows 已執行：Watch 工程／來源123項、companion工程／DTO／語法結構檢查、既有6項原生來源測試，均通過。新增2個XCTest測receipt重載／reset、事件wire毫秒／舊欄位相容／設定不變，已接待Apple執行；沒有把這些尚未執行的Swift測試算進本機通過數。
