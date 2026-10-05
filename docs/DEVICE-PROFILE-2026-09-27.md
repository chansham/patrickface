# 裝置目標與查證 · 2026-09-27

本文件把使用者提供的裝置資訊與 Apple 官方規格分開記錄。已足夠按 46mm 目標繼續製作；沒有讀取或實測使用者裝置，也沒有據此宣稱已安裝成功。

| 項目 | 使用者提供 | 本輪官方查證／仍未知 |
|---|---|---|
| Apple Watch | 「最新 Apple Watch 12、46mm、S12」 | 官方確有 Apple Watch Series 12，46mm 版本顯示器為 416×496 實體像素、326ppi。官方晶片欄列 **S11**；保留使用者原報「S12」，不推斷其用意或當作已核實晶片。具體型號號碼、材質、GPS／Cellular 未讀取。[Apple 規格](https://www.apple.com/apple-watch-series-12/specs/) |
| watchOS | 最新版本，確切號碼不確定 | 查證時 Apple 列 Series 12／Ultra 4 最新為 **watchOS 27.0.1**，其他 Series 9 及後續適用型號為 27。這是官方可用版本，不是已確認手錶安裝版本。[Apple 安全性版本列表](https://support.apple.com/en-us/100100) |
| 現有 iPhone | iPhone 13 Pro、最新 iOS | Apple 的 iOS 27 支援列表含 iPhone 13 Pro；查證時最新公開 iOS 為 27。裝置實際版本與 build 號仍未知。[iOS 支援裝置](https://www.apple.com/os/ios/)、[版本列表](https://support.apple.com/en-us/100100) |
| 配對相容性 | 有上述 Watch 與 iPhone | Series 12 官方条件為 iPhone 11 或後續機型、iOS 27 或後續、watchOS 27 或後續。iPhone 13 Pro 符合手機世代條件；實際配對、系統版本與本 App 安裝流程仍須驗證。[Apple 相容表](https://support.apple.com/en-la/118490) |
| 下一支 iPhone | 計劃 10 月中換 iPhone 18 Pro Max | 記為購買計劃，不算已持有。iPhone 18 Pro Max 在官方 iOS 27 支援列表中；不以換機作為目前製作的前提。[iOS 支援裝置](https://www.apple.com/os/ios/) |
| 開發電腦 | Windows，沒有 MacBook | Windows 可做素材、資料、瀏覽器及純邏輯檢查。原生仍須 macOS／合適 Xcode、簽名與實機分發；現有路線見 [INSTALLATION.md](INSTALLATION.md)，本輪沒有購買、遠端編譯或安裝。 |

## 顯示尺寸如何使用

- 46mm 是錶殼規格；416×496 是官方顯示器像素。兩者不能直接換成瀏覽器 CSS 寬度。[Apple 規格](https://www.apple.com/apple-watch-series-12/specs/)
- 200 CSS px 小預覽只用來檢查縮小後的角色表情與主要時間是否可讀。瀏覽器縮放、作業系統縮放和螢幕密度不同，不能標成「與實體 46mm 完全同尺寸」。
- 原生需在實際可用畫面、圓角及安全區中排版；不能把整個 416×496 像素矩形當作每個位置都能放內容。
- 現階段保留大圖、约 200 CSS px 小圖和逐幀檢視。真正大小、亮度、Always-On、腕下、觸控、耗電與持續播放限制仍待實機。

## 後續裝置驗證資料

需要安裝時再補實際 watchOS／iOS 版本、型號號碼、普通配對或家人設定、簽名／Developer Program 情況，以及使用的 Xcode／SDK 版本。這些未知不會阻止美術和前景播放器繼續製作。

Apple 的版本列表顯示 Xcode 27 已於 2026-09-14 發布，需支援的 macOS；雲端 runner 是否已提供、工程是否能編譯，必須看該次建置輸出，不能只憑官網有新版就寫已通過。[Apple 安全性版本列表](https://support.apple.com/en-us/100100)
