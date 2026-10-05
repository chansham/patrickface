# 私人安裝與沒有 Mac 的開發路線

資料查證：2026-09-27；原生整合更新：2026-09-28。此文件提供可選路線與驗收門檻；**尚未代表本專案已編譯、簽名、上傳或安裝成功**。本次研究沒有購買服務、建立 Apple 帳號、上傳程式或操作手錶。

## 現在已知與待確認

- 使用者沒有 MacBook；目前使用 iPhone 13 Pro，計畫換 iPhone 18 Pro Max，Watch 為使用者提供的 Series 12 46 mm。OS 小版本與 Apple Developer Program 會員狀態仍待確認。此套裝按普通配對 iPhone＋Watch 開發。
- 私人 GitHub 倉庫 `<GITHUB_USER>/patrickface` 已只讀確認為 **PRIVATE**、預設分支 `main`；查詢時沒有已登記的 workflow 或 run。沒有更改可見度、推送、上傳或啟動 CI。
- Windows 已接好原生首頁、數字時間、逐幀素材、原味手臂時計、衣服／情境／心情、照顧、音效／觸覺、作息、生日與確切日期節日、陪伴倒數及手機同步的源碼。iPhone widget、Watch complication 改讀同一份陪伴狀態；舊整圖晃動頁不再是首頁。
- Watch 健康摘要只在按下按鈕後請求 **read-only** 今日步數、最近心率及 HRV，附資料時間；沒有樣本顯示「尚無資料」，不推斷拒絕權限或人的心情，不啟動假健身 session。
- **所有上述原生修改尚未在 Apple SDK 編譯或實機跑過。**素材為本輪授權接入的開發稿；新衣服、時計關節和動作過渡仍可審改。不可把網頁通過或源碼檢查通過寫成 Watch 已完成安裝。
- 沒有自己的 Mac 不等於必須買 Mac：借用／租用遠端 Mac 或 macOS CI 可以編譯，但仍要處理簽名和真機交付。[I01]

## 如何選擇

| 條件與目的 | 首選路線 | 仍需要什麼 |
|---|---|---|
| 有普通配對 iPhone，要完整寵物邏輯 | Windows 開發＋macOS CI／遠端 Mac＋自己帳號的 TestFlight 內部測試 | Apple Developer Program、簽名設定、有效 build；按真機問題迭代 |
| 先把角色外觀戴上去，願意使用現成工具的互動能力 | Clockology 的 iPhone編輯／匯入與Watch App | 相容iPhone／Watch、重新製作成其支援格式；完整養成邏輯不保證可做 |
| 有可借的 Mac，先少量測試並接受每週維護 | Xcode＋免費 Personal Team 開發安裝 | 與Xcode可配對／連線的真機；7天到期後重新建置安裝 |
| 不經TestFlight，要給自己的註冊裝置安裝 | 付費會員＋Ad Hoc／development provisioning | Watch與相關裝置識別碼、有效profile、已驗證的本地安裝管道 |
| 只有家人設定的Watch，沒有一般配對iPhone | 先驗 independent watch app與該設定的安裝管道 | 不能假設管理者iPhone能按普通配對流程安裝TestFlight；可能先用現有獨立App驗入口 |
| 想從Windows用AltStore／Sideloadly直接裝Watch | 研究候選，不作已可交付路線 | 必須找到匹配機型／版本的維護中實作並完成實測；iPhone側載成功不是證據 |

具體玩法與限制見 [CAPABILITY-MAP.md](CAPABILITY-MAP.md)。先選能保留寵物需求的交付路線，再決定是否做現成工具的短期版本。

## 已準備：手動 Apple 編譯與診斷

[apple-build.yml](../.github/workflows/apple-build.yml) 保留手動入口，另只允許 `codex/apple-watch-integration` 這條私人開發分支的 push 觸發，讓第一次驗證不需要改動 main。沒有 PR／定時觸發；同分支新版本取消仍在跑的舊版本。權限 `contents: read`，不需要 Apple secrets，不自行下載 Xcode。macOS 執行使用 Actions 額度；實际 run 與結果見 [10月5日編譯紀錄](APPLE-BUILD-20261005.md)。[I06][I20]

[build_apple_simulators.sh](../tools/build_apple_simulators.sh) 會：

1. 列出當時 Xcode 和 SDK，檢查共享 `PatrickFace`／`PatrickCompanion` schemes。
2. 實際編譯並執行三組 Foundation 測試：原生舊規則、atlas／輪廓／排程規則、陪伴狀態／照顧／計時／日期去重。
3. 無簽名編譯 Watch App＋complication、iPhone App＋widget，再用 `build-for-testing` 編譯 XCTest target。這一步尚不啟動模擬器跑 XCTest。
4. 用 [check_apple_bundle.py](../tools/check_apple_bundle.py) 檢查 **產出的** iPhone App 內確實有 `Watch/PatrickFace.app` 與兩個 extensions、bundle IDs／四產品版本一致、所有逐幀與 Experience 資源的 SHA 正確。

手動 workflow 可勾選 `unsigned_device_archive`，再對 `generic/platform=iOS` 做無簽名 Release archive，檢查實際 archive 內的 Watch payload。無簽名 simulator／device archive 均不能裝到手錶或提交 TestFlight。workflow 只保留編譯紀錄為目前私有 repo 的診斷 artifact，7天到期；不上传 IPA、不發公開 release，也不提交 Apple。出錯時保留原始 compiler／project 錯誤供修復。

真正啟動前需把這份具體版本放到私有倉庫，並確認目前可用的 macOS 額度；手動入口要求 workflow 已在預設分支。[I20] 借到 Mac 時，也可從根目錄執行 `bash tools/build_apple_simulators.sh`。要實際跑模擬器 XCTest，另用 `iOSCompanion/tools/verify_companion_on_mac.sh`，它只選已安裝的 iPhone runtime，不自行下載。

### 簽名、匯出與 Watch 內嵌檢查

[archive_apple.py](../tools/archive_apple.py) 已準備兩種明確模式，尚未執行：

- 不帶 `--signing-config`：只做無簽名 device archive 與內嵌檢查。
- 帶本機設定 `--signing-config /絕對路徑/實際設定.json`：使用這台 Mac 已安裝的憑證及 profiles，做手動簽名 archive，再 **只匯出到本機**。不帶 `-allowProvisioningUpdates`，不建立／下載 profiles，不連 Apple 提交程式。

[apple-signing.example.json](../tools/apple-signing.example.json) 是不能直接執行的範本；填入自己的 Team ID、簽名憑證種類、四個 profile 名稱。不要把密碼、`.p12` 私鑰或 `.mobileprovision` 放入版本庫。選擇 `app-store-connect`（私人 TestFlight）、`release-testing`（已註冊裝置）或 `debugging`，以使用的 Xcode 支援的 export method 為準；最初選用的 profiles 必須符合該方法及四個 entitlements。

| Target | 目前 bundle ID | 需要的能力 |
|---|---|---|
| iPhone App | `com.chans.patrickface.companion` | App Group |
| iPhone widget／Live Activity | `com.chans.patrickface.companion.widgets` | 同一 App Group |
| Watch App | `com.chans.patrickface.companion.watchkitapp` | 同一 App Group、HealthKit read |
| Watch complication | `com.chans.patrickface.companion.watchkitapp.complications` | 同一 App Group |

共用 App Group 是 `group.com.chans.patrickface.shared`。四個 target 使用同一 Team；profiles 名稱由各 target 自己的 `PATRICK_*_PROFILE` 變數帶入，不能把同一 profile 強套四個 bundle。若 bundle ID／App Group 已被其他團隊占用，必須一起更新工程、entitlements、Watch 配對鍵、shared store 及驗證器。`--build-number` 會一致套用四個產品，修正 Watch Info.plist 先前寫死 build 1 的問題。

iPhone 工程已宣告 Watch cross-project dependency 與 `Embed Watch Content`，Watch App 內再嵌 complication。Watch 設定 `WKCompanionAppBundleIdentifier` 指向 iPhone ID、`WKWatchOnly=false`、`WKRunsIndependentlyOfCompanionApp=true`。這表示配對套裝中的 Watch 可獨立運行，不表示這是 watch-only 分发工程。Apple 的現代單一 Watch app target 不另需要舊式 WatchKit app extension。[I21]

匯出選項固定 `destination=export`、不上传 symbols；私人 TestFlight 方法預設 `testFlightInternalTestingOnly=true`。正式上传仍是其後的獨立動作，且要先有會員、正確簽名、App Store Connect app record，並跑過 Apple 編譯和核心真機測試。[I22]

## 路線 A：Windows＋雲端 macOS＋私人 TestFlight

這是有普通配對 iPhone 時，最容易持續迭代完整原生寵物的方案。私人內部測試不要求公開商店頁面或公開邀請連結；它仍是 Apple 的測試分發服務。[I02][I03]

1. 在 Windows 完成源碼、素材與本地邏輯檢查；保留私有版本庫。
2. 在有合適 Xcode／watchOS SDK 的 macOS runner做**無簽名的編譯／模擬器測試**，先暴露真實 Swift、asset catalog 和工程錯誤。這一步不等於可安裝的真機程式。
3. 用使用者自己的 Apple Developer Program 團隊設定 bundle IDs、App Group、簽名憑證與 profiles。現有四個產品 target 應同團隊；若既有識別碼不能註冊，需要一併改工程與通訊關聯，而非只改一處名稱。
4. 在 macOS runner archive／export並檢查 watch payload、extension、entitlements、deployment target。GitHub 官方有匯入簽名憑證及profile的CI流程；敏感值存repository secrets，不提交 `.p12`、私鑰、密碼或profile進源碼。[I01]
5. 建立 App Store Connect app record並上傳build，等待Apple處理。建立自己的內部測試群組；符合角色的帳號可加入。[I02]
6. 在**與Watch配對的iPhone**安裝TestFlight，接受內部邀請。現有companion套裝先裝iPhone版，再在TestFlight詳細頁安裝相容Watch版本；watch-only build也從配對iPhone的TestFlight列表安裝。[I04]
7. 先驗最小閉環：冷啟動→摸摸／換衣→重開保存→手機設定傳到Watch→離線Watch仍可玩。然後才測健康、NFC、背景或運動整合。

**有效期限**：每個TestFlight build自上傳起最多90天，到期不能再開啟；應在到期前提供新build並安裝。不要把它描述成一次安裝永久有效。內部測試不等於取消Apple服務條件，也不是將他人隨意加為管理員的理由。[I03][I04]

**費用**：Apple Developer Program為US$99／會員年度，地方價格以註冊顯示為準。[I05] GitHub私有repo有按帳號方案的Actions額度；超出才依服務計費／額度限制處理。查證日官方標準macOS 3／4 core費率為US$0.062／分鐘，另有artifact儲存計費；應先設預算及短artifact保留期，不能保證所有使用量免費。[I06]

## 路線 B：Xcode Cloud或租借Mac

Apple Developer Program目前包含Xcode Cloud **25 compute hours／月**，可build、test、archive並分發到TestFlight；它的首次workflow配置仍需在Xcode完成，第一輪完成後可在App Store Connect管理更多workflow。[I07][I08]

因此：

- 借用一次Mac或租用遠端Mac，可初始化Xcode Cloud、設定簽名與排除工程問題；以後主要在Windows改程式。
- 只有瀏覽器和Git repo時，不能宣稱首次Xcode Cloud完全不用接觸Xcode。GitHub macOS CI則可用檔案設定workflow，但仍要準備合法有效的簽名資料。
- 雲端Mac不在使用者手錶旁邊。一般遠端桌面連線不會自動把本地Watch變成Xcode可調試設備；採TestFlight讓設備自行下載，比承諾遠端USB／藍牙透明轉接務實。
- 不需要把Apple Account密碼交給陌生人代簽；可使用自己的帳號及適當權限。服務供應商的地區、儲存隔離、Xcode版本和收費另於選購時核對，本文件不估造租金。

## 路線 C：免費 Personal Team

Apple官方允許免費Apple Account在Xcode建立Personal Team做個人裝置測試，並列出：[I09]

| 限制 | 實際影響 |
|---|---|
| 最多10個App IDs，7天有效 | 多target工程會用到多個識別碼，不能把一個App等同只佔一個ID |
| 最多3部註冊裝置，7天有效 | 配對測試需要逐裝置確認，不能任意擴散安裝 |
| 每裝置最多3個App | 需檢查裝置現有開發App數量 |
| 安裝用profile簽發後7天到期 | 需要重新建置及安裝；沒有免費永久安裝承諾 |
| 無TestFlight分發服務 | 不能把免費Apple Account當付費團隊的TestFlight替代 |

**不要使用過時理由判定必敗**：截至查證日，Apple iOS capability表的App Groups三個會員欄均有支援勾選（已核對HTML `alt="yes"`）；watchOS表也明說watch app target的App Groups／background modes不依會員種類。是否能讓本工程全部target實際完成Personal Team簽名，仍須以當前Xcode結果驗證。[I10][I11]

此路線適合借得到Mac、能接近並配對實機、願意週期維護的人。雲端僅產出檔案尚不足證明可從Windows完成Watch免費重簽安裝。

## 路線 D：Ad Hoc／註冊裝置開發安裝

Apple官方支援將watchOS app發給註冊裝置，不必經公開App Store發布；先登記需要測試的裝置，將它們包含在相應profile，archive後匯出簽名產物。每個會員年度每個產品家族有註冊額度；對本任務只需自己的裝置。[I12][I13]

官方說明的安裝工具是Xcode／Device Hub或Apple Configurator，使用IPA安裝的iOS／watchOS開發測試需開啟Developer Mode。這與App Store／TestFlight安裝路線不同。[I12]

這條路可以少一個TestFlight環節，但要先回答：如何取得正確Watch識別碼、如何讓安裝工具連上本地裝置、profile與所有嵌入target是否相符、到期後如何更新。**不能僅因匯出IPA成功，就宣稱Windows端可把watch部分裝好。**目前未驗證本專案的Ad Hoc端到端安裝。

## 路線 E：Clockology外觀／簡單互動版

Clockology可從App Store安裝，使用者匯入內容不需要替本專案自己申請開發者簽名。官方列出圖層、影片／動畫、聲音、互動按鈕切換圖層、時間、活動與電池資訊。[I14]

可重用的是角色圖片、分層與動畫素材；應另製作其支援的clock格式並在iPhone編輯器確認。原生Swift工程、WatchConnectivity契約、養成資料及任意遊戲規則不會因匯入圖片自動運作；本倉庫交付包不應僅改副檔名當成Clockology成品。

其全螢幕clock檔案仍在App內執行。官方FAQ要求Return to Clock設為一小時並至少每小時喚醒一次，也說長時間通知可能回原生錶面。原生complication類型另有邊界，不能混稱永久第三方系統錶面。[I15]

若採此路線，驗收是：真機可匯入→手臂角度正確→動畫觸發→返回App→省電表現；再決定是否足夠。免費／訂閱功能範圍應在使用者所在地App Store確認，本文件不承諾所有功能免費。

## 只有Watch或家人設定

Independent watch app可以不安裝companion也運作，但**獨立運作與beta如何安裝是兩個問題**。Apple目前TestFlight說明仍要求配對的iPhone，包括watch-only app。[I04][I16]

Apple Watch For Your Kids（前Family Setup）允許家人沒有自己的iPhone，但初次設定仍要管理者iPhone，並有cellular Watch型號、Apple Account、Family Sharing和地區條件。部分依賴companion的功能不提供。[I17]

本次沒有找到官方保證「管理者iPhone可把自己的TestFlight邀請安裝到家人Watch」的完整特殊流程。因此若使用者屬這種情況，先驗目前管理方式與可用App Store／beta入口，再選交付法。不能為了猜測安裝方案就先解除配對、抹除或要求重設手錶。

## 非官方安裝的查證結果

AltStore官方入門主要為iPhone／iPad；Sideloadly官方描述iOS、Apple Silicon與tvOS。兩者存在Windows工具／自動重簽說明，**不構成Watch payload可被保留、正確簽名及傳到Watch的證明**。[I18][I19]

目前結論是未驗證，不是「網上有人說可用所以已解決」，也不武斷宣稱任何非官方方案永遠不可能。若繼續研究，需對應使用者的確切版本，查維護中原始專案、已知問題與實際Watch安裝記錄；付費企業簽名服務並不能代替這個驗證。

## 第一次真機驗收清單

- 確認型號、OS、配對方式、Apple團隊與build有效期。
- 從安裝入口成功安裝，Watch app可自行冷啟動；不是只看到iPhone圖示。
- 重啟App後衣服／心情／寵物進度保存；手機離線仍可操作基本寵物。
- 手機與Watch雙向同步能區分立即套用、排隊、失敗；重複訊息不重複獎勵。
- Watch充電、滿電、低電量與unknown分清；手機充電不改Watch電池狀態。
- 普通觸控、Digital Crown離開、返回時鐘、Always-On、Focus和靜音均測一次。
- 只有用到時才測健康／照片／定位／通知權限；拒絕後仍可玩基本寵物。
- 記錄簽名與安裝方法、build號、測試結果、更新方法；模擬器PASS不替代這張表。

## 來源索引

全部於2026-09-27查閱。費率、系統支援與服務要求可能改變，真正安裝前應再次核對。

[I01]: https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications "GitHub — Sign Xcode applications on macOS runners"
[I02]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers "Apple — Add internal testers"
[I03]: https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/ "Apple — TestFlight overview"
[I04]: https://testflight.apple.com/ "Apple — TestFlight installation and expiry"
[I05]: https://developer.apple.com/programs/enroll/ "Apple — Developer Program fee"
[I06]: https://docs.github.com/en/billing/concepts/product-billing/github-actions "GitHub — Actions billing"
[I07]: https://developer.apple.com/xcode-cloud/get-started/ "Apple — Xcode Cloud requirements and quota"
[I08]: https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow "Apple — First Xcode Cloud workflow"
[I09]: https://developer.apple.com/help/account/basics/about-your-developer-account "Apple — Personal Team limits"
[I10]: https://developer.apple.com/help/account/reference/supported-capabilities-ios "Apple — iOS capability table"
[I11]: https://developer.apple.com/help/account/reference/supported-capabilities-watchos "Apple — watchOS capability table"
[I12]: https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices "Apple — Registered-device installation"
[I13]: https://developer.apple.com/help/account/provisioning-profiles/create-an-ad-hoc-provisioning-profile "Apple — Ad Hoc profiles"
[I14]: https://clockologyapp.com/about-us/ "Clockology — Features"
[I15]: https://clockologyapp.com/faq/ "Clockology — Device and runtime limitations"
[I16]: https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps "Apple — Independent watch apps"
[I17]: https://support.apple.com/en-us/109036 "Apple — Family setup"
[I18]: https://faq.altstore.io/ "AltStore — Official documentation"
[I19]: https://sideloadly.io/ "Sideloadly — Official supported platforms"
[I20]: https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow "GitHub — Manually running a workflow"


## 本輪原生行為驗收

本機已通過工程／plist／雙端 v1 DTO 結構檢查與包裝檢查器的3項負面回歸（缺 Watch complication、素材遭改、版本不一致）。這些不是 Swift 編譯結果。新增 Foundation／XCTest 測試已寫入上述 Mac pipeline，Windows 尚未執行。

上手錶後依序核對：

1. 首頁大數字每分鐘獨立更新；缺素材或暫停時仍顯示時間。原味手臂時計以 manifest 的真分層資料顯示當下時分，播放動作時讓位，動作結束恢復當前時間。
2. 換衣／心情／聲音／觸覺／日期／24小時設定，關App重開仍保留；已選特定衣服但沒有動作時只回應文字和照顧，不偷換成別套衣服。auto 可按動作切換預設演出衣服。
3. 餵食冷卻3秒，+12飽足／+2親密；摸摸+1親密；數值0–100。飽足按離線經過時間每小時減1.5，最多每分鐘保存一次，不靠背景常駐。
4. 陪伴計時10秒至120分鐘：暫停凍結、繼續換新截止時間、取消不是完成、自然完成只記一次。手機鎖屏倒數／Dynamic Island 和 Watch 同步要真機確認；這不是 HealthKit workout。
5. 自動作息可調，預設22:00–06:00，跨午夜正確；相同起訖停用。生日只存 `MM-DD`，允許2/29；節日只讀內建精確日期（目前5個固定節日＋18筆HKO 2026–2028農曆日期，生日優先於固定節日、固定節日優先於農曆），資料缺失不猜日期。當日去重；quiet觀察到的事件不排隊補演。
6. 抬腕前景才跑逐幀；腕下、背景、設定面板、減少動態、低耗電時靜止；待機眨眼不發聲／震動。哈欠睡前進入一次，冷卻10分鐘，沒有不停循環。
7. 用普通配對 iPhone 測 reachable、離線、延遲與重複送達；新 experience 狀態時間戳用 epoch ms，旧 v1 外層日期仍ISO8601；過期照顧指令不補播，不重複獎勵。
8. HealthKit 首次按鈕授權、空資料、讀取失敗、重新整理，顯示樣本時間。不能把授權請求完成等同已取得讀取權限；Apple 刻意不公開是否拒絕讀取。[I23]
9. 快捷指令「照顧」「情境」「心情」「陪伴計時」可作為 iPhone 自動化的後續動作。App 本身沒有 NFC 掃描；iPhone 充電自動化不代表 Watch 充電。聲音只在 App 前景並遵循開關；實際 Watch 喇叭／靜音行為須真機試聽。[I24][I25]

### 本輪補充官方來源（2026-09-27）

- [I21] Apple TN3157，現代 Watch app 與 companion 內嵌關係：https://developer.apple.com/documentation/technotes/tn3157-updating-your-watchos-project-for-swiftui-and-widgetkit
- [I22] Apple archive 與分發、私人內部 TestFlight選項：https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases
- [I23] Apple HealthKit讀取授權與隱私：https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data
- [I24] Apple WatchConnectivity 狀態與排隊傳送：https://developer.apple.com/documentation/watchconnectivity/transferring-data-with-watch-connectivity
- [I25] Apple AVAudioPlayer：https://developer.apple.com/documentation/avfaudio/avaudioplayer；Watch觸覺：https://developer.apple.com/documentation/watchkit/wkinterfacedevice/play(_:)

Apple SDK 編譯、圖形像素方向、效能／記憶體、Watch 喇叭、HealthKit 取樣、WC真機時序與簽名安裝仍是未完成驗收項；沒有假造成功的安裝包。
