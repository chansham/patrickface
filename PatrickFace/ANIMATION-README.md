# 原生逐格播放器接入記錄

更新：2026-09-27。這一輪是 **watchOS 原始碼接入**；目前這台 Windows 沒有 Swift 編譯器、Xcode 或 Apple SDK，尚未證實能在模擬器或 Series 12 46mm 上執行。

`PatrickFaceApp` 現在開啟 `PatrickAnimatedFaceView`。旧的 `PatrickFaceView` 與圖片保留在專案中，但不再是主 App 的畫面入口。本輪沒有改舊圖片、complication 圖像或 iPhone 的畫稿展示。

## 已寫入的行為

- 時間由獨立的 `TimelineView(.everyMinute)` 顯示；動作暫停、素材缺失、讀取錯誤都不會停止數字讀時。時間維持在角色上方。
- 從圖集逐格抽取並替換畫稿，不靠整張圖片旋轉、呼吸縮放或平移充當角色表演。宣告 `frameRegions` 時按逐列輪廓遮罩抽取，不能用外框裁切代替遮罩，以免把鄰格人物一起帶入；每格使用同一個方形顯示區。
- 416:496 只作參考畫面比例，按實際 SwiftUI 空間等比縮放；不把硬體像素當成 point。角色方框位於 `(0.1W, 0.25H)`，邊長 `0.8W`。
- `scale` 預設 1、整段共用；`frameRegions` 的來源是同一個 N×N 畫布，定位採分區檔內的 `canvas.anchorNormalized`，對齊 `master.anchorNormalized`。不根據每格人物外框重新置中或縮放。只有未宣告分區檔的舊資料仍用等格方式：非正方形格等比顯示，寬為 `方框邊長 × min(1, 格比例) × scale`，高為 `方框邊長 × min(1, 1/格比例) × scale`，格邊界由共享比例取整而不累加格寬。
- 支援 `frameIndices`；播放格數可大於原圖格數，例如同一張八格圖播放兩次組成十六格。動作長度採 `durationsMs`，不使用持續 30/60fps 的空轉重繪。
- 只要 App 不在前景、腕下、開啟「減少動態」或低耗電模式，就取消表演與待機計時，回靜態畫稿。回到前景不補播安靜期間錯過的情境。
- 找不到動作、檔案缺失、SHA 校驗失敗或分區資料不符時顯示尚未準備／讀取失敗，選單停用該動作。分區檔宣告後讀取失敗不退回等格裁切，也沒有拿舊動作假裝替代。

## 情境與觸發

| 動作 | 來源 | 播放方式 |
| --- | --- | --- |
| 三種眨眼 | `idle-blink-normal`、`idle-blink-slow`、`idle-blink-double` | 僅清醒、未充電、未專注、未運動時，在上次表演結束後隨機等待 10–22 秒，再從實際可讀的圖集中挑一種，排除上一種。只剩同一款可讀時保持靜止，不連播 |
| 睡前哈欠 | 手動選睡眠、現有 22:00–05:30 規則、手機傳來的睡眠設定／效果預覽 | 進入睡前時一次；自動觸發至少間隔 10 分鐘，時間儲存在本機。選單的明確手動試播可重播 |
| 睡醒 | 從睡眠狀態退出 | 一次，素材缺失則顯示未準備 |
| 充電 | 手錶本身的 `batteryState`，或已明示的手機效果預覽 | 進入 charging/full 時一次。前景約每 5 秒讀取；不是偵測 iPhone 充電，也不替换系統充電畫面 |
| 摸摸／點擊 | 點角色、長按、既有外部開啟互動命令、選單 | 播放 `pet` 一次；播放中重複點同一個動作不重新解碼或無限重啟 |
| 投餵 | 選單／輔助使用動作 | 播放 `feed` 一次 |
| 專注 | 手機現有計時器經 WatchConnectivity 到達 `.running` | 播放 `focus` 一次；不把一般 Focus 狀態當成睡眠或運動 |
| 完成慶祝 | 已知計時器到達截止時間；同一 ID 只觸發一次 | 播放 `celebrate` 一次。v1 停止命令會清除計時器，因此保留已知截止時間；提早停止不慶祝，超過 60 秒的過期事件不補播 |
| 運動 | 現有手動「運動陪伴」情境 | 進入時播放 `exercise` 一次；沒有宣稱已接 HealthKit 偵測或記錄運動 |
| 泡澡及其他動作 | 動作選單 | 一次性手動試播；沒有新增自動泡澡判斷 |

若第一次打開 App 時已在睡前或充電狀態，視為這次可見工作階段的初次進入；哈欠仍受已保存的冷卻時間限制。啟動後只有靜態哈欠首格可用時，這張已存在的新畫稿可作安靜底圖，**不會代演缺失的其他動作**。

## 素材位置

共享來源為專案根目錄 `animation/catalog.json`。原生 Resources 新增了 `PatrickFace/Animation/` 的 folder reference；同步工具必須把清單與所需圖集放入這裡並保留子目錄。

清單中的 `atlas` 可為 `animation/yawn-v1/atlas-eyes-v2.png` 或原生相對路徑 `yawn-v1/atlas-eyes-v2.png`。原生讀取時去掉開頭的 `animation/`，拒絕绝對路徑、URL、反斜線與 `..`。不能把「已批准方向」當成「每個新畫稿都已通過審稿」。

## 輪廓分區契約

清單可增加 `frameRegions: {path, sha256, version: 1}`；`path` 與圖集採同一套路徑限制，分區 JSON 必須同步到 App 的 Animation 資源資料夾。播放器核對分區 JSON 的 SHA-256、來源 PNG 的實際 SHA-256／尺寸／路徑，以及清單提供的 PNG SHA。任何不符均使該動作不可播放。

分區檔採 `schemaVersion: 1`，提供共同方形 `canvas` 與逐格 `frames`：

- `canvas.anchorPixels` 是整數定位點；`anchorNormalized` 必須等於該點除以畫布邊長，不能以近似的 0.88 代替實際比例。
- `sourceBounds` 是源 PNG 的外框，**並不表示外框裡所有像素都屬於本格**。`rows` 才是本格像素遮罩：每列為 `[來源 y, x 起點, x 終點（不含）, …]`，可有多段分離的範圍。
- `translation = canvas.anchorPixels - anchorSource` 是整張源圖的整數平移；`placement = sourceBounds.xy + translation` 是外框在輸出畫布的位置。原生驗證兩者一致，沒有把 placement 當成整張圖的平移量。
- 每格建立同尺寸透明 CGContext，以 rows 對應的矩形聯集裁限，再將原圖按 translation 平移繪入。來源像素與輸出畫布為 1:1，關閉插值和裁限抗鋸齒；不按每格外框放大，不改寫 PNG。
- 分區座標從左上開始，bitmap CGContext 的預設座標從左下開始。遮罩列使用 `N - (sourceY + translationY) - 1`，整張圖的繪製底部使用 `N - translationY - atlasHeight`；兩處共同轉換一次，不再逐格翻轉。
- `frameIndices` 索引分區檔的 frames，可重複同一個分區。沒有這個欄位時按 0 到 frameCount−1 播放。

分區來源、畫布、平移、像素列及播放索引的檢查已寫入原始碼。這是資料與實作說明，**尚未用 Apple SDK 編譯或執行 CGContext**；上下方向、彩色半透明邊緣及 Core Graphics 色彩／預乘 alpha 的實際結果仍須在 Mac 比對。

## 驗證與待辦

本機已執行現有工程驗證：123 項來源／工程／配對與隱私檢查通過。四個新增 Swift 檔的 Sources reference、Animation Resources reference、主入口也已檢查；這些都不是 Swift 編譯成功的證明。

另提供純 Foundation 測試 `tools/NativeAnimationChecks.swift`，涵蓋情境只播一次、冷卻邊界、四種靜態條件、同一計時器只慶祝一次、提早取消、舊資料奇數圖集切格、重複播放索引和路徑檢查。本輪補上分區來源／定位一致性、遮罩缺失／重疊／越界、分區索引重複，以及宣告分區後禁止退回等格的檢查；傳入清單時也讀取其分區 JSON。**此測試尚未執行**，且它不執行 CryptoKit 檔案雜湊或 Core Graphics，需在已有 Swift 的機器上：

```sh
swiftc PatrickFace/PatrickAnimationCatalog.swift PatrickFace/PatrickAnimationPolicy.swift tools/NativeAnimationChecks.swift -o /tmp/patrick-animation-checks
/tmp/patrick-animation-checks animation/catalog.json
```

Mac 上先同步素材，再使用現有 `tools/build_apple_simulators.sh` 做無簽名編譯；本輪沒有啟動遠端 CI、安裝、簽名或上传。模擬器與實機還需確認：

1. 數字可讀、圖集上下方向正確；以分區資料比對每格帽子、腳和鄰格邊界。加入上紅下藍與半透明邊緣的小測試圖，確認 row mask 沒有混入鄰格、平移沒有上下顛倒、色彩與透明邊緣正確。固定比例／定位不應因切格跳動；原圖本身已有的尺寸或姿勢差異仍需另看。
2. 角色點擊、長按、動作選單、從選單關閉後開始播放；選單開啟時主畫面的動作與待機排程取消，5 秒狀態輪詢也停止。
3. 腕下、中斷、App 切到背景、減少動態、低耗電途中切換，均立即停止；安靜狀態不在背後補幀或等待播完。
4. 真實 Watch 充電狀態、配對 iPhone 的睡眠命令、開始／提早停止／正常到期計時器。更換手機後需重新驗證配對與安裝；目前實際 OS 小版本未知。
5. 連續數分鐘的待機間距、記憶體峰值、抽幀耗時與耗電。原生保留靜態底圖、當前圖集與分區資料，逐次產生當前 N×N 畫格，不預先常駐整段的所有輸出畫格；仍須實機量測。

## Apple 官方依據

查閱日期：2026-09-27。

- [TimelineView](https://developer.apple.com/documentation/swiftui/timelineview)：獨立時間更新排程；watchOS 腕下時系統可能降低更新頻率。
- [isLuminanceReduced](https://developer.apple.com/documentation/swiftui/environmentvalues/isluminancereduced)：腕下且常顯時通常為 true，須適應低亮度。
- [accessibilityReduceMotion](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducemotion)：讀取系統「減少動態」偏好。
- [isLowPowerModeEnabled](https://developer.apple.com/documentation/foundation/processinfo/islowpowermodeenabled)：低耗電狀態及其變更通知。
- [WKInterfaceDevice batteryState](https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterystate)：先啟用電池監控才能讀取充電狀態。
- [CGImageSource](https://developer.apple.com/documentation/imageio/cgimagesource)、[cropping(to:)](https://developer.apple.com/documentation/coregraphics/cgimage/cropping(to:))：讀取圖集並按格裁切。
- [Quartz 2D 座標系統](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Conceptual/drawingwithquartz2d/dq_overview/dq_overview.html)、[CGContext clip](https://developer.apple.com/documentation/coregraphics/cgcontext/clip(using:))：bitmap context 預設原點在左下，路徑可裁限繪製範圍。
- [CryptoKit HashFunction](https://developer.apple.com/documentation/cryptokit/hashfunction)：用 SHA-256 比對打包的 JSON 與來源圖集版本。
