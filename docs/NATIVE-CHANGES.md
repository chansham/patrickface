# 原生 Apple Watch 第一批修改

2026-09-27。這份記錄描述已寫入的原生來源，不代表已完成 Apple SDK 編譯或真機驗收。既有角色 PNG 只是沿用的暫存外觀；本批不決定新畫風。

## 已實作

- **電池與充電**：畫面出現時啟用 `WKInterfaceDevice.isBatteryMonitoringEnabled`，背景停用、回到前景重新啟用。保留未知電量（-1）不視為低電量的防護；連接充電器及已充滿都視為實際充電。
- **睡眠判定**：移除 FocusChecker、Focus 輪詢及授權請求，不再把任何專注模式當成睡眠。保留清楚標示的 22:00–05:30 夜間排程、手機 sleepMode 和效果預覽相容性。
- **陪伴入口**：主畫面右下角「…」開啟情境和互動。可選「依時間陪伴」「休息陪伴」「睡眠陪伴」「運動陪伴」，选择存於手錶本機。休息停止自動揮手，睡眠顯示原有 Z 效果，運動陪伴只有身體小幅擺動，**不建立 workout、不讀取心率、不宣稱偵測到運動**。
- **打招呼**：沿用 1.8 秒揮手與系統 haptic；低耗電模式中停用。主畫面既有單擊、雙擊切換暫存外觀、長按揮手仍保留。
- **充電小表演**：必須讀到手錶實際 charging/full，才允許手動開始約 6 秒身體擺動。拔掉充電器、進入腕下／非前景／低耗電時，停止動作。手機「充電預覽」不會解鎖這個入口。它不接管系統充電動畫、不自動開啟 App、沒有背景表演。
- **預覽來源標示**：手機發來 sleeping／low-battery／charging 效果時，主畫面顯示「效果預覽」，complication 狀態顯示 PREVIEW，不再把模擬效果當成量測狀態呈現。
- **真實時間幾何**：低電量傾斜、橫向呼吸、運動及充電擺動只作用於身體。雙手繼續共享 `(360,498)`、時針長 250／分針長 340；外層只允許平移及等比縮放，不再讓傾斜和非等比縮放扭曲時間角度。既有短暫揮手偏移仍保留，結束後回到即時時間。
- **Complication**：身體先畫、雙手後畫；兩手同軸，軸心位置與長度比例改讀共用 `PatrickClockLayout`。沒有新增 widget family 或聲稱 complication 可連續互動。
- **狀態時效**：前景按分鐘更新共享狀態的時間戳。狀態未變時，widget reload 至多每 15 分鐘請求一次；狀態改變仍即時請求。實際刷新仍由 WidgetKit 排程。

## 與手機的相容規則

沒有修改 wire protocol v1、訊息名稱、theme raw values、bundle ID、App Group、receiver 或 iPhone 檔案。手錶情境是本機附加設定，不送入原有 wire。

手動情境優先於目前手機設定；新收到並接受的手機 sleepMode／previewState 會切回「依時間陪伴」，因此原有手機控制仍有作用。啟動時載入的既有手機快取不會清除手錶已存的手動選擇。

「依時間」模式保留原協議優先次序：手機 sleeping 預覽優先，否則手機 sleepMode on/off 優先於夜間排程。其他手動情境由使用者明確決定。

## 驗證與限制

本機 Windows 查無 `swift`，也沒有 Apple watchOS SDK。**沒有執行 Xcode Build、Simulator、簽名、安裝或真機測試。**

已執行：

- `python -B tools/validate_watch_project.py`：121 個來源／專案／協議／素材一致性檢查通過。
- `python -B tools/test_native_source.py`：6 組原生來源與幾何回歸通過。其中從目前 Swift 的手臂變換鏈讀取實際平移／縮放，再以 720 組方向與姿態組合驗證角度不被外層變換扭曲；其餘檢查生命週期、身體隔離、complication 層序、預覽標示及刷新節流。這不是 Swift 編譯測試。
- `git diff --check`：本批無空白錯誤。

已提供但**尚未執行**：`tools/NativeRulesChecks.swift`。它直接測試 `PatrickShared.swift` 的全天夜間邊界、手動／手機情境優先序、代表時間、共用幾何與原有 deep link。在有 Swift 的機器可將這兩個檔案一同編譯執行；完整 UI 仍需要 Xcode／Apple SDK。

待 Mac／實機確認：Picker／sheet 版面與關閉、充電器插拔及電池狀態延遲、腕下／低耗電節流、揮手後顯示角度、complication 各種尺寸和著色、手機控制與本機情境切換、WidgetKit 實際刷新預算。

## 尚未做

新畫風和服裝素材、节日换装內容库、健康情緒讀寫、壓力估算、真實 workout tracking、App Intents／Shortcuts、Smart Stack 直接互動、Controls、自訂通知／音效、全系統換皮，以及安裝分發流程，均不屬於這批原生已實作功能。
