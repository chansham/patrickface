# 健康資料與日常陪伴接入

核實日期：2026-10-07。Apple 官方文件為本頁外部依據；來源與實作狀態分開列明。

## 本輪交付

Watch 選單的「健康摘要」改為七項自選唯讀資料：今日步數、最近心率、HRV SDNN、靜止心率、呼吸率、睡眠手腕溫度與近 24 小時睡眠。初次預設全部未選；按「授權並讀取所選項目」才請求那些項目的讀取權限，`toShare` 為空。

可自行開啟「開頁刷新已選項」：只重新查詢曾經主動請求的項目，不自動顯示授權視窗。這裡的「曾請求」不是已獲准。每筆數值都有樣本時間或統計區間、來源，空查詢顯示尚無可讀資料；沒有用 0 代替空資料，也沒有把空資料判為拒絕授權。

新增「呼吸休息 1 分鐘」入口，開始既有手動陪伴倒數。它不依健康閾值啟動、不宣稱治療效果、不建立真實健身紀錄；可用動作仍由所選衣服與前景播放條件決定。

本輪源碼與工程引用已接好，Windows 的 plist／來源結構檢查通過。[本輪 Apple CI 37589666713](https://github.com/chansham/patrickface/actions/runs/37589666713) 已通過 Apple 編譯與新增的 27 項純 Foundation 檢查；對應程式提交 `86f0ba23f24ca17e314d7dcdd7054cbfdfb7fd60`，SDK 26.5。這驗證程式及區間規則，**不代表實機授權、感測或健康選項畫面已通過**。

| 檔案 | 責任 |
| --- | --- |
| `PatrickFace/PatrickHealthPanel.swift` | 七項選擇、最小授權、查詢、來源／時間顯示、取消與前景生命週期 |
| `iOSCompanion/Shared/PatrickHealthSummary.swift` | 不持久化的顯示模型、睡眠區間合併、舊查詢防回填規則 |
| `tools/NativeHealthChecks.swift` | 缺資料／真零、重複與跨來源睡眠、跨日／DST、範圍改選與取消規則 |
| `PatrickFace/Info.plist` | 對應的健康讀取用途說明 |
| `PatrickFace/PatrickAnimatedFaceView.swift` | 健康頁入口與主動呼吸 callback，由本輪 UI／事件工作接線 |

健康值只存在健康頁的記憶體；不寫入健康、不進日記、Widget、WatchConnectivity 或外部服務。只將選擇項目、曾請求項目 ID 與自動刷新偏好存在本機。iPhone 目前沒有同一健康摘要 UI；iPhone 與 Watch 的既有陪伴狀態同步不含健康數值。

## 可讀資料、真正意義與目前範圍

| 資料 | 官方能力與重要限制 | 目前 PatrickFace／下一步 |
| --- | --- | --- |
| 步數 | HealthKit 可做累計統計；來源可分開列出。各來源與健康 App 的優先順序，不應被我們自行相加的推論取代。[統計](https://developer.apple.com/documentation/healthkit/hkstatistics/sumquantity())、[来源](https://developer.apple.com/documentation/healthkit/hkstatistics/sources) | **已接源碼**：本地今天午夜至查詢時間的 HKStatisticsQuery，列出回傳來源；不是運動距離或卡路里估計。實機需對照健康 App 的來源合併表現。 |
| 心率 | 可讀已儲存心率；最新官方說明已包含 Series 12／Ultra 4 的白天連續綠光測量，頻率仍不能等同 App 即時收到樣本。[Apple 心率說明](https://support.apple.com/en-us/120277) | **已接源碼**：最近七日最新一筆與時間；不啟動假健身來保持螢幕或強迫即時測量。 |
| HRV SDNN | SDNN 是正常心跳間隔的標準差，單位為毫秒；是指定指標，不是壓力分數。[SDNN](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn) | **已接源碼**：明確標為 SDNN。沒有通用壓力閾值、健康診斷或自動改心情。 |
| Recovery HRV／RMSSD | Apple 現行支援頁列出 Series 12／Ultra 4 的 Recovery HRV；公開 `heartRateVariabilityRMSSD` 文件標為 iOS／watchOS 27 起。不可再說 Apple 只有 SDNN。[Recovery HRV](https://support.apple.com/en-us/120277)、[RMSSD API](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilityrmssd) | **研究已確認，未接**。目前已驗證建置使用 SDK 26.5；需先有 SDK 27 建置／availability 檢查與真機樣本，再加入獨立可選項，不能把 SDNN 改名代用。 |
| 靜止心率 | 系統根据休息時樣本估計；當日或前日估計可能被替換，運動後坐下的心率不直接等同它。[restingHeartRate](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/restingheartrate) | **已接源碼**：最近七日最新系統估計，显示時間。未做個人趨勢或異常提醒。 |
| 呼吸率 | HealthKit 有每分鐘呼吸次數的离散記錄；能查詢紀錄不代表按鈕能立刻測量。[respiratoryRate](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/respiratoryrate) | **已接源碼**：最近七日最新樣本與來源。沒有把呼吸率直接轉成壓力。 |
| 睡眠手腕溫度 | API 提供睡眠期間手腕的**絕對溫度**；健康 App 顯示的相對個人基準差是不同呈現。樣本從首夜可讀，健康 App 通常需約五晚建立基準。[API](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature) | **已接源碼**：最新 °C 與時間，明示不是體溫計／基準差；沒有用數值判斷發燒或感冒。 |
| 溫度所需設備／設定 | 現行官方支援 Series 8 及之後、所有 Ultra，並已包括 SE 3；需啟用睡眠追蹤，睡眠專注每晚至少四小時、約五晚建立基準。不是即時按需溫度計。[設定與限制](https://support.apple.com/en-us/102674) | 不以「沒資料」推断是哪個設定錯。顯示前由使用者確認自身型號／睡眠設定；不要求經期權限。 |
| 睡眠 | inBed、awake 與各 asleep 階段可能重疊，不能全部相加。[sleepAnalysis](https://developer.apple.com/documentation/healthkit/hkcategoryvaluesleepanalysis) | **已接源碼**：近 24 個實際小時內，只取 asleepUnspecified／Core／Deep／REM；UUID 去重、裁切時間窗，再取跨來源區間聯集。不是 Apple 夜間分期或來源优先算法，跨來源冲突仍需實機對照。 |
| 血氧 | 有公開氧飽和度类型，但功能受型號、年齡、地區與購買版本影響；美國特定新購版本的分析在配對 iPhone 完成，不可保證 Watch 本地即時有值。[API](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/oxygensaturation)、[Apple 血氧限制](https://support.apple.com/en-us/120358) | **未接／不請求權限**。日後可獨立選擇，需來源／時間與裝置驗證，不把讀值作醫療判斷。 |
| State of Mind | 公開模型為使用者記下的當下情緒或整日心情，iOS 18／watchOS 11 起；不是手錶推測的情緒。[HKStateOfMind](https://developer.apple.com/documentation/healthkit/hkstateofmind)、[WWDC wellbeing APIs](https://developer.apple.com/videos/play/wwdc2024/10109/) | **未接／不請求權限**。現有「角色心情」維持使用者選擇，不混同心理健康紀錄；未把日記寫進 HealthKit。 |
| 運動與運動鏡像 | watchOS 10／iOS 17 起的多裝置健身範例使用真正 HKWorkoutSession；官方要求實體裝置執行該範例。[多裝置健身](https://developer.apple.com/documentation/healthkit/building-a-multidevice-workout-app) | **未接真實運動記錄**。既有散步／跑步／力量分類仍是陪伴計時。正式健身需另做起停、暫停、保存、失聯恢復、所需權限與實機測試。 |
| Apple Readiness 或第三方壓力／恢復分數 | Apple 系統已有新健康呈現不代表每個分數都有公開讀取 API；本輪未找到並驗證可直接讀取該分數的公開 HealthKit 契約。[Apple 2026 發布說明](https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/) | **未知／未接**；不自行造分數，也不把第三方私有計算結果當成標準 HealthKit 欄位。 |

## 自動化與兩端聯動應如何落地

本輪的自動化是「回到可見的健康頁後，重新讀取曾請求且仍勾選的資料」，不是背景健康監控。Apple 的 iPhone／Watch HealthKit 資料庫由系統同步，Watch 端歷史資料保留與同步時點受系統管理；我們不另用 WatchConnectivity 複製敏感原始值。[HealthKit 架構](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework)

下一階段若做可選的資料更新提示，可用 Observer Query 察覺資料變動，再取增量，但需要獨立開關、背景交付能力與真機驗證。交付頻率是上限，不是保證時刻；watchOS 多數類型有每小時上限與共享背景預算，不能承諾每分鐘健康事件或用背景回呼強制亮屏表演。[Observer Query](https://developer.apple.com/documentation/healthkit/hkobserverquery)、[背景交付](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:))

Apple 刻意不讓 App 判定讀取授權是准許還是拒絕；空資料亦可能是同步延遲、無樣本或歷史授權範圍限制。[授權](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data) 因此本轮切換項目、離頁、腕下、進背景均清掉顯示值，停止查詢並增加 generation，晚到結果不得回填；再入頁重查，不重用數值快取。**不能承諾在使用者從另一台裝置撤銷權限的同一瞬間收到通知並清畫面**：沒有可據此判斷讀取授權的公開回呼，本輪也沒有跨裝置撤權監聽。可用「清除本頁數值」立即清掉当前畫面，不影響健康 App 原紀錄。

## 男性使用者可借鑑的趨勢方法

本專案不做經期功能、不要求經期／排卵／生殖健康權限。Apple 經期追蹤在既有記錄、心率和支援裝置的夜間溫度中找變化，排卵是回溯估計，不能直接套成男性的壓力或生病判斷。[Cycle Tracking](https://support.apple.com/en-au/120356)、[Watch 經期說明](https://support.apple.com/en-ph/guide/watch/apd26429adf0/watchos)

可借鑑的是資料處理原則，以下為本專案的後續設計建議，**不是聲稱已重現 Apple 演算法**：

- 先保留日期、來源、裝置與測量情境；同一夜間區間與同一指標才比較，不混用 SDNN、RMSSD、絕對溫度和基準差。
- 有多晚有效資料後才建立個人參考範圍，標出缺日、更換手錶或來源變化；資料不足就顯示不足，不補零或套用別人的正常值。
- 將近期資料與自身過往呈現為描述性趨勢，可附使用者自行記下的運動、旅行、飲酒、睡眠或環境變化；這些可能共同影響溫度／心率，不能把相關性寫成診斷。[溫度影響因素](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/applesleepingwristtemperature)
- 派大星可提供自願休息、呼吸或查看紀錄入口；不因一次 HRV 下降斷言「你壓力大」，不因手腕溫度上升斷言「感冒了」。目前只做手動呼吸入口，未啟動任何趨勢閾值或健康值自動換裝。

## 尚需實測

1. 健康選項、授權流程與呼吸入口的實際畫面和操作；本輪 Apple 編譯與 27 項 Foundation 測試已通過，但未在模擬器截图中覆蓋健康頁。
2. 實體 Watch 逐項授權／拒絕、部分授權、改選、腕下／背景與查詢同時發生，確認沒有舊值回填或自動授權彈窗。
3. 檢查樣本時間與來源、空結果、有限歷史；核對跨來源睡眠與當地跨午夜的步數，不宣稱必與健康 App 私有合併算法完全相同。
4. 溫度需實際有睡眠記錄；RMSSD 需先驗證 SDK 27 的編譯與裝置樣本。本輪不冒充已驗證 OS 27 新資料。
5. 手動呼吸從健康頁可返回陪伴畫面；安靜／低電量／減少動態時仍保存計時，但不補播舊動畫與音效。
