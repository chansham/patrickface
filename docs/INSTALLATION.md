# 私人安裝

目前只有一條安裝路線：Windows、免費 Apple 帳號、[Sideloadly](https://sideloadly.io/) **0.71.0**。不需要 Mac，不走 TestFlight，不租 Mac，也不用付費 Apple Developer Program。這些路線已不採用，下文不再寫它們的步驟。

還沒有裝到手機或手錶上。無簽名編譯通過，不等於已經簽名或已經安裝。

## 裝置

目前的裝置是 iPhone 18 Pro Max 和 Apple Watch Series 12 46mm，系統是 iOS 26 和 watchOS 26。App 最低系統同樣是 iOS 26 和 watchOS 26。沒有讀取序號或系統 build，也沒有在這兩台真機上跑過。細節見 [裝置紀錄](DEVICE-PROFILE-2026-09-27.md)。

## 為什麼第一階段只裝 iPhone

Sideloadly 0.71.0 的更新說明寫明：Apple Watch App 現在會簽名並處理，但對象是已加入 Apple Developer Program 的帳號；免費 Apple 帳號的支援要等下一版。出處是 [Sideloadly changelog](https://sideloadly.io/changelog) 的 v0.71.0。

因此用免費帳號時，不能把內嵌 Watch App 簽上去並當成已支援。第一階段只安裝 iPhone companion。Watch 程式、complication 和未簽名封存都留在倉庫裡，等 Sideloadly 下一版寫明免費帳號可以簽 Watch，再另測。不要為了裝上手錶改走付費會員、TestFlight 或租一台 Mac。

0.70.1 曾寫「預設保留 WatchKit App 並重簽」。0.71.0 把 Watch 簽名收成付費開發者帳號，免費帳號明確延後。以 0.71.0 這句為準。

## 未簽名包怎麼來

[apple-build.yml](../.github/workflows/apple-build.yml) 固定在 macos-26、並明確選用 Xcode 26.6。push（含 `main`）時編譯模擬器產品。通過後才做無簽名 Release device archive，並上傳 artifact `patrick-unsigned-resigning-input-<run number>`，保留 7 天。裡面的 `PatrickCompanion-unsigned.ipa` 不能直接安裝，要由 Sideloadly 用自己的免費 Apple 帳號重簽。

截圖用的 Watch 模擬器預設 46mm，並優先選這台 runner 已安裝、且 runtime 支援的 Series 12。若沒有 Series 12，就保持最接近的 46mm（目前常見是 Series 11），並在該次 `report.json` 的 `series12Fallback` 寫明。模擬器截圖失敗若只是手機截圖逾時，不代表編譯失敗。

手動在 Mac 上可以用 `bash tools/build_apple_simulators.sh`。這份文件不把借來的 Mac 當成安裝路線。

四個產品的 bundle ID 仍是：

| Target | bundle ID |
|---|---|
| iPhone App | `com.chans.patrickface.companion` |
| iPhone widget／Live Activity | `com.chans.patrickface.companion.widgets` |
| Watch App | `com.chans.patrickface.companion.watchkitapp` |
| Watch complication | `com.chans.patrickface.companion.watchkitapp.complications` |

共用 App Group 是 `group.com.chans.patrickface.shared`。第一階段只簽 iPhone 時，widget 若一起簽上，群組名稱仍要和程式裡的固定值一致。Watch 的 HealthKit 留到免費帳號可以簽 Watch 之後再驗。

不要把 Apple 帳號密碼、`.p12`、私鑰或 `.mobileprovision` 放進版本庫。

## 第一階段：只裝 iPhone

以下尚未在這台手機上做過。做到哪一步，就記到哪一步。

1. 只從 [Sideloadly 官網](https://sideloadly.io/) 安裝 Windows 版，確認版本是 0.71.0。依官網準備 iTunes／iCloud 元件。用 USB 接上並解鎖 iPhone 18 Pro Max，在手機上信任這台電腦。
2. 從當時最新的 `patrick-unsigned-resigning-input-<run>` 取出 `PatrickCompanion-unsigned.ipa`，先核對同目錄的 SHA256。
3. 把 IPA 載入 Sideloadly。Apple 帳號、密碼和兩步驗證只在自己的電腦上輸入，不寫進文件或倉庫。
4. 免費帳號簽不上 Watch 時，第一階段以 iPhone App 能打開為準。Watch 沒有出現是目前工具的限制，不是改走付費路線的理由。若整包因為內嵌 Watch 而簽失敗，保留 Sideloadly 的原文，不要改 bundle、刪檔或假裝 Watch 已裝上。
5. 若手機要求開發者模式或信任開發者，依畫面指示到「設定 → 隱私權與安全性 → 開發者模式」，或「設定 → 一般 → VPN 與裝置管理」。選項沒出現就留下畫面，不補寫一個不存在的開關。
6. 免費帳號的安裝大約 7 天要續簽。Sideloadly 的自動續期需要電腦上的 Daemon，並用 USB 或已設定的同一網路看到這台 iPhone。續期沿用同一個 Apple 帳號和 bundle ID。

iPhone 裝上之後先看：App 能冷啟動、數字時間在、設定裡沒有「星星睡衣樣本」、也沒有「原味手臂時計」讀時選項。手錶端留到免費帳號的 Watch 簽名可用之後。

## 真機之後要核對的行為

這些是裝上 iPhone、以及日後 Watch 能簽上之後的驗收，不是現在已經通過的項目。

1. 首頁數字時間會更新。手臂時計維持暫停，不應出現在設定或畫面上。
2. 換衣、心情、聲音、觸覺、日期和 24 小時制在關掉再開後仍在。
3. 照顧和陪伴計時的規則與源碼一致；這不是 HealthKit 健身紀錄。
4. 健康、通知、定位只在用到時才請求；拒絕之後基本陪伴仍可玩。
5. 模擬器通過不能代替這張表。
