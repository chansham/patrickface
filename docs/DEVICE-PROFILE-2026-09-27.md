# 裝置目標與查證 · 2026-09-27

本文件把使用者提供的裝置資訊與 Apple 官方規格分開記錄。下表保留 **2026-09-27 查證時點**，10 月 5 日的新版本、帳號與編譯證據另列於後。已足夠按 46mm 目標繼續製作；沒有讀取或實測使用者裝置，也沒有據此宣稱已安裝成功。

| 項目 | 使用者提供 | 2026-09-27 官方查證／當時仍未知 |
|---|---|---|
| Apple Watch | 「最新 Apple Watch 12、46mm、S12」 | 官方確有 Apple Watch Series 12，46mm 版本顯示器為 416×496 實體像素、326ppi。官方晶片欄列 **S11**；保留使用者原報「S12」，不推斷其用意或當作已核實晶片。具體型號號碼、材質、GPS／Cellular 未讀取。[Apple 規格](https://www.apple.com/apple-watch-series-12/specs/) |
| watchOS | 最新版本，確切號碼不確定 | 查證時 Apple 列 Series 12／Ultra 4 最新為 **watchOS 27.0.1**，其他 Series 9 及後續適用型號為 27。這是官方可用版本，不是已確認手錶安裝版本。[Apple 安全性版本列表](https://support.apple.com/en-us/100100) |
| 現有 iPhone | iPhone 13 Pro、最新 iOS | Apple 的 iOS 27 支援列表含 iPhone 13 Pro；查證時最新公開 iOS 為 27。裝置實際版本與 build 號仍未知。[iOS 支援裝置](https://www.apple.com/os/ios/)、[版本列表](https://support.apple.com/en-us/100100) |
| 配對相容性 | 有上述 Watch 與 iPhone | Series 12 官方条件為 iPhone 11 或後續機型、iOS 27 或後續、watchOS 27 或後續。iPhone 13 Pro 符合手機世代條件；實際配對、系統版本與本 App 安裝流程仍須驗證。[Apple 相容表](https://support.apple.com/en-la/118490) |
| 下一支 iPhone | 計劃 10 月中換 iPhone 18 Pro Max | 記為購買計劃，不算已持有。iPhone 18 Pro Max 在官方 iOS 27 支援列表中；不以換機作為目前製作的前提。[iOS 支援裝置](https://www.apple.com/os/ios/) |
| 開發電腦 | Windows，沒有 MacBook | Windows 可做素材、資料、瀏覽器及純邏輯檢查。原生仍須 macOS／合適 Xcode、簽名與實機分發；現有路線見 [INSTALLATION.md](INSTALLATION.md)，截至 9 月 27 日沒有購買、遠端編譯或安裝；10 月 5 日的編譯新增證據見下文。 |

## 顯示尺寸如何使用

- 46mm 是錶殼規格；416×496 是官方顯示器像素。兩者不能直接換成瀏覽器 CSS 寬度。[Apple 規格](https://www.apple.com/apple-watch-series-12/specs/)
- 200 CSS px 小預覽只用來檢查縮小後的角色表情與主要時間是否可讀。瀏覽器縮放、作業系統縮放和螢幕密度不同，不能標成「與實體 46mm 完全同尺寸」。
- 原生需在實際可用畫面、圓角及安全區中排版；不能把整個 416×496 像素矩形當作每個位置都能放內容。
- 現階段保留大圖、约 200 CSS px 小圖和逐幀檢視。真正大小、亮度、Always-On、腕下、觸控、耗電與持續播放限制仍待實機。

## 2026-10-05 使用者條件與官方複核

使用者已明確確認：只有一般 Apple 帳號，**沒有付費 Apple Developer Program 會員**，使用 Windows、iPhone 13 Pro 與配對 Watch，沒有可用 Mac。未選擇借 Mac 或 TestFlight；不要求其另找 Mac 或購買會員。免費帳號的官方能力範圍不等於本專案已完成簽名，完整安裝路線的條件見 [INSTALLATION.md](INSTALLATION.md)。

| 本次複核 | 2026-10-05 官方資料 | 與實機／舊紀錄的界線 |
|---|---|---|
| Watch 規格 | Series 12 原頁仍列 46mm、416×496 像素、326ppi、**S11**。[Apple 規格](https://www.apple.com/apple-watch-series-12/specs/) | 不更改使用者原報「S12」，不以官網代替讀取其型號號碼。 |
| 公開系統版本 | Apple 現列最新 iOS 與 watchOS 均為 **27.0.1**；9 月 28 日 watchOS 27.0.1 已列適用 Series 9 及後續型號。[安全性版本列表](https://support.apple.com/en-us/100100) | 上表的「iOS 27、只有 Series 12／Ultra 4 為 watchOS 27.0.1」是 9 月 27 日的歷史查證；使用者手機／Watch 實際版本與 build 號仍未知。 |
| iPhone 與 Watch 相容性 | iOS 27 支援列表仍含 iPhone 13 Pro、iPhone 18 Pro Max；Series 12 配對條件為 iPhone 11 或後續、iOS 27 或後續、watchOS 27 或後續。[iOS 支援裝置](https://www.apple.com/os/ios/)、[Watch 相容表](https://support.apple.com/en-la/118490) | 符合官方世代條件，不等於本 App 已在這一對裝置安裝及運行；18 Pro Max 仍只是換機計畫。 |
| Xcode／SDK | 官方表列 Xcode 27 使用 iOS／watchOS SDK 27，需 macOS Tahoe 26.6 或後續；也列 Xcode 26.6 使用 SDK 26.5。[Xcode 系統要求](https://developer.apple.com/xcode/system-requirements) | 本次 runner 仍是 26.6／26.5。Xcode 27 的公開存在不是本工程已用 27 編譯的證據。 |
| 免費帳號 | 官方允許 Xcode Personal Team 作個人裝置測試；profile 簽發後 7 天到期，需重新建置安裝。當前 iOS／watchOS 能力表的免費欄均列 App Groups、HealthKit 支援。[Personal Team](https://developer.apple.com/help/account/basics/about-your-developer-account)、[iOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-ios)、[watchOS 能力表](https://developer.apple.com/help/account/reference/supported-capabilities-watchos) | 沒有因此要求付費或刪除功能；四個 target 的免費簽名、Widgets／complication 共用資料、WatchConnectivity 真機運作與續期均未驗證。純 Windows 完整安裝流程仍未證實。 |

## 2026-10-05 已取得的 Apple 編譯證據

已用使用者指定的 `chansham/patrickface` 私人 GitHub 倉庫完成 [run 37254670555](https://github.com/chansham/patrickface/actions/runs/37254670555)，版本 `f6daa08`，結果為成功：

- runner：Xcode 26.6、iOS／watchOS SDK 26.5。
- 1,695 項 Foundation 檢查（1503＋129＋63），以及 iPhone Air／iOS 26.5 模擬器上的 9 項 XCTest 通過。
- iPhone App、Watch App、iPhone widget、Watch complication 四個產品編譯及版本／ID／素材 SHA 檢查通過。
- 無簽名 Release device archive 成功；實際封存包中的 Watch payload 和四個產品通過檢查。

這些是 **Apple 編譯、測試及封存證據**，並非使用者實機的系統資料，也不是簽名或安裝成功。沒有可直接裝到 Watch 的已簽名成品；TestFlight／Ad Hoc 的會員條件未滿足。完整建置過程見 [APPLE-BUILD-20261005.md](APPLE-BUILD-20261005.md)。

**26.5 與 27 的界線：**26.5 模擬器通過不能描述為 Series 12／OS 27 真機通過；後續需以使用者實際版本配對、簽名、安裝及運行。官方表的 Xcode 26.6 Device Support 欄寫 iOS 15 or later／watchOS 8 or later，沒有相同的上限，因此也不僅憑 SDK 較舊就判定 OS 27 必定不能安裝。若需要排查新版裝置問題，應以支援的 Xcode／SDK 與實際連線結果對照，不能虛構相容或不相容結論。[Xcode 系統要求](https://developer.apple.com/xcode/system-requirements)

## 後續裝置驗證資料

需要安裝時仍須補實際 watchOS／iOS 版本及 build、Watch 型號號碼、普通配對／家人設定細節、可行的簽名與安裝入口，並記錄當次 Xcode／SDK。使用者沒有付費會員已是已知條件，不再列為待確認。這些未知不阻止美術、前景播放器及現有 macOS CI 繼續驗證，也不表示已選定要使用者另找 Mac 的路線。
