# Apple Watch 生態與派大星聯動地圖

查證日期：**2026-10-07**。本文件選取 Apple 系統功能及六款具代表性的第三方 App，檢查它們公開的資料、捷徑與入口。這不是所有 Watch 軟件的完整清單，也不是多年使用者訪談或故障發生率研究。下文的「痛點」是可用來設計和驗收的代表情境；技術結論以 Apple／開發商文件為依據，沒有登入、購買、讀取個人健康資料或進行真機互通測試。

派大星適合負責**生活事件的陪伴、簡短回應與一眼可讀的摘要**。運動記錄、睡眠分析、付款及可靠叫醒等工作，先沿用使用者已在用的系統或專門 App。基本陪伴不應以購買下表任何第三方 App 或訂閱為前提。

## 和現有工程的關係

[CAPABILITY-MAP.md](CAPABILITY-MAP.md) 的 50 個情境仍是需求地圖；其中 9/27「原生待 Apple 編譯」是歷史描述，不能蓋過 [PROJECT-STATUS.md](PROJECT-STATUS.md) 的後續編譯證據。編譯、介面模擬及素材播放通過，也沒有證明第三方資料互通、鎖定狀態自動化或真機健康背景更新已通過。

本次讀到的既有入口包括：

- [PatrickIntents.swift](../iOSCompanion/PatrickCompanion/PatrickIntents.swift)：照顧、情境、角色心情、陪伴倒數及暫停／繼續／結束。陪伴倒數不是 HealthKit 健身訓練，也不是控制 Apple Workout 的暫停鍵。
- 同檔本輪新增 `PatrickAutomationIntent`，接收「鬧鐘已停止／我起床了」回報；其描述明確是接在使用者捷徑之後，不讀取或停止系統鬧鐘，背景不補播。存在程式入口不等於已在使用者手機建立自動化。
- [PatrickHealthPanel.swift](../PatrickFace/PatrickHealthPanel.swift) 與 [PatrickHealthSummary.swift](../iOSCompanion/Shared/PatrickHealthSummary.swift)：本輪已落盤七項自選唯讀摘要（步數、心率、SDNN HRV、靜止心率、呼吸率、睡眠手腕溫度、近 24 小時已記錄睡眠），附時間／來源；睡眠只做區間聯集，不冒稱 Apple 分期算法。可自選開頁刷新，新增權限仍需主動按鈕。該版本 Apple 編譯結果見[本輪驗證](ECOSYSTEM-20261007.md)；真機權限仍待驗證，本文件不修改健康實作。
- [Info.plist](../iOSCompanion/PatrickCompanion/Info.plist) 與 [PatrickDeepLink.swift](../iOSCompanion/Shared/PatrickDeepLink.swift)：工程已有 `patrickface` 路由；只有已定義路由才能使用，不能因此假定存在任意第三方分數接收 URL。

**本研究没有實作 AutoSleep／Athlytic／Bevel 等外部健康分數接收器；也沒有新增相機控制、NFC 門禁或系統鬧鐘接管。**

## 先分清四種能力

| 證據層級 | 能確認的事 | 不能直接推導的事 |
|---|---|---|
| 公開 HealthKit 資料型別 | 授權後可按型別查詢實際存在的樣本；需要來源、時間和單位 | App 讀了 HRV，就把它自己的恢復分數也寫進 HealthKit |
| 公開 Shortcuts／App Intents 或 URL 動作 | 使用者可執行文件列明的動作；若有明確回傳值才可設計接收 | 有「打開 App」動作，就能讀該 App 畫面內所有數據 |
| 系統／App 的使用者介面 | 使用者可在原 App 查看、記錄或操作 | 別的 App 擁有相同讀寫權限，或可在背景替它操作 |
| 本次未核實 | 所查官方資料未提供足夠證據 | 功能永遠不可能，或應猜一個 URL／私有 API 接上 |

HealthKit 是共同資料庫，需要逐型別授權；讀取無結果不能可靠區分「沒有記錄」與「未允許讀取」。Observer 通知表示資料庫有樣本增刪，不等於身體狀態即時改變；背景交付由系統安排，而且不能只用 Simulator 驗證。[HealthKit](https://developer.apple.com/documentation/healthkit)、[授權](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data)、[Observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries)。

## Apple 系統功能

以下均於 2026-10-07 核實。系統功能不另收第三方訂閱費，但受裝置、OS、地區與權限限制；新 API 仍要對照本工程最低版本及實際 CI SDK，不能只看最新網頁就直接呼叫。

| 用途／系統功能 | 公開資料或入口 | 派大星可做的聯動 | 界線與退路 | 官方來源 |
|---|---|---|---|---|
| Health：集中健康資料 | HealthKit 的步數、心率、HRV、睡眠、已完成 workout 等型別，逐項授權 | 顯示「記錄到的資料＋樣本時間＋來源」，使用者點開再詳看；缺資料保留一般陪伴 | 不複製整套健康儀表板；不把不同來源、不同 HRV 統計定義混為同一數字 | [資料型別](https://developer.apple.com/documentation/healthkit/data-types)、[來源優先序](https://support.apple.com/en-by/108779) |
| Vitals：日／夜生理指標與個人範圍 | 系統 Vitals 畫面；部分底層指標有 HealthKit 型別 | 提供可理解的樣本摘要；想看系統判讀時引導使用者進原 App | 本次未核實 Vitals 的「正常／偏離」分類有公開可讀接口；不自行冒充 Apple 的範圍判讀 | [Vitals 使用指南](https://support.apple.com/en-my/guide/watch/apd15aa7ed96/27/watchos/27) |
| Readiness：當日活動準備程度 | **Apple 已有 Readiness**：Series 12／Ultra 4、13 歲以上，0–10 分，綜合活動、Vitals、睡眠分數；Watch 與 iPhone Fitness 可看 | 若使用者想參照，先以原 App 查看＋手動選「今天輕鬆些」作可靠入口 | 已讀完整官方指南及新聞稿；**未核實該分數的公開 HealthKit／Shortcuts 讀取 API**。不能拿 HRV 自算一分冒充 Apple Readiness，也不是安全運動許可 | [完整使用指南](https://support.apple.com/guide/watch/flx4gnzby346/watchos)、[Apple 說明](https://support.apple.com/en-us/128112)、[2026/9 新聞稿](https://www.apple.com/newsroom/2026/09/apple-advances-health-and-fitness-capabilities-using-apple-intelligence/) |
| Workout／Fitness：真正記錄運動 | `HKWorkout` 完成記錄；手機個人自動化有 Apple Watch Workout 開始／結束觸發 | 使用者開始跑步時切陪伴情境；完成後按 workout UUID 去重慶祝，資料未同步時只記「收到結束回報」 | Watch 同時只能有一個 workout session。派大星不能為常駐動畫開另一場假訓練，打斷原記錄 App；不要把所有第三方訓練都當成相同捷徑觸發 | [Workout session](https://developer.apple.com/documentation/healthkit/hkworkoutsession)、[另一場 session 的錯誤](https://developer.apple.com/documentation/healthkit/hkerror/code/erroranotherworkoutsessionstarted)、[事件觸發](https://support.apple.com/en-euro/guide/shortcuts/apd932ff833f/ios) |
| Sleep：排程、階段、睡眠分數 | `sleepAnalysis` 記錄與系統 Sleep；捷徑有睡前／就寢／起床事件 | 睡前換睡衣；晨間在資料已到時顯示睡眠時長，沒有資料就普通早安 | 排程進入睡眠 Focus 不等於實際睡着，起床鬧鐘發生不等於人已清醒；本次未核實 Apple 睡眠分數可供第三方直接讀取 | [Sleep 使用指南](https://support.apple.com/guide/watch/track-your-sleep-crpxel1lvun9/watchos)、[資料型別](https://developer.apple.com/documentation/healthkit/data-types)、[Sleep 觸發](https://support.apple.com/en-euro/guide/shortcuts/apd932ff833f/ios) |
| Mindfulness／State of Mind | 正念時間記錄、使用者自填心情；對應 HealthKit `mindfulSession`／`HKStateOfMind`（按 OS 支援） | 短呼吸陪伴；需要記錄時另行明示授權，並保留本人輸入 | 遊戲角色心情不等於健康心情；HRV 低不等於悲傷、焦慮或抑鬱。計時開始不等於完成一段可寫入的正念記錄 | [記錄心境](https://support.apple.com/guide/watch/log-your-state-of-mind-apd7de0f5610/27/watchos/27)、[HKStateOfMind](https://developer.apple.com/documentation/healthkit/hkstateofmind)、[mindfulSession](https://developer.apple.com/documentation/healthkit/hkcategorytypeidentifier/mindfulsession) |

Readiness 來源複核：2026-10-07 成功讀取 [Apple Support 128112 全文](https://support.apple.com/en-us/128112)，頁面標示發布日 **2026-10-06**，原文短句為「Your readiness score ranges from 0-10:」。另已讀取[完整 Watch 指南](https://support.apple.com/guide/watch/readiness-flx4gnzby346/watchos)（本次轉至 en-euro 版本），內文列明 Series 12／Ultra 4、年齡條件與 iPhone Fitness 入口。曾使用的 en-my 固定版本網址本次回傳存取錯誤，因此以上兩個已開啟全文的網址才是本次覆核依據；產品存在仍不證明有第三方分數 API。

## 六款代表性第三方 App

費用只區分是否需要額外購買／訂閱，不以外區價格代替使用者商店價格。所有第三方均為**選配**。表內「未核實分數接口」不否定使用者在原 App 看得到分數。

| App／用途 | 已公開的讀寫／快捷入口 | 真正可設計的派大星聯動 | 專有分數不可讀時的退路 | 費用與 2026-10-07 核實來源 |
|---|---|---|---|---|
| **Athlytic**：Recovery、Exertion、Battery、睡眠與訓練 | 讀 Apple Health；有 workout 記錄；可選把其計算的睡眠靜息心率寫回 Health。這不等於把 Recovery 分數寫回 | 已完成訓練後回應；顯示授權取得的原始健康資料。若只想參考 Recovery，先由使用者在 Athlytic 看完再選陪伴模式 | 本次所查官方文件未核實 Recovery／Battery 的公開分數輸出接口；不用畫面抓取或把其 Battery 誤當手錶電池 | 訂閱。 [官方功能與方案](https://athlyticapp.com/)、[Recovery 定義](https://athlyticapp.helpscoutdocs.com/article/20-understanding-recovery)、[寫回 RHR 的選項](https://athlyticapp.helpscoutdocs.com/article/21-recovery-preferences) |
| **Bevel**：恢復、負荷、睡眠、訓練與日記 | 讀 Apple Health／已支援的其他資料源；官方 Sleep Shortcut 組合鬧鐘與 Sleep Focus。第三方資料接進 Bevel 不等於 Bevel 分數能再輸出 | 用使用者已有睡前捷徑接派大星睡衣情境；運動／睡眠摘要仍取有來源的 Health 樣本 | 未核實 Recovery／Stress／Nutrition Score 的公開輸出接口；Sleep Shortcut 不是分數接口 | 核心功能已免費；最新 Pro 清單包括 Intelligence、Biological Age、Health Records，不能簡化成「全部免費」或「只有 AI 付費」。[版本／Pro 範圍](https://help.bevel.health/en/articles/11194113)、[連接資料源](https://help.bevel.health/en/articles/10400449)、[Sleep Shortcut](https://help.bevel.health/en/articles/10795905) |
| **AutoSleep**：自動睡眠分析與起床準備星級 | 讀／寫 Apple Health 睡眠資料；有 Lights Off；官方 **Shortcuts 回傳字典**，含睡眠時長、開始／結束及 Readiness 星級／HRV 等欄位 | 若使用者已有此 App，可研究「手機取字典→使用者允許的 Patrick 接收動作→本地晨間卡」。下節給 schema 草案，**未實作接收** | 沒買 App 或字典缺值時用 Apple 睡眠樣本／普通早安；AutoSleep 分數明確標來源，不改稱 Apple 分數 | 一次購買、官方稱無訂閱。[官方](https://autosleepapp.tantsissa.com/)、[公開字典](https://autosleepapp.tantsissa.com/today/shortcuts)、[睡眠階段模式](https://autosleepapp.tantsissa.com/clock/sleep-stages)、[Lights Off](https://autosleepapp.tantsissa.com/today/lights-off) |
| **Gentler Streak**：活動路徑、恢復導向訓練 | Apple Health 讀写、Watch workout；官方有寫回運動主觀用力程度的選項，預設關閉 | 把「休息也是生活的一部分」用在角色回應；讀完成運動作一次回饋，不另做一套負荷算法 | 未核實 Activity Path／Wellbeing 的公開分數輸出；用使用者選擇休息＋實際已完成運動 | 免費功能＋Premium 訂閱／終身方案。[官方](https://gentlerstories.com/gentlerstreak)、[Health／RPE 與免費步數範圍](https://gentlerstories.com/newsroom/20250528gssteps)、[訓練引導範圍](https://gentlerstories.com/newsroom/20240209newguidance) |
| **Streaks**：習慣任務、健康目標與計時 | 公開 Shortcuts／App Intents；列有完成／略過任務、開始／停止計時。部分健康任務可寫 Health | 使用者主動執行「完成某任務→派大星短慶祝」的組合；沿用原 App 習慣紀錄 | 任務完成動作不代表任意 Health 自動達標都有外部事件 callback；不能宣稱可查全部內部連勝資料。不因漏一天懲罰角色 | 付費購買；非必需。[官方](https://streaksapp.com/)、[App Intents](https://crunchybagel.com/streaks-for-ios-17-watchos-10/)、[公開動作](https://crunchybagel.com/streaks-5-now-available/)、[商店](https://apps.apple.com/us/app/streaks/id963034692) |
| **WaterMinder**：飲水記錄與提醒 | 官方 Shortcuts 有記錄杯量／顯示餘額等；公開 x-callback URL 有 `add-water`、`log-cup`；有 Health 整合 | 使用者確認喝水後由唯一記錄者寫入，再讓派大星回應；或只讀 Health 的 `dietaryWater` 作摘要 | 角色吃點心不代表人吃喝，不能順便寫健康紀錄。URL 指令不是讀取全部飲水紀錄的 API；杯量單位按 App 設定核對 | 免費＋Premium 訂閱／內購；方案以當地商店為準。[Shortcuts](https://funnmedia.zendesk.com/hc/en-us/articles/360016086612-Siri-Shortcuts-and-WaterMinder)、[URL 文件](https://funnmedia.zendesk.com/hc/en-us/articles/360007745191-WaterMinder-X-Callback-URL-Support)、[商店](https://apps.apple.com/us/app/water-tracker-by-waterminder/id653031147)、[Apple 飲水型別](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/dietarywater) |

上述較舊的 Streaks／WaterMinder 教學可證明開發商曾公開哪些動作，不能保證今天安裝版的介面名稱完全相同。正式接線前應在使用者安裝版查看實際動作與回傳型別，不以 App 名稱猜 scheme。對 Athlytic 的 HRV 取樣建議，也不應為了寵物效果引導開啟與本人狀況無關的醫療設定。

## AutoSleep：可驗證的字典與研究用接收草案

官方 `Time Asleep` 字典的 `Sleep` 是小時，`Start`／`Until` 是主要睡眠時段；`Readiness` 字典的 `Stars` 是其星級，`HRV`／`BaselineHRV` 分別為起床 HRV 與 28 日基準，單位 ms。可用鍵以安裝版對應磁貼顯示為準。[AutoSleep 字典文件](https://autosleepapp.tantsissa.com/today/shortcuts)。

以下是**建議未來由接收器建立的內部封裝**，不是 AutoSleep 原生 JSON，不是本次已存在的 Intent，也不是真人資料。示例只展示睡眠時長；若未來另接星級，應用 `autosleep.readiness.stars` 命名，不轉成百分制或 Apple Readiness。

```json
{
  "schemaVersion": 1,
  "sourceApp": "AutoSleep",
  "sourceAction": "Time Asleep",
  "transport": "user-configured-iPhone-shortcut",
  "receivedAt": "2026-10-07T08:02:00+08:00",
  "sampleInterval": {
    "start": "2026-10-06T23:45:00+08:00",
    "end": "2026-10-07T07:30:00+08:00"
  },
  "metrics": {
    "autosleep.sleepDurationHours": 7.75
  },
  "storageScope": "local-only",
  "userEnabled": true
}
```

若要實作，先處理這些接收規則：

1. 捷徑是「AutoSleep 動作→取得字典值→明示的 Patrick 接收動作」；目前最後一步尚未建立。不能把健康字典塞進普通開頁 URL 或分析日誌。
2. 檢查來源動作、鍵名、數值單位與日期可否解析；缺值存未知，不用 0。輸入時間加時區，不能假定每種 locale 的 `Start`／`Until` 都是 ISO 字串。
3. 接收時間與樣本時段分開；只顯示「上次收到」，不能稱即時。跨日、多段睡眠、來源稍後修訂都要可追溯。
4. 相同來源／時段重送不重複獎勵；資料修訂更新卡片，不重新播慶祝。過期、未解鎖或手機不可達時，使用一般早安，之後不突然补演。
5. 匯入只增加來源明確的摘要，不覆蓋遊戲心情、不寫回另一份睡眠記錄，也不因某分數自動下健康判斷。使用者可停用並刪除派大星的副本。

## 相機、NFC 與長期使用情境的痛點

下列為**代表性設計情境**，不是聲稱所有長期使用者都遇過，也沒有排列故障頻率。系統已有的解法應在產品內講清楚；派大星能改善的部分主要是狀態回饋、去重、退路和自己的互動。

| 情境／困擾 | 官方可證實的能力與限制 | 派大星可自行改善／可靠退路 | 不應承諾 |
|---|---|---|---|
| 用手錶拍手機照片，畫面斷線或距離太遠 | Apple Camera Remote 已有取景、拍照／影片、縮放、鏡頭／閃光及倒數；文件要求約 10 米藍牙範圍。[官方相機遙控](https://support.apple.com/en-ie/guide/watch/apda6e61c287/watchos) | 先保留系統 Camera Remote 操作；角色可做使用者主動打開的拍照前小表演。真正自製遙控應另做 iPhone 相機頁及明確連線／保存回覆 | 未核實公開 API 可讓 Patrick 控制系統 Camera Remote，不能說已能遥控所有拍照 App |
| 按了快門卻不知道拍成沒，重試拍一堆 | 即時 WatchConnectivity 訊息需 `isReachable`；排隊背景傳輸不是即時。自家相機可使用 AVFoundation 的拍照結果回呼。[WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession)、[AVCapturePhotoOutput](https://developer.apple.com/documentation/avfoundation/avcapturephotooutput) | 若未來做自家相機，分「手機已收到／已拍到／已存相簿」，每次 request ID 去重，逾期取消；斷線只顯示重連，不事後執行積壓快門 | 發送成功不等於照片已保存；不能靠健康／運動背景權限常駐相機。此方案未實作 |
| 手機響、手錶不響，誤以為漏通知 | Apple 通常把通知送到手機或手錶其中一方，依手機解鎖、Watch 鎖定、Focus 與連線狀態分流。[通知路由](https://support.apple.com/en-au/108369) | 自家通知提供來源、時間與「本次提醒已處理」；設定說明不再讓兩端各排同一提示；收到延遲事件先檢查是否過期 | 不能讀取或重新包装所有第三方通知，也不能繞過使用者 Focus |
| 同一件事手機、手錶、捷徑各慶祝一次 | 通訊排隊與兩端狀態不同是設計上要處理的條件，不是可靠的「剛剛發生」證據。[WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity/wcsession) | 建議統一事件 ID、來源時間、有效期限與單次呈現記錄；背景只保存，回前景不補播一串。使用者手動操作優先 | 接收封包不等於兩端當時都在前景，也不等於外部 App 的動作已成功 |
| 健康摘要慢半拍、心率是幾小時前 | Observer 是資料增刪通知，背景安排有系統限制；資料可能稍後才寫入或同步。[Observer queries](https://developer.apple.com/documentation/healthkit/executing-observer-queries) | 每項顯示樣本時間；過期顯示「較早記錄」，可手動刷新；與角色即時動作解耦 | 舊 HRV／睡眠樣本不能當即時壓力、正在睡覺或已經恢復的判定 |
| 多個 App 都記運動／睡眠／喝水，數字重複 | Health 提供資料來源與優先序；不同來源的資料不能直接全加。[管理 Health 來源](https://support.apple.com/en-by/108779) | 採選定來源、正確統計與區間合併策略；workout 按 UUID，喝水選唯一寫入者；記錄修訂／刪除不重獎勵 | 不把「數值與 Health 畫面相同」當作所有查詢的自然保證；不跨来源疊加所有睡眠階段 |
| 工作／睡眠 Focus 切了，角色沒跟上；手機鎖定時捷徑停住 | 手機個人自動化有指定 Focus 開／關；能否鎖定執行仍受動作權限與系統條件限制，個人自動化也不隨裝置同步。[設定觸發](https://support.apple.com/en-ph/guide/shortcuts/apde31e9638b/ios)、[新增自動化](https://support.apple.com/guide/shortcuts/add-automations-apdfbdbd7123/ios)、[個人自動化](https://support.apple.com/en-gb/guide/shortcuts/apd690170742/9.0/ios/26) | 使用者自建手機捷徑→既有情境 Intent；介面顯示最後收到的模式／時間；保留 Watch 手動切換與結束時間，避免睡眠情境卡住 | 不宣稱任意第三方 Focus 都可在背景被讀取；不強制開 Watch App。換手機後需重查自動化 |
| 想用手錶掃房間貼紙開工作模式 | Apple 公開 NFC 標籤讀取在 iOS，HIG 明確不支援 watchOS；手機捷徑 NFC 觸發辨認標籤 ID，不讀其任意內容。[NFC HIG](https://developer.apple.com/design/human-interface-guidelines/nfc?changes=_4)、[NFC 觸發](https://support.apple.com/en-ph/guide/shortcuts/apde31e9638b/ios) | 用 iPhone 掃桌面標籤→Patrick 情境／倒數；同一操作另給按鈕或 QR 入口。標籤代表使用者意圖，不當作人真的已開始專注 | 不能寫成 Watch 本身可掃所有 NFC 貼紙；手機背景掃描也受相機、Wallet、重啟後鎖定等狀態限制 |
| 想把任意門禁／交通卡塞進派大星 | Wallet／Express 支援的是合資格發卡方與卡／鑰匙，不是任意 NFC 憑證。可支援免喚醒驗證，但條件按卡種／裝置而異。[Express Mode](https://support.apple.com/en-us/105123)、[Wallet 存取安全](https://support.apple.com/guide/security-pdf/access-using-apple-wallet-sec75f6d5040/web) | 保留 Wallet 或原實體卡；派大星可做使用者手動到家回應、或另接合法門鎖廠商公開的 Home／捷徑入口；門禁本身需另核發卡方 | 不能複製任意門禁密鑰、讀交易秘密或把普通貼紙變成支付卡；官方 iPhone 電力備用說明不能套成沒電 Watch 也能開門 |
| 手機與手錶鬧鐘不一致、按掉了仍看到舊動作 | iPhone 鬧鐘可設定推送至 Watch；Watch 自建鬧鐘不會反向提醒 iPhone。捷徑可接鬧鐘停止／起床事件。[Watch 鬧鐘](https://support.apple.com/en-ie/guide/watch/apd27ce65478/watchos)、[事件觸發](https://support.apple.com/en-euro/guide/shortcuts/apd932ff833f/ios) | 可靠叫醒仍用系統鬧鐘；停止後回報角色一次，真正起床可另手動確認；過期回報不補播。工程本輪已提供回報 Intent，但仍需自動化與真機驗證 | 不讀／關全部系統鬧鐘，不把停止鬧鐘當作已清醒，更不以背景動畫代替叫醒可靠性 |
| 抬腕只有幾秒，介面太多層或提醒太吵 | Apple 建議 Watch 互動精簡、可一眼讀取，透過 complication／通知／Smart Stack 保留短入口。[Watch 設計](https://developer.apple.com/design/human-interface-guidelines/designing-for-watchos) | 主頁最多當下最有用的摘要；角色表演短且可略過；音效可關、休息日不懲罰；詳細設定留手機 | 不以更多常駐動畫、更多感測或更多通知等同更好的陪伴 |

## 建議的日常編排與優先級

下表是開發建議，不是完成清單。各情境先接可證明的事件，素材完成度與藝術批准另外驗收，不因資料／介面通了就把未修畫稿算成完成。

| 優先級 | 一天中的具體體驗 | 優先沿用的能力 | 派大星新增價值／驗收要點 |
|---|---|---|---|
| P0 | 早上按掉鬧鐘後短早安；本人確認起床再切日間衣服 | 系統鬧鐘＋使用者手機自動化＋本輪回報 Intent | 區分鬧鐘事件和本人起床；兩端／重送只回應一次；未開 App 不強制補演 |
| P0 | 工作 Focus 開啟，切正裝並可自行開始專注倒數 | 指定 Focus 自動化＋既有情境／倒數 Intent | 開 Focus 不偷偷開始不可控計時；手動覆寫有效，不和系統 Focus 來回打架 |
| P0 | 跑步時使用原 Workout 記錄，完成回來角色喝水／喘氣／鼓掌 | Apple 或使用者原本的 workout App | 陪伴不搶 workout session；無資料只說收到回報，不捏造距離／卡路里 |
| P0 | 睡前換睡衣，晚間充電呈現對應場景 | Sleep／Focus 排程、Watch 自身電池狀態、現有睡眠設定 | 手機插電不等於 Watch 插電；入睡排程不等於身體已睡著；音效與提醒遵守使用者選擇 |
| P1 | 晨間／运动後自願查看簡短健康摘要 | HealthKit 已存樣本 | 來源／時間／未知狀態完整，睡眠區間不重算、重送不重獎勵；不先做自己的恢復／情緒算法 |
| P1 | 相機、Wallet、第三方記錄工具的清晰入口 | 原 App＋使用者自行建立的系統捷徑 | 先讓使用者知道該在哪裡操作；未有公開連結的 App 提供文字步驟，不猜 URL、不以空按鈕假裝整合 |
| P2 | 已有 AutoSleep／Streaks／WaterMinder 的使用者串上自己的習慣 | 官方字典或明確的動作／回傳值 | 一次接一個 adapter，明示資料種類、唯一寫入者及撤銷方法；無該 App 仍能使用基本陪伴 |
| P3 | 派大星倒數拍照、照片保存後回應 | 自家 iPhone AVFoundation 相機＋即時 WC 回覆 | 需完整開發及實機驗證鏡頭權限、手機鎖定／中斷、逾期／重試；做不到時保留 Camera Remote |

同一時刻的動作應有明確優先序：使用者手動互動／正在進行的倒數優先，其次是當下有效的生活事件，最後才是待機眨眼。過期、重複或只有資料同步的事件更新摘要即可。派大星不需要複製六款健康 App 的所有圖表，更不應要求裝齊才有趣。

## 正式接線前要留下的證據

- **真實入口**：安裝版捷徑動作名稱、回傳型別及一份去識別的測試輸入。公開產品頁只證明功能存在，不證明輸出契約。
- **資料語義**：來源 App／裝置、樣本時段、單位、算法名稱、查詢／接收時間及未知原因；SDNN 與不同定義的 Recovery HRV 不直接混用。Apple 系統新分數 API 未核實就留空。
- **裝置條件**：實際 Watch／iPhone／OS、解鎖與 Focus、前景／背景、斷線與重連、換日及時區；HealthKit 背景交付要真機，不能拿模擬器播放結果代替。
- **副作用**：照顧寵物不寫入人類健康記錄；任何喝水、正念或訓練寫入都需明確操作及授權，並與原記錄 App 避免重複。
- **可退出**：每個聯動可停用；停用後仍有普通陪伴及手動選擇；不保留多餘健康副本、不將私人健康資料放入遠端日誌或一般 URL。

本文件交付的是來源核實與可實作設計邊界。第三方 App、系統新功能、專有分數接收、自製相機與真機自動化，均應在各自完成後另記實作和驗收結果。
