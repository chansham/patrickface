# 私人安裝與沒有 Mac 的開發路線

首次資料查證：2026-09-27；帳號、安裝條件與 Apple 官方資料複核：2026-10-05。此文件提供可選路線與驗收門檻。私人 GitHub macOS runner 已完成下述無簽名編譯與測試；簽名、真機安裝仍未完成。沒有購買服務、建立 Apple 帳號或操作手錶。9 月 27 日的歷史資料與本次新增證據分別標示。

## 2026-10-06 最新套件（取代下文build6作為下一次試裝輸入）

使用者已說稍後再連接手機，本輪先完成四款App內錶面、啞鈴定位、散步／跑步／肌力陪伴分類、計時控制捷徑及首次暫停Live Activity修復。`8582124`的[Apple run37400635967](https://github.com/chansham/patrickface/actions/runs/37400635967)全部成功：1734項Foundation、12項XCTest、12項封裝測試、四產品編譯、無簽名裝置封存及兩端四版式截圖。下文10月5日結果保留為歷史。

最新輸入為[未簽名build8](../output/apple-build/run-37400635967-artifacts/patrick-unsigned-resigning-input-8/PatrickCompanion-unsigned.ipa)，版本1.0，45,251,085 bytes；SHA256 `d3011b73a023144ebc2593fa3e226bd0bd33c643f1cae872b6a1e2393615729a`。下載後156項內容及四產品已逐項核對，報告與manifest／checksum放在同目錄。它仍需重簽，不能直接安裝；沒有操作Apple登入、Sideloadly或使用者裝置。詳見[本輪整合紀錄](INTEGRATION-20261006.md)。

## 現在已知與待確認

- 使用者使用 Windows、沒有 Mac；目前使用 iPhone 13 Pro 及配對的 Watch，Watch 型號自報為 Series 12 46 mm，計畫換 iPhone 18 Pro Max。2026-10-05 已明確確認只有一般 Apple 帳號，**沒有付費 Apple Developer Program 會員**。實際 OS 小版本、Watch 型號號碼尚未讀取；詳見 [裝置紀錄](DEVICE-PROFILE-2026-09-27.md)。
- 2026-10-05 使用者指定改用 `chansham` 並完成 GitHub 登入授權；新建 `chansham/patrickface` 已確認 **PRIVATE**。獨立開發分支已完成 Apple 編譯；原 `<GITHUB_USER>/patrickface` 保留。GitHub 授權不等於 Apple 簽名或付費會員。
- Windows 已接好原生首頁、數字時間、逐幀素材、原味手臂時計、衣服／情境／心情、照顧、音效／觸覺、作息、生日與確切日期節日、陪伴倒數及手機同步的源碼。iPhone widget、Watch complication 改讀同一份陪伴狀態；舊整圖晃動頁不再是首頁。
- Watch 健康摘要只在按下按鈕後請求 **read-only** 今日步數、最近心率及 HRV，附資料時間；沒有樣本顯示「尚無資料」，不推斷拒絕權限或人的心情，不啟動假健身 session。
- **Apple 編譯已通過，簽名與真機仍未完成。**2026-10-05 的 `f6daa08`／[run 37254670555](https://github.com/chansham/patrickface/actions/runs/37254670555) 全部成功：1,695 項 Foundation 檢查（1503＋129＋63）、9 項 XCTest 實跑、iPhone／Watch 雙平台及兩個 extensions 編譯、四個 product 的版本／ID／素材 SHA 檢查、無簽名 Release device archive。XCTest 在 iPhone Air／iOS 26.5 模擬器執行；runner 為 Xcode 26.6、iOS／watchOS SDK 26.5。這些不是 Series 12／OS 27 真機證據；詳細記錄見 [本次紀錄](APPLE-BUILD-20261005.md)。素材仍為開發稿，沒有因編譯通過而取得美術批准。
- 沒有自己的 Mac 不等於必須買 Mac：借用／租用遠端 Mac 或 macOS CI 可以編譯，但仍要處理簽名和真機交付。[I01]

## 如何選擇

| 條件與目的 | 首選路線 | 仍需要什麼 |
|---|---|---|
| 目前免費帳號，借得到可連接真機的 Mac | Xcode＋免費 Personal Team 開發安裝 | 四個 target 實際完成簽名／安裝；每 7 天重新建置安裝，須能持續取得 Mac 使用權 |
| 日後自行選擇付費會員，要從 Windows 持續迭代 | Windows 開發＋macOS CI／遠端 Mac＋私人 TestFlight 內部測試 | Apple Developer Program、簽名設定及有效 build；目前沒有會員，未啟用此路線 |
| 先把角色外觀戴上去，願意使用現成工具的互動能力 | Clockology 的 iPhone編輯／匯入與Watch App | 相容iPhone／Watch、重新製作成其支援格式；完整養成邏輯不保證可做 |
| 不經TestFlight，要給自己的註冊裝置安裝 | 付費會員＋Ad Hoc／development provisioning | Watch與相關裝置識別碼、有效profile、已驗證的本地安裝管道 |
| 只有家人設定的Watch，沒有一般配對iPhone | 先驗 independent watch app與該設定的安裝管道 | 不能假設管理者iPhone能按普通配對流程安裝TestFlight；可能先用現有獨立App驗入口 |
| 想從 Windows 安裝完整 iPhone＋Watch 套裝 | **Sideloadly v0.70.1 是有官方更新紀錄支持的可測試候選**；AltStore 另列未驗證 | Sideloadly 已明列保留及重簽 WatchKit App、更新 bundle IDs；免費帳號、目前 iOS／watchOS 27、實際 Watch 安裝與續期仍待實測。[I29] |

目前以使用者的 **Windows＋iPhone＋Watch、沒有可用 Mac、沒有付費會員** 為前提；使用者沒有選擇借 Mac 或 TestFlight。下列 Mac／付費路線僅保留為有條件的說明，不要求使用者尋找 Mac 或購買會員。免費帳號＋可用 Mac 是有官方依據的個人裝置測試途徑；Sideloadly v0.70.1 已提供可測試的 Windows 候選，但純 Windows 免費安裝完整 iPhone＋Watch 套裝的端到端結果仍未證實。[I29] 具體玩法與限制見 [CAPABILITY-MAP.md](CAPABILITY-MAP.md)；Clockology 僅是另行製作的外觀／簡單互動版本，不是本原生 App 的等效交付。

## 已通過：Apple 編譯與診斷

[apple-build.yml](../.github/workflows/apple-build.yml) 保留手動入口，另只允許 `codex/apple-watch-integration` 這條私人開發分支的 push 觸發，讓第一次驗證不需要改動 main。沒有 PR／定時觸發；同分支新版本取消仍在跑的舊版本。權限 `contents: read`，不需要 Apple secrets，不自行下載 Xcode。macOS 執行使用 Actions 額度；實际 run 與結果見 [10月5日編譯紀錄](APPLE-BUILD-20261005.md)。[I06][I20]

[build_apple_simulators.sh](../tools/build_apple_simulators.sh) 會：

1. 列出當時 Xcode 和 SDK，檢查共享 `PatrickFace`／`PatrickCompanion` schemes。
2. 實際編譯並執行三組 Foundation 測試：原生舊規則、atlas／輪廓／排程規則、陪伴狀態／照顧／計時／日期去重。
3. 無簽名編譯 Watch App＋complication、iPhone App＋widget，再用 `build-for-testing` 編譯 XCTest target。隨後從已安裝且 scheme 支援的 iPhone 模擬器選取 UDID，以同一份產物執行 `test-without-building`；沒有可用 runtime 時明確失敗，不下載替代 runtime。
4. 用 [check_apple_bundle.py](../tools/check_apple_bundle.py) 檢查 **產出的** iPhone App 內確實有 `Watch/PatrickFace.app` 與兩個 extensions、bundle IDs／四產品版本一致、所有逐幀與 Experience 資源的 SHA 正確。

手動 workflow 可勾選 `unsigned_device_archive`，私人開發分支 push 則在前述驗證通過後自動對 `generic/platform=iOS` 做無簽名 Release archive，檢查實際 archive 內的 Watch payload。**`9d6e095` 已提交及推送新版 workflow**：archive 步驟新增 `--package-unsigned`，通過封裝檢查後，把未簽名 IPA、manifest 與 SHA256 檔存為私人倉庫的 `patrick-unsigned-resigning-input-<run number>` artifact，保留 **7 天**；診斷 log、XCTest result bundle 及後續模擬器截圖另存診斷 artifact，同樣保留 7 天。

這是供 Windows 工具重新簽名的輸入，不是已簽名成品；**未簽名 IPA／archive 不能直接安裝到裝置或提交 TestFlight**。workflow 不發公開 release，也不提交 Apple。`9d6e095` 的 [run 37256581810](https://github.com/chansham/patrickface/actions/runs/37256581810) 已全部成功：原有1695項Foundation及9項XCTest再通過、12項封裝測試全部通過，未簽名IPA已下載並再次驗證154個項目。真正46mm Watch模擬器截圖也已實看，時間安全區與角色頭腳正常。具體版本、SHA及實機界線見 [本次紀錄](APPLE-BUILD-20261005.md)。

本次已從私人開發分支的 push 執行成功；後續仍需依使用者帳號的 macOS 額度安排建置。手動入口要求 workflow 已在預設分支。[I20] 借到 Mac 時，也可從根目錄執行 `bash tools/build_apple_simulators.sh`，其中包含實跑 XCTest 的步驟；需要單獨驗證 companion 時，可用 `iOSCompanion/tools/verify_companion_on_mac.sh`，它只選已安裝的 iPhone runtime，不自行下載。

### 簽名、匯出與 Watch 內嵌檢查

[archive_apple.py](../tools/archive_apple.py) 區分下列用途：

- 不帶 `--signing-config` 或 `--package-unsigned`：只做無簽名 device archive 與內嵌檢查；`f6daa08` 已通過。
- 帶 `--package-unsigned`：以 macOS `ditto` 複製及封裝四個原始 device 產品；核對原 bundle IDs／版本、iPhoneOS／WatchOS、每檔 SHA／類型／權限及符號連結，再核對 ZIP 內容。第六輪已產出版本1.0／build6，僅供重新簽名。未刪除 Watch、extensions、素材或修改原始檔案來避過檢查。
- 帶本機設定 `--signing-config /絕對路徑/實際設定.json`：使用這台 Mac 已安裝的憑證及 profiles，做手動簽名 archive，再 **只匯出到本機**。不帶 `-allowProvisioningUpdates`，不建立／下載 profiles，不連 Apple 提交程式。這個簽名模式尚未執行，並與 `--package-unsigned` 互斥。

manifest 的 `entitlementRequirements` 是四份**源碼 entitlement 模板**及其 SHA、App Group／HealthKit 要求，並非已簽名 IPA 中實際有效的權限。未簽名包明列 `signed=false`、`directlyInstallable=false`；重新簽名後必須另查四個產品的實際 entitlements 與 provisioning profiles。

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

## 目前 Windows 試裝（尚未執行）

先使用官方 **Sideloadly v0.70.1** 作候選，保持 Windows＋iPhone＋配對 Watch，不要求 Mac 或付費會員。以下是待實作的流程；目前尚未登入 Sideloadly、替帳號簽名或完成裝置安裝。[I19][I29]

**使用者於10月5日選擇稍後再試裝。**試裝輸入已準備好，接續時從連接iPhone開始，不要求重新授權GitHub或尋找Mac。

1. 已下載並核對的檔案位於 `output/apple-build/run-37256581810-artifacts/patrick-unsigned-resigning-input-6/`：`PatrickCompanion-unsigned.ipa`（45,178,729 bytes）、完整manifest及`.ipa.sha256`。IPA SHA256為`a60802223ff36887de9ce4866e5ef2c1b1cc2bcc45d08ce882da54ecb2d34319`。可直接取本機檔案，不需自行拆包／改名或刪檔；私人GitHub artifact保留7天不影響本機副本。
2. 只從 [Sideloadly 官網](https://sideloadly.io/)取得 Windows 版，確認至少包含 v0.70.1 的 WatchKit 改進。依官網要求核對 Windows 的 Apple iTunes／iCloud 元件；先以 USB 連接並解鎖 iPhone，在手機出現提示時信任這台 PC，確認工具能辨識裝置。[I19][I30]
3. 將 IPA 載入 Sideloadly，**由使用者自行輸入 Apple 帳號、密碼及兩步驗證**。保留 Watch App 與兩個 extensions，不使用刪除 extensions／Watch 子包來換取手機端安裝成功。原套裝的 bundle ID 關聯與共用資料必須一起驗證；不憑猜測指定尚未確認的進階 UI 選項。[I19][I29]
4. 依裝置實際提示處理 Developer Mode 與開發者信任。Sideloadly FAQ 的 iPhone 位置是「設定 → 隱私權與安全性 → 開發者模式」；若出現不受信任開發者，依「設定 → 一般 → VPN 與裝置管理」的相應帳號完成信任。Watch 的 Developer Mode／信任亦需按實際狀態處理；選項未出現時保留畫面與原錯誤，不假稱已開啟。[I26][I30]
5. 手機成功後，仍要確認 Watch 端確實安裝並可冷啟動，兩個 extensions 保留，手機／Watch 設定可往返，重開後資料保存。若只能裝手機、Watch 不出現或回報簽名錯誤，記錄為部分成功並保留錯誤；不宣稱套裝已完成。
6. 免費帳號有效期為 7 天。官方說明自動續期需電腦上的 Sideloadly Daemon 運行，並透過 USB 或已設定的同網路 Wi-Fi 偵測裝置；更新沿用同一 Apple 帳號與 bundle ID。這是一般 App 的續期機制，**本專案 Watch 子包及其 extensions 能否一併正常續期仍需實測**。[I30]

**本工程的具體驗收點：**四個 target 的源碼共用群組是 `group.com.chans.patrickface.shared`，程式讀取也使用此固定值。若重簽工具只改 entitlements 的群組名稱，程式仍讀原值，widget／complication 共用資料可能失效；必須檢查重簽後的實際值與程式是否一致。Watch 的 HealthKit 權限也要對照實際 profile。manifest 中的源碼模板、Sideloadly 宣告能重簽 WatchKit，以及一般免費帳號支援，三者都不代替上述實測。

## 路線 A：Windows＋雲端 macOS＋私人 TestFlight

這是**日後選擇付費會員時**可用的持續迭代方案；目前使用者沒有會員，尚未設定或啟用 TestFlight。此路線不要求使用者擁有 Mac，但編譯及簽名仍在合適的 macOS／Xcode 環境進行。私人內部測試不要求公開商店頁面或公開邀請連結；它仍是 Apple 的測試分發服務。[I02][I03]

1. 在 Windows 完成源碼、素材與本地邏輯檢查；保留私有版本庫。
2. 在有合適 Xcode／watchOS SDK 的 macOS runner做**無簽名的編譯／模擬器測試**，先暴露真實 Swift、asset catalog 和工程錯誤。這一步不等於可安裝的真機程式。
3. 用使用者自己的 Apple Developer Program 團隊設定 bundle IDs、App Group、簽名憑證與 profiles。現有四個產品 target 應同團隊；若既有識別碼不能註冊，需要一併改工程與通訊關聯，而非只改一處名稱。
4. 在 macOS runner archive／export並檢查 watch payload、extension、entitlements、deployment target。GitHub 官方有匯入簽名憑證及profile的CI流程；敏感值存repository secrets，不提交 `.p12`、私鑰、密碼或profile進源碼。[I01]
5. 建立 App Store Connect app record並上傳build，等待Apple處理。建立自己的內部測試群組；符合角色的帳號可加入。[I02]
6. 在**與Watch配對的iPhone**安裝TestFlight，接受內部邀請。現有companion套裝先裝iPhone版，再在TestFlight詳細頁安裝相容Watch版本；watch-only build也從配對iPhone的TestFlight列表安裝。[I04]
7. 先驗最小閉環：冷啟動→摸摸／換衣→重開保存→手機設定傳到Watch→離線Watch仍可玩。然後才測健康、NFC、背景或運動整合。

**有效期限**：每個TestFlight build自上傳起最多90天，到期不能再開啟；應在到期前提供新build並安裝。不要把它描述成一次安裝永久有效。內部測試不等於取消Apple服務條件，也不是將他人隨意加為管理員的理由。[I03][I04]

**費用**：Apple Developer Program為US$99／會員年度，地方價格以註冊顯示為準。[I05] GitHub私有repo有按帳號方案的Actions額度；超出才依服務計費／額度限制處理。2026-09-27 查證時官方標準macOS 3／4 core費率為US$0.062／分鐘（10 月 5 日未重新核價），另有artifact儲存計費；應先設預算及短artifact保留期，不能保證所有使用量免費。[I06]

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

**2026-10-05 官方複核**：iOS 與 watchOS 能力表的免費 Apple Developer 欄，**App Groups、HealthKit 均有支援勾選**；已核對原頁 HTML 的 `alt="yes"`，不是把純文字表格的空白誤讀成不支援。因此不能以這兩項為理由要求付費或預先刪除功能。這只證明官方列出的能力範圍，**不代表本工程四個 target 已完成 Personal Team 簽名**。[I10][I11]

本工程有四個產品識別碼，widget／complication 各自需要符合所選團隊的簽名與共用 App Group。四個 target 不等於在同一手機安裝四個獨立 App，也不能忽略帳號已佔用的 App IDs。WatchConnectivity 的手機與 Watch 關聯、Widget 共用資料仍須在真正簽名及安裝後驗證；目前的 Foundation／XCTest 成功不代替這些實機驗收。

此路線適合借得到 Mac、能讓 Xcode 與實機配對、願意每週維護的人；**借用一次 Mac 不等於永久安裝**。目前 Apple 的 Device Hub 文件允許 iOS 27 及後續版本在同一 Wi-Fi 網路無線配對 Mac；較舊 iOS 可用連接線，Watch 先處理 companion iPhone。iPhone 與 Watch 都需開啟 Developer Mode 並完成信任。一般遠端桌面不會自動建立這條裝置連線；雲端只產出檔案，仍不足以證明 Windows 可完成 Watch 免費重簽、安裝及續期。[I09][I26]

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

**2026-10-05 新增直接證據：Sideloadly v0.70.1 官方 changelog 明確說明，現在預設保留 WatchKit App，重新簽名並更新 bundle IDs；此前會剝除這部分。**因此 Sideloadly 已由只有一般 iOS 側載資訊，升級為本專案在 Windows 上的**具體可測試候選**。首頁沒有單獨列出 Watch，不能蓋過這份明確的新版更新紀錄。[I19][I29]

這項改進證明工具宣告處理 WatchKit 子包，尚不證明使用者的免費帳號、目前 iOS／watchOS 27 與本專案四個產品一定可完成安裝。需驗證重新簽名後的 bundle ID 關聯、App Group／HealthKit 與各 profile，以及 Watch 端實際安裝、冷啟動和到期前續期；iPhone 側載成功或一般 App 自動續期說明都不能代替 Watch 端結果。本次沒有安裝、登入或實機測試。

AltStore 官方 Windows 安裝說明確認的是 iOS 裝置。[I18][I27] 其 Watch App resigning 議題 #229 仍為開放的 enhancement；維護者於 2020-05-28 回覆當時尚不具備 WatchOS App 安裝能力。這是維護者的歷史說明，不是 2026 年所有版本必然不支援的證明。本次未找到維護者對上述完整 Watch 流程的現行保證，也未在使用者裝置實測。[I28]

目前結論分開記錄：**Sideloadly v0.70.1 有維護者發布的 WatchKit 保留／重簽能力證據，但本專案尚未完成端到端實測；AltStore 的完整 Watch 安裝仍未證實。**接下來應對應使用者的確切版本與本工程驗證，不把候選方案寫成已安裝成功，也不宣稱所有非官方方案都不可行。

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

基礎來源於 2026-09-27 查閱。2026-10-05 再讀 Apple 帳號／免費能力表／配對與裝置分發文件、TestFlight 安裝說明，以及 AltStore／Sideloadly 官方資料；新增來源 I26–I30 於 10 月 5 日查閱；I29 的 Sideloadly v0.70.1 WatchKit 更新證據已納入，取代僅依首頁平台清單所能得到的有限結論。其他來源（尤其雲端費率與配額）仍按原查證日期，不表示本次全部重新核價。裝置與 Xcode 新版核對另見 [裝置紀錄](DEVICE-PROFILE-2026-09-27.md)。

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
[I26]: https://developer.apple.com/documentation/xcode/managing-your-simulated-and-physical-devices-in-device-hub "Apple — Device Hub pairing"
[I27]: https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows "AltStore — Windows installation"
[I28]: https://github.com/altstoreio/AltStore/issues/229#issuecomment-635651937 "AltStore maintainer — Historical Watch app support request"
[I29]: https://sideloadly.io/changelog "Sideloadly v0.70.1 — WatchKit apps retained and re-signed"
[I30]: https://sideloadly.io/faq.html "Sideloadly — USB, Developer Mode, trust and refresh requirements"


## 本輪原生行為驗收

2026-09-27 已通過的是 Windows 工程／plist／雙端 v1 DTO 結構檢查與包裝檢查器的 3 項負面回歸（缺 Watch complication、素材遭改、版本不一致）。2026-10-05 又取得前述 macOS runner 的 1,695 項 Foundation、9 項 XCTest、Apple 雙平台編譯及無簽名 archive 成功證據。前者不再是唯一證據；兩者仍不能代替下列真機行為驗收。

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

Apple SDK 26.5 編譯、上述測試及無簽名封存檢查已完成；iPhone及46mm Watch模擬器啟動畫面已實看。所有原生動作、效能／記憶體、Watch 喇叭、HealthKit 取樣、WatchConnectivity 真機時序、四個 target 的簽名與裝置安裝仍待驗收；沒有可直接安裝的已簽名成品，也沒有 Series 12／OS 27 真機通過的證據。
