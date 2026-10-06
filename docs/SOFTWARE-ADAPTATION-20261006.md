# 2026-10-06 軟件適配與互動補完

本輪依使用者「暫時無法連手機，先繼續補功能」的要求，沿實際首頁、選單、捷徑與同步呼叫路徑核對，並完成兩項可在電腦上準備的互動。以下「已接線」指有可達的程式入口；不代表已在使用者的 iPhone／Apple Watch 安裝驗收。

## 本輪實作

### 1. 分清運動陪伴的用途

Watch 選單、iPhone「計時」分頁和開始計時捷徑現在可選「散步陪伴」「跑步陪伴」「肌力陪伴」。原有專注、呼吸休息及一般運動陪伴保留。種類會存檔、記入日記，並隨 WatchConnectivity 的 experience 狀態同步。

- `PatrickActivityKind` 使用 `focus / breathing / exercise / walking / running / strength`。後四項均解析為 `exercise` 情境；專注和呼吸解析為 `focus`。
- 三項新增運動使用現有運動造型。兩端計時頁已說明共用素材；本輪沒有新增跑步原畫，不能把啞鈴畫稿當成新跑步動畫。
- 這些是按截止時間運作的陪伴倒數，不會開啟 Apple 健身訓練，也不會產生距離、速度、心率或卡路里資料。
- 沒有增加新的 WC envelope 類型或健康權限。兩端需使用含新增種類的版本；舊版 App 不保證能識別新增種類。

主要來源：`iOSCompanion/Shared/PatrickExperience.swift`、`PatrickFace/PatrickAnimatedFaceView.swift`、`iOSCompanion/PatrickCompanion/TimerControlView.swift`、`iOSCompanion/PatrickCompanion/PatrickPhoneExperienceView.swift`、`iOSCompanion/PatrickCompanion/PatrickIntents.swift`。

### 2. 捷徑可控制現有倒數，兩端按鈕共用同一規則

新增第八個預置捷徑「控制派大星陪伴計時」，可選暫停、繼續、結束。它開啟 iPhone App，讓既有模型同步 Live Activity；狀態變更會存至 App Group、更新小工具並送往配對手錶。

- 沒有活動時會如實回覆，不建立假的成功紀錄。
- 重複暫停或繼續不更改 revision，也不把截止時間向後延長。暫停後重啟 App，仍以凍結的剩餘時間繼續。
- 所有控制先結算截止時間：到期後才按「結束」，仍保留「完成」和一次完成獎勵；提早結束則不算完成。
- Watch、iPhone 原有暫停／繼續／結束按鈕也接至此共用控制。真正發生的轉換才加入日記。
- 沿用現有安靜恢復規則：狀態可結算，但不因此補播背景期間錯過的角色動作或音效。

主要來源：`PatrickExperienceState.controlActivity`、`PatrickTimerControlIntent`、`PatrickExperienceIntentExecutor.control`、`AppModel.toggleExperiencePause/cancelExperienceActivity`、`PatrickFaceApp.swift` 的 Watch model 專用 `controlActivity`（不經過無條件遞增 revision 的一般設定寫入入口）。

## 實際可達能力盤點

| 範圍 | 現在的入口與實作 | 確認邊界／缺口 |
|---|---|---|
| iPhone 主介面 | `RootView` 的陪伴、計時、連線三分頁；摸摸、餵食、休息、心情、情境、服裝、設定、日記、小驚喜 | 舊 `ThemeControlCenterView` 雖仍有源碼，未列入根頁導航，不能以它的舊按鈕宣稱可達 |
| Watch 互動 | 點角色摸摸；長按／更多選單可照顧、選當前服裝動作、開始及控制計時、找小驚喜、設定、開健康資料頁 | 缺指定服裝動作時不偷換別套衣服；腕下、背景、低耗電及減少動態遵守靜態／抑制效果規則 |
| 角色狀態 | 飽足、親密、餵食／摸摸統計、照顧冷卻、60 筆日記、本地存檔；按離線經過時間結算飽足 | 角色遊戲資料，不是人的生理或情緒評分 |
| 小驚喜 | 兩端「找個小驚喜」，六句輪替、60 秒持久化冷卻、日記；當前衣服有短反應才播放 | 只有文字／既有反應與點綴，沒有假稱新增動畫；背景不延遲補演 |
| 陪伴計時 | 10 秒至 120 分鐘、截止時間、暫停、繼續、結束、重載、一次完成結算；本輪補具名運動及控制捷徑 | 不開啟 HealthKit workout、不藉 workout 保持螢幕亮、不記錄運動成果 |
| 捷徑／自動化 | 照顧、情境、心情、開始計時、控制計時，以及既有睡眠模式、音效、開啟角色共 8 個預置捷徑 | 個人自動化需使用者在 iPhone 配置。情境可接 NFC／充電等自動化結果，不等於 Watch 掃 NFC 或自動偵測泡澡 |
| WatchConnectivity | 啟動 session、即時訊息／背景傳送／application context、訊息去重、新舊 experience 排序、旧 timer 覆蓋護欄 | 兩端真機離線重連、重签後 App Group／bundle ID 相容仍待試裝 |
| iPhone 小工具 | `PatrickStatusWidget` 讀 App Group，呈現心情、飽足、親密、計時；點擊 deep link 開 App | 是狀態小工具，尚無小工具內直接餵食或暫停按鈕 |
| Watch complication | `PatrickFaceComplications` 顯示狀態與時間，提供開 App 入口 | 由 WidgetKit timeline 更新，不是持續逐幀角色或替換整個系統錶面 |
| Live Activity | `PatrickActivityController` 開始／更新／結束；鎖定畫面、Dynamic Island 的計時與暫停狀態；點擊計時頁 | 受系統權限及呈現控制。沒有伺服器推播或假背景保活；真機鎖屏與跨裝置顯示仍待驗證 |
| 聲音與觸感 | 六個本機短音效、設定開關；新舊音效入口共用前景、低耗電、減少動態與過期請求限制 | 音效預設關閉；實際音量、靜音模式、震感、Watch 喇叭效果須真機聽測 |
| 健康資料 | Watch 健康頁按鈕才請求讀取今日步數、最新心率／HRV 與樣本時間；無資料顯示尚無資料 | 只讀既有樣本，不是即時運動監測。不能把讀不到資料判成「拒絕授權」，不推測壓力或自動設定心情；iPhone 首頁沒有健康資料入口 |
| 睡眠／日期／充電 | 睡眠時段可調、生日去重、精確節日表；Watch 真實電池充電狀態接場景；前景充電／泡澡泡泡有動態開關 | 不代替系統睡眠記錄、Nightstand 或原生充電畫面；農曆只有已有年份表，不能猜未提供日期 |
| 錶面版式 | 本輪由版式工作另接經典／大字／劇場／運動資訊；本文件僅補 settings 遷移與保存測例 | 新版式實際 Apple 編譯及畫面證據由本輪整體驗證提供，不沿用舊經典版截圖當作四版已驗收 |

## 驗證紀錄與下一步

已確認的上一輪基線為 `9d6e095`、[Apple 執行 37256581810](https://github.com/chansham/patrickface/actions/runs/37256581810)：1,695 項 Foundation 檢查、9 項 XCTest、Watch／iPhone／小工具／complication 編譯、封存與未簽名 IPA 包裝通過。真實模擬器為 Series 11 46mm／watchOS 26.4 及 iPhone Air／iOS 26.5，不是使用者的 Series 12／OS 27。詳情見 [APPLE-BUILD-20261005.md](APPLE-BUILD-20261005.md)。

2026-10-06 本輪在 Windows 完成：

- `tools/test_native_source.py`：6 項既有來源回歸通過。
- `tools/validate_watch_project.py`：123 項 Watch 工程檢查通過。
- `iOSCompanion/tools/validate_structure.py`：工程、extension、嵌入 Watch、scheme、權限／隱私與來源結構檢查通過。
- 原生互動修改的 `git diff --check` 通過。
- `NativeExperienceChecks.swift` 新增 33 個計時種類／控制／截止／重載斷言，以及 6 個版式舊檔遷移、四種值 roundtrip 與未知值 fallback 斷言；`PatrickContractTests.swift` 新增 2 項真 XCTest，覆蓋 App Group 持久化、WC envelope 與過期控制的兼容計時呈現。

**Windows 沒有 Swift／Apple SDK，新增 Swift 斷言與 XCTest 尚未在本輪執行。** 上述來源檢查不能替代編譯。下一次 Apple 檢查需執行新增測試，並在 simulator 實際試：散步開始→暫停→重開→繼續→結束；跑步到期後再結束；捷徑重複控制；配合四版式核對計時顯示。真機可連線後，再驗 Watch 同步、音效、健康讀取授權和安裝續期。此次沒有啟動 CI、推送、簽名或操作裝置。

## Apple 一手依據（查閱 2026-10-06）

- [AppIntent](https://developer.apple.com/documentation/appintents/appintent) 與 [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider)：以既有 App Intents 型別提供操作、參數與預置捷徑。本輪採用現有 App 的介面模式，未引入新版本限定 API。
- [Authorizing access to health data](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)：讀取需逐資料類型授權；基於隱私，不能由讀不到樣本判斷使用者拒絕讀取權限。
- [Displaying live data with Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities)：ActivityKit 管理呈現的開始、更新、結束；不是任意背景執行或自動運動記錄能力。

上述官方頁面已讀取其 Markdown 內容；實際採用能力仍以本專案的呼叫路徑和 Apple 編譯／裝置結果為準。
