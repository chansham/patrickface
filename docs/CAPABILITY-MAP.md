# 派大星腕上寵物：能力與玩法地圖

查證日期：2026-09-27。用途：把需求拆成可實作、可驗收的情境；**這是能力研究與開發路線，不是已完成功能清單**。來源以 Apple 文件為主；第三方工具僅採用其自身公開說明。沒有進行真機安裝或測試。

2026-10-07追加：本文50項是9月的研究基線，原生「待編譯」等段落保留當時狀態；後續多輪Apple編譯已有結果。最新實作與當輪驗證請看[聯動紀錄](ECOSYSTEM-20261007.md)及[專案現況](PROJECT-STATUS.md)。HRV新型別、Readiness、AlarmKit、七項健康摘要、起床回報、第三方App與相機/NFC痛點已重新查核在[最新生態地圖](ECOSYSTEM-MAP-20261007.md)，不能只用舊表判斷現行系統全部能力。

## 要做的體驗

讓派大星成為能看時間、被照顧、陪伴生活並逐步收集服裝的腕上寵物。角色的動作、表情、服裝與背景可替換，不將產品鎖定為某一季、2D、3D 或單一畫風。既有「手臂作時／分針」仍是可選的時間呈現方式；其他寵物場景不必為了看時間而限制互動。

完整互動放在 watchOS App；抬腕入口、簡短狀態與快捷操作分別交給 complication、Smart Stack、通知和適用版本的 controls。手機可做設定、素材匯入與自動化；沒有手機在旁時，手錶仍應保存自身寵物狀態。Apple 官方的 independent app 設計允許 companion 作輔助，但不能將 WatchConnectivity 當成獨立 App 唯一資料來源。[S01]

## 如何讀取狀態

- **直接**：公開 API 足以實作該範圍；仍須開發和驗證，並非表示本倉庫已完成。
- **替代**：原先想像的系統行為無公開入口，但能用另一個流程達成接近的使用目的。
- **不可（公開 API）**：未找到受支援的替換或存取方式；同列提供可用替代，不代表所有未來系統永久不可能。
- **待實機**：API／設計有依據，但時機、權限、硬體、背景狀態或配對行為須用使用者裝置證明。

版本採**最低可依賴入口**：現有工程以 watchOS 10／iOS 17 為基礎；double tap 主動作需 watchOS 11+ 及支援硬體；Watch controls 是 watchOS 26+。不可因現行文件列出新 API，就直接放入舊版本而沒有 availability 與替代 UI。[S02][S03]

## 本輪源碼狀態：日常體驗已接，原生仍待編譯與實機

詳細可用項、測試證據與未完成項集中在 [PROJECT-STATUS.md](PROJECT-STATUS.md)。舊 PatrickFaceView 的整張旋轉表演已不是當前主首頁；Watch 入口是 PatrickAnimatedFaceView，手機是 PatrickPhoneExperienceView，兩端共用 PatrickExperience 狀態、Animation／Experience 資源與原味時計 manifest。

現已接衣櫥、照顧、手動心情、三種陪伴倒數、數字／日期、短音效／輕震、生日／節日／睡眠設定、手機捷徑與小工具摘要。健康摘要只有按鈕觸發的唯讀步數／最近心率／HRV，顯示樣本日期，不推算壓力或心情。運動陪伴沒有假建 workout session；泡澡沒有自動偵測。

Watch 電池監控依 App 生命週期讀真實狀態；手機效果預覽與系統充電區分。NFC 需在配對 iPhone 建立個人自動化，不能說網頁或 Watch 已能任意讀標籤。新稿與程式皆未完成 Apple SDK／真機驗收；私人使用也不等於可接管系統所有畫面。下方 50 項仍是研究與驗收路線，不是已完成清單。

## 50 個可落地情境

### 日常寵物與時間

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
|---|---|---|---|---|---|
| 01 抬腕回來打招呼 | 發現你回來，眨眼或短暫伸懶腰，隨後恢復時計 | 直接＋待實機；依 App 重新 active 判斷「回來」，不宣稱精準辨識每次抬腕原因 | Watch；不用健康權限 | scenePhase 去重；測抬腕、解鎖、通知返回與切 App 不連播 | [S04][S05] |
| 02 摸摸、戳肚子 | 點頭、彈跳、害羞；短觸覺回應 | 直接；手勢只在可互動畫面內，不能攔截整個系統的觸控 | Watch；觸覺依靜音及使用設定實測 | 定義手勢優先級和冷卻時間；與雙擊／長按避免衝突 | [S06] |
| 03 餵食與照顧 | 選小點心、吃完飽足上升，偶爾打嗝 | 直接；遊戲內數值與時間計算，不需要健康資料 | Watch 本機儲存 | 儲存事件時間；關 App 再開仍一致；不要求背景每秒扣數值 | [S01][S05] |
| 04 換衣與收集 | 帽子、上衣、手持物；任務或紀念日解鎖 | 直接；道具為資料與素材，不以付費／網路作前提 | Watch；可選 iPhone 管理 | 建立外觀槽位、圖層順序與版本；每種畫風都能套同一套道具概念 | [S01][S07] |
| 05 手臂看時間 | 兩手共用一軸；短時針、長分針，表演後回到當前時間 | 直接；屬 App 畫面，不能註冊成任意第三方系統錶面 | Watch | 各整點／交叉角度驗證；動作不移動軸心；時間直接由日期算，不累積角度誤差 | [S05][S07] |
| 06 Always-On 陪伴 | 低亮度靜態睡眼、分鐘級時間；抬腕才有細動作 | 直接＋待實機；依系統 cadence 降頻，不能要求 Always-On 持續全速動畫 | 支援 Always-On 的 Watch；型號待確認 | 用 TimelineView context.date；測低電量、鎖定、腕部朝下與返回時鐘 | [S04][S05] |

### 充電、床頭與電量

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
|---|---|---|---|---|---|
| 07 手錶充電時「吃電」 | 插上充電器後，App 裡抱住電池、充能發光 | 替代＋待實機；讀 **Watch** 的 WKInterfaceDevice batteryState。不可替換系統充電圖示，也未有「插上即強制開 App」保證 | Watch、充電器；啟用 battery monitoring | 本輪已加監控與實際充電才能手動播放的入口；先實測。自動跨 charging 邊界播一次／背景補演仍待開發 | [S06][S08][S09] |
| 08 充飽後慶祝 | 電池滿了伸懶腰或戴滿電皇冠 | 直接於 App 可執行時＋待實機；不要把 80% 最佳化充電等待判作故障或滿電 | Watch；同上 | 區別 charging／full／unplugged／unknown；量測與系統值差異，避免假裝精確即時通知 | [S08][S09] |
| 09 手機充電小劇場 | 手機一充電，派大星收到「家裡補給」提示 | 替代；iPhone「充電器」捷徑觸發的是 **手機**，可送自訂事件到 Watch，不能標作手錶正在充電 | 支援自動化的 iPhone、配對 Watch；使用者建立個人自動化 | 事件標明來源 phone；離線排隊、過期取消；不得改寫 Watch batteryState | [S10][S11] |
| 10 床頭晚安 | 黑底小床、派大星睡覺、大字時間；手機可另作 StandBy 卡片 | 替代；Apple Watch Nightstand 是系統畫面，未見可掛自訂角色的公開擴充點；做 App 床頭場景或手機 StandBy，不覆蓋 Nightstand | Watch 充電器；手機方案另需 iPhone | 先讓使用者手動開床頭場景；測退出／熄屏；保留系統鬧鐘作真正叫醒入口 | [S12][S04][S13] |
| 11 低電量省力 | 角色坐下、關閉粒子、保留時間與簡單表情 | 直接＋待實機；電量低和系統 Low Power Mode 是不同條件，兩者分別處理 | Watch | batteryLevel unknown 不當成 0%；定義降級層級並測功耗，不用假 workout 延長常駐 | [S06][S14][S05] |

### 節日、時段、天氣與個人紀念日

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
|---|---|---|---|---|---|
| 12 定時換衣 | 上班時間穿小領帶，夜晚穿睡衣 | 直接；本地規則計算「此刻應穿什麼」，不要求 App 準點被喚醒 | Watch；無額外權限 | 時區／跨日／夏令時間與手動覆蓋；下一次開啟直接呈現正確結果 | [S15][S05] |
| 13 公曆節日 | 萬聖節披風、聖誕帽、跨年短慶祝 | 直接；節日資料由產品設定，Calendar 只負責日期運算 | Watch | 地區可選、同日多節日排序、可關閉；一年只獎勵一次並可補領 | [S15] |
| 14 農曆節日 | 新年紅衣、中秋抱月餅、端午划龍舟小表演 | 直接＋日期驗證；使用 Chinese calendar，閏月規則需明訂，不能把「農曆日期」當公曆固定日期 | Watch；無定位必要 | 年份、時區、閏月測例；節日名稱／地方習俗自訂；清明等節氣另用可靠日期資料 | [S15][S16] |
| 15 生日／紀念日 | 戴生日帽、送一封小卡片、解鎖紀念衣服 | 直接；手動錄入即可，不必讀整個通訊錄 | Watch 或 iPhone | 公曆／農曆、2月29日規則、提醒時間、一次性與每年重複 | [S15][S17] |
| 16 天氣換衣 | 下雨拿傘、冷天圍巾、晴天遮陽帽 | 直接＋待服務接入；WeatherKit 或其他合規資料源，過期時顯示資料時間 | 網路；定位可選，以手動城市替代；WeatherKit 會員及歸因 | 城市設定、快取、斷網、預報更新頻率；不每秒查網路 | [S18] |
| 17 早晚與旅行時差 | 清晨打哈欠，日落看星星；旅途中戴旅行帽 | 直接；固定時段可離線；依實際日落則需天氣／日照資料 | Watch；定位非必要 | 本地時區與固定家鄉時區二選一；切時區不重複發獎勵 | [S15][S18] |

### 睡眠、情緒與休息

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
|---|---|---|---|---|---|
| 18 手動晚安／起床 | 一按蓋被子，一按揉眼睛醒來 | 直接；這是使用者指定的角色場景，不宣稱偵測人在睡覺 | Watch；可選 App Intent | 明確的開始／解除；重開 App 保留；短暫預覽不可永久覆蓋自動規則 | [S01][S19] |
| 19 跟隨指定睡眠 Focus | 睡眠 Focus 開啟就換睡衣，關閉再醒來 | 替代＋待實機；一般 Focus status 只表示通知專注狀態，**不是 Focus 名稱或已入睡**。用 iPhone 指定「睡眠」自動化→Intent→WC，或自訂時段 | 配對 iPhone、使用者設定的自動化；若讀 Focus status 需授權 | 測工作／勿擾不會被誤判睡眠；斷線補送含時間與有效期 | [S10][S11][S20] |
| 20 昨晚睡眠回顧 | 早上展示「昨晚陪你休息」小卡與柔和伸展 | 直接讀取紀錄＋待實機；HealthKit sleepAnalysis 是樣本，不是可靠的即時入睡事件 | HealthKit 睡眠資料讀取同意；相容睡眠記錄設定 | 待資料同步後生成摘要；缺資料說尚無紀錄，不假造睡眠時數 | [S21][S22] |
| 21 手動心情／心情日記 | 選開心、普通、累了；角色回應擁抱、一起坐一會 | 直接；先採本地自述；可選把使用者主動記錄寫入 HKStateOfMind | 本地版無健康權限；HealthKit 版需逐項同意及 API 版本檢查 | 保留使用者用詞；可修改／刪除；關閉健康權限也能玩 | [S23][S22] |
| 22 心率／HRV 陪伴建議 | 提供「要休息一下嗎」選項，再由使用者決定表情 | 替代；HRV 是心搏間隔變化，**不能由一個值斷言焦慮、悲傷或壓力**。不用它自動覆蓋使用者心情 | 自選 HealthKit 心率／HRV 讀取；資料可能延遲／缺少 | 先展示採樣時間；只做可忽略的陪伴建議；未選擇即不開啟此功能 | [S24][S22] |
| 23 呼吸／短暫伸展 | 角色呼吸、雙手舒展，結束給一顆小星星 | 直接；真正正念／自我照顧可評估符合用途的 extended runtime，不將它作任意動畫常駐捷徑 | Watch；如記錄 mindful minutes 才另外求健康權限 | 先做前景1分鐘版；測打斷、離開、到期；不是醫療指示 | [S14] |

### 運動與活動獎勵

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
|---|---|---|---|---|---|
| 24 步數與活動圓環 | 步數種出貝殼，圓環完成就送小旗 | 直接＋待資料更新；HealthKit activity summary／步數讀取，不能擷取或修改系統 Fitness 畫面 | Watch／iPhone HealthKit 逐項讀取 | 按日去重、跨裝置避免加總重複；空資料不當成沒有活動 | [S25][S22] |
| 25 跑步／走路陪跑 | 跑鞋、沿路小動畫、距離里程慶祝 | 直接：自家 HKWorkoutSession；替代：保留 Apple Workout，完成後讀取已存紀錄給獎勵 | HealthKit；戶外路線才要定位 | **二選一模式**，不另起第二個 workout 與系統 Workout 搶 session；先驗時間／距離／暫停 | [S26][S27] |
| 26 單車陪騎／手機儀表 | 戴頭盔踩單車，手機看大字速度與寵物狀態 | 直接於自家 workout＋待實機；workout mirroring 是自家 Watch session 與 companion，不是接管任何運動 App | Watch＋配對 iPhone；HealthKit，必要時定位／外部感測器 | 依 Apple sample 驗 mirrored session、斷線恢復、暫停／結束同步 | [S28][S26] |
| 27 重訓／瑜伽／舞蹈 | 健身服、組間休息倒數、瑜伽伸展與跳舞慶祝 | 直接記正確運動種類；替代：手動計組與結束後摘要。不能僅靠 workout type 保證自動辨識所有次數／姿勢 | HealthKit 運動；純手動遊戲可不授權 | 選相應 activityType；組數先手動；自動動作辨識是獨立研究和實測項目 | [S27][S26] |
| 28 游泳／水上活動 | 泳鏡、氣泡、完成後海底慶祝 | 直接記錄／摘要＋待實機；Water Lock 會停用觸控螢幕，不能要求水下連續點餵食；不能推定所有 Watch／活動深度都適用 | 適用水上活動的 Watch；HealthKit；泳池長度設定 | 入水前設定；水中大字資訊；出水解鎖後發獎勵；遵循該型號水阻限制 | [S06][S27][S29] |
| 29 健行／其他運動／完成獎勵 | 登山包、球衣、划艇或拳套；用時／完成一次解鎖服裝 | 直接依已保存 workout 類型映射；不假造未提供的動作細節 | HealthKit workout 讀取；路線可選 | 先涵蓋健行、划艇、球類、拳擊；未知類型用通用運動服，保留原始類型 | [S27][S22] |

### 快速觸發、實體道具與系統入口

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
| 30 掃實體 NFC 道具 | 手機碰「食物卡」後，派大星收到指定點心 | 替代＋待實機；**iPhone NFC→個人自動化→App Intent→WC**。Watch 一般 Core NFC 讀標籤不受支援；Wallet 功能不等同公開讀卡器 | 支援 NFC 自動化的 iPhone、相容標籤、配對 Watch | 先一張測試標籤；foreground/background/鎖定/離線矩陣；收訊成功≠Watch 已顯示動畫 | [S10][S11][S30] |
| 31 BLE 小按鈕／道具 | 按藍牙玩具按鈕送食物，或接感測器觸發活動 | 直接能力＋待硬體；Core Bluetooth 可以讀周邊特徵，背景受系統排程限制；不是任何「藍牙按鈕」都開放通訊 | 公開 GATT 協定的 BLE 周邊；藍牙權限 | 先確認周邊服務UUID／characteristic；實體裝置測重新連線與背景通知 | [S31] |
| 32 Siri／捷徑 | 說「讓派大星睡覺」「換旅行衣服」 | 直接；App Intent 表達已實作動作；聲音／開畫面可能需前景與裝置解鎖 | 相容 Watch／iPhone；使用者啟用相關捷徑 | 先驗主題／睡眠，再加餵食；Intent 不依 UI 才能修改狀態；回覆分清已套用／等待手錶 | [S19][S11] |
| 33 Control Center／Smart Stack 按鈕 | 一按摸摸、開始專注、切衣服 | 直接於 watchOS 26+；iPhone control 在錶上操作仍在手機執行，不能誤當 Watch 本地動作；需開手機前景的 control 不會出現 | watchOS 26+；舊版用 complication／App 按鈕 | 為 Watch 寫本地 control；區分 iPhone relay；離線也能做本地照顧 | [S02] |
| 34 Ultra Action button | 實體按鍵直接叫出陪伴場景／開始一項活動 | 直接適用入口＋待實機；讓使用者配置 control／捷徑，不能全系統任意攔截按鍵 | Ultra 系列；controls 方案 watchOS 26+ | 先測「開始專注」；不支援機型顯示同功能屏幕按鈕 | [S02] |
| 35 雙指互點 double tap | 畫面上的主要按鈕可餵食或暫停專注 | 直接＋待實機；watchOS 11+ 將 on-screen 按鈕指定為 primaryAction；不是程式已有的「雙擊螢幕」 | 支援 double tap 的 Watch 型號；系統手勢開啟 | 每個 scene 僅一主動作；測不可見按鈕、捲動及輔助使用；舊型號保留觸控 | [S03] |
| 36 complication／Smart Stack 狀態 | 露個頭、顯示心情／倒數，點一下回寵物 | 直接；系統負責版型與更新，不能把它當高幀率微型遊戲 | WidgetKit；版本依所用互動API | 先穩定 deep link、冷啟動與簡潔狀態；不將舊 timeline 寫回主狀態 | [S07][S02] |

### 提醒、生活工具與素材擴充

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
| 37 自己的提醒通知 | 「休息一下」「今天的小禮物到了」，可按稍後或開 App | 直接＋待實機；只能管理自己 App 的通知，不換掉其他 App 的通知介面／提示音 | 通知同意；靜音／Focus 仍由系統處理 | 通知要可關閉；測 Watch/iPhone路由，去重；離線仍可用預排本地提醒 | [S17][S32] |
| 38 音效與觸覺 | App 內短笑聲、點擊彈跳音、互動震動 | 直接前景播放＋待音訊路由；Watch 自訂「通知聲」不能只憑 iOS UNNotificationSound 推定支援，先用系統通知＋開 App 播角色音效 | Watch 音訊輸出／耳機依型號版本實測；無須麥克風 | 區分 App 音效與通知聲；不替換充電音／來電音；靜音與不打擾設定測試 | [S06][S32][S33] |
| 39 行事曆陪伴 | 開會前穿小西裝，下一個事件顯示簡短卡片 | 直接 EventKit 讀取＋待配對；「只看事件」仍需 full access，沒有獨立 read-only 授權 | Calendar full access；拒絕可用手動事件 | 選要顯示的行事曆、隱藏事件名稱、時區；權限撤回後清除快取摘要 | [S34][S35] |
| 40 地點／導航 | 到家換居家服，散步時派大星指向目的地 | 直接定位＋替代；watchOS 26 MapKit 可路線／搜尋；舊版可開 Maps 或使用手機位置自動化傳場景 | 定位按需要索取；網路；iPhone relay為可選 | 先手動選「家／外出」；再測定位精度、斷網、位置延遲，不把地理事件當即時保證 | [S02][S36] |
| 41 專注／休息計時 | 派大星一起讀書，結束伸懶腰並給一顆星 | 直接；保存開始／結束日期，UI推算剩餘；到期由本地通知，手機 Live Activity 提示 | 通知可選；iPhone Live Activity／StandBy另需支援版本 | 補暫停／續行／取消與重啟恢復；測後台結束不靠 Task.sleep 當唯一機制 | [S05][S17][S13] |
| 42 音樂陪伴 | 歌單衣服、播放自己的海浪音、音樂時跳小舞 | 直接自有音訊；Apple Music可評估 MusicKit，但各播放器的 watchOS 可用性需逐API確認，先用手機播放／系統Now Playing替代 | Apple Music需授權及適用訂閱；自有音效不需訂閱 | 先短音效；音樂加入真正播放UI，測輸出裝置；不得用無聲音訊騙常駐 | [S37][S33] |
| 43 照片／服裝素材匯入 | 以照片作背景、小卡片；自訂帽子顏色或貼紙 | 直接 PhotosPicker／檔案型素材＋待實機；不必索取整個相簿；Watch picker需實體裝置測試 | 手機最方便；Watch可用picker的機型／版本 | 先手機選圖、裁切、縮圖，再傳輸；限制尺寸與記憶體；保留原素材版本 | [S38][S11] |
| 44 今日回顧／收集冊 | 展示照顧、專注和運動的小卡，累積服裝但不懲罰缺席 | 直接本地事件／可選健康摘要；同步延遲不應扣掉獎勵 | Watch本地；iPhone同步可選；健康資料另授權 | 以事件ID去重、版本遷移；斷線數日再合併；提供手動匯出／重設確認 | [S01][S11][S22] |

### 衣櫥、個性與泡澡情境（2026-09-27新增需求）

本節是使用者新增方向與待開發玩法；對上一批3張圖的喜歡，不等於整個素材庫已獲批准。外觀須逐件確認，詳見[角色方向](CHARACTER-DIRECTION.md)。

| 編號／用途 | 派大星的具體表現 | 路線與邊界 | 裝置／權限 | 下一步與驗收 | 來源 |
|---|---|---|---|---|---|
| 45 眼鏡配件 | 圓框看書、方框認真思考、墨鏡淡定耍酷 | 直接本地素材與槽位；表情與眼鏡獨立，可保留眼睛辨識度 | Watch；不需感測器／健康權限 | 提案逐件確認；測眨眼、側看與小尺寸鏡框，不讓每副眼鏡都搭同一笑臉 | 使用者本輪方向；[S01][S07] |
| 46 帽子衣櫥 | 保留喜歡的星星睡帽，再提案日常帽、貝雷帽等不同性格 | 直接；帽子、睡衣、表情可組合，不預先批准所有提案 | Watch本地；iPhone選配可選 | 設定帽子錨點、與眼鏡的遮擋順序；先審外形再導出素材 | 使用者本輪方向；[S01][S07] |
| 47 正裝與嚴肅表情 | 西裝領帶、整理袖口、皺眉思考、平靜注視或一點無奈 | 直接；由手動選擇／已設定情境呈現，不以感測器猜人格或心情 | Watch；不需健康權限 | 檢查不被自動加腮紅、大笑、愛心等覆蓋；正式、認真、得意等各自可選 | 使用者本輪方向；[S01][S07] |
| 48 多套睡衣與睡帽 | 星星睡衣之外，提案條紋、格紋、素色；可睏、安靜看書或剛起床 | 直接本地衣櫥＋可選時段規則；穿睡衣不必等於已入睡 | Watch；手機睡眠捷徑可選 | 分開保存服裝與場景；手動服裝不被定時規則悄悄覆蓋；數套逐件驗收 | 使用者本輪方向；[S15][S19] |
| 49 手動泡澡小劇場 | 角色坐浴缸、頂毛巾、泡泡、小鴨；可閉眼放鬆，也可一本正經 | 直接視覺＋替代觸發；按「泡澡」即可，不要求手錶真的入水，也不宣稱偵測使用者泡澡 | Watch本地；浴室 NFC 方案另需相容 iPhone／標籤 | 先做手動開始／結束、過期恢復；再接 iPhone NFC→Intent→WC 或自訂時段；保留事件來源 | 使用者本輪方向；[S10][S11][S19][S30] |
| 50 入水／智慧家庭輔助切景 | 收到已啟用的入水或家居情境線索後，提示「切換泡澡場景？」 | 感測能力直接、泡澡判定不可直接取得、整合待實機；Water Lock不是入水或泡澡證據，濕度／浴室燈也不能辨識誰在泡澡 | 支援深度的 Watch、Motion授權、depth capability及適合session；或使用者已有的Home感測器／中樞 | 先查型號與runtime availability；入水只能標記入水。家居到本App的傳遞需獨立驗證，不假設Home automation可任意執行手機App Intent／WC | [S43][S44][S45][S46][S47][S50] |

### Apple Watch能否知道「正在泡澡」？

**沒有查到公開的「泡澡偵測」API。**手錶可以在特定條件下取得水中資料；把這些資料解讀成泡澡仍是推測。本專案先採手動場景，NFC或定時是使用者指定的觸發，智慧家庭是可選研究，不作已自動偵測的宣稱。

| 能力 | 官方範圍與本專案處理 |
|---|---|
| Water Lock | 防止觸控誤觸、解鎖時排出喇叭的水；可以手動開啟，也會隨部分水上活動啟用。單憑開啟狀態不能證明手錶已入水，更不能證明泡澡；它不是增強防水的功能。[S43] |
| 系統Depth／水溫 | 當前手冊列Series 10及後續支援機型可測至6米、Ultra系列至40米；SE不能因代數較新就算支援。已查到Series 10／11與Ultra的官方說明，使用者型號仍未知。Depth是水中活動資訊，不是浴缸或淋浴辨識。[S44] |
| 第三方即時資料 | `CMWaterSubmersionManager`提供入水事件、深度、壓力、水溫；需`NSMotionUsageDescription`、使用者授權及對應capability。Shallow Depth and Pressure上限6米；完整40米權利需向Apple申請。以`waterSubmersionAvailable`檢查真機，不在Simulator假裝測到。[S46][S47] |
| 文件版本與session | 某些Core Motion範例仍以Ultra為例，但Apple的watchOS更新已明確寫Series 10支援淺水capability，不能據舊範例斷言只有Ultra。背景水中session／自動開啟另有設定與生命週期；不應為寵物動畫虛構潛水或workout。[S45][S47] |
| 存下的健康樣本 | 深度／水溫也可作HealthKit樣本；讀取需要相關同意，樣本到達不保證就是目前狀態。洗手、游泳和泡澡可能都有接觸水，缺資料也不能判定沒有泡澡。[S45][S22] |

**泡澡與熱水的實際使用條件**：Apple明列應避免接觸肥皂／肥皂水（包含淋浴、泡澡）及蒸氣室；這不等於宣稱所有清水接觸都不允許。Ultra水中活動的官方水溫範圍為0–40°C；一般Series／SE的0–35°C是環境溫度，不能直接當成浴水上限。泡澡動畫可在手錶保持乾燥時播放，無需為觸發畫面而讓裝置接觸熱水或沐浴用品。[S48][S49]

最小交付順序：手動泡澡→使用者自訂時段→有配對iPhone時測浴室NFC→已有相容家居設備才評估感測器。浴室燈／濕度事件只作可取消的建議；即使有Home自動化，也須另驗它到手機／Watch App的資料通道。泡澡演出和設定預設留在本機，不使用相機、麥克風或浴室影像；不預設上傳使用時間。[S50]

## 四個不能混在一起的事件

1. **Watch 正在充電**：Watch 的 `WKInterfaceDevice` 提供電池狀態。文件沒有承諾電池變更會在被終止狀態喚醒本 App；先在可執行時讀取，再補演。[S08]
2. **iPhone 接上充電器**：iPhone 個人自動化事件，適合做手機小劇場或通知手錶，不能代表 Watch 充電。[S10]
3. **通知已靜音／有 Focus**：`INFocusStatus` 的一般資訊不是指定的「睡眠」模式，也不是生理上的睡著。[S20]
4. **健康紀錄更新**：HealthKit 資料可能晚到，未讀到資料不等於使用者沒有活動或睡眠，也不能可靠區分拒絕读取與缺資料。[S22]

因此事件需要保留 `source`、發生時間、接收時間與有效期；前景表演、角色持久狀態、通知、widget 更新分開處理。手機送來的「播放表演」過了有效期只更新摘要，不在數小時後突然補播。這是建議的工程契約，尚不代表所有欄位已實作。

## 原生系統與非官方工具的實際位置

- 目前公開的第三方能力是 App、widget／complication、通知與適用系統的 controls。未找到可以將任意派大星程式替換 Apple 原生充電畫面、Nightstand、系統錶面引擎或其他 App 通知音的入口。可交付替代是「寵物 App＋系統入口」，不是聲稱已修改 watchOS。[S04][S07][S12]
- **Clockology**：官方支援圖層、影片／動畫、聲音與按鈕切圖層，適合先驗證可佩戴的角色視覺；匯入素材不等於匯入 Swift。其全螢幕 clock 類型仍是 App，FAQ 的 Return to Clock 一小時設定與喚醒條件要納入體驗；不能當任意寵物資料邏輯或永久原生錶面已獲支援。[S39][S40]
- **AltStore／Sideloadly**：公開文件主要保證 iPhone／iPad 等平台；截至查證日沒有取得其能把本專案完整 watch payload 正確簽名並安裝的證據。因此可列研究候選，不作交付承諾；iPhone 版能裝不代表 Watch 版能裝。[S41][S42]
- 若要研究特定舊系統工具或越獄方案，第一步是確認**Watch型號、watchOS、配對iPhone及iOS**和維護中的原始專案支援表；不能先叫使用者降級、解除配對或付費買簽名。此次沒有執行這類操作。

## 建議實作順序與完成條件

1. **先讓寵物本身成立**：摸摸、餵食、手動心情、睡覺、衣櫃、事件保存、離線恢復與可選手臂時計。全部用本地規則即可，先不等健康權限或手機自動化。
2. **把日常連起來**：正確的 Watch 電量、前景充電小劇場、時段／節日、專注計時、complication入口、手機設定同步。
3. **再加可選整合**：指定睡眠捷徑、NFC道具、天氣、Calendar、照片、活動摘要；權限拒絕仍保留基本寵物。
4. **最後做需真機的即時能力**：運動 session／mirroring、BLE、double tap、controls、音訊路由、Always-On功耗。測試必須涵蓋前景、離開App、手機離線、Watch鎖定及通知干擾。

每項功能至少要留下：來源／版本條件、可重現觸發方式、預期畫面、拒絕權限／離線替代，以及一次真正裝置結果。瀏覽器模擬可驗外觀與狀態邏輯，不能證明傳感器、簽名、背景喚醒或真機功耗。

安裝、沒有 Mac、免費／付費帳號及家人設定路線另見 [INSTALLATION.md](INSTALLATION.md)。

## 來源索引

以下均於 2026-09-27 查閱；URL未加追蹤參數。情境中的動作設計是本專案提案，來源只支持其 API／平台依據。

[S01]: https://developer.apple.com/documentation/watchos-apps/creating-independent-watchos-apps "Apple — Creating independent watchOS apps"
[S02]: https://developer.apple.com/videos/play/wwdc2025/334/ "Apple — What's new in watchOS 26"
[S03]: https://developer.apple.com/documentation/watchos-apps/enabling-double-tap "Apple — Enabling double tap"
[S04]: https://developer.apple.com/documentation/watchos-apps/designing-your-app-for-the-always-on-state "Apple — Always On state"
[S05]: https://developer.apple.com/documentation/watchos-apps/updating-watchos-apps-with-timelines "Apple — Timelines"
[S06]: https://developer.apple.com/documentation/watchkit/wkinterfacedevice "Apple — WKInterfaceDevice"
[S07]: https://developer.apple.com/documentation/watchos-apps "Apple — watchOS apps"
[S08]: https://developer.apple.com/documentation/watchkit/wkinterfacedevice/batterystate "Apple — Watch battery state"
[S09]: https://support.apple.com/en-euro/guide/watch/apd2b717523a/watchos "Apple — Charge Apple Watch"
[S10]: https://support.apple.com/zh-hans/guide/shortcuts/apde31e9638b/10.0/ios/27 "Apple — Shortcuts setting triggers"
[S11]: https://developer.apple.com/documentation/watchconnectivity/wcsession "Apple — WCSession"
[S12]: https://support.apple.com/en-ie/guide/watch/apd27ce65478/watchos "Apple — Alarms and Nightstand"
[S13]: https://developer.apple.com/documentation/activitykit "Apple — ActivityKit"
[S14]: https://developer.apple.com/documentation/watchkit/using-extended-runtime-sessions "Apple — Extended runtime sessions"
[S15]: https://developer.apple.com/documentation/foundation/datecomponents "Apple — DateComponents"
[S16]: https://developer.apple.com/documentation/foundation/calendar/identifier-swift.enum/chinese "Apple — Chinese calendar"
[S17]: https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app "Apple — Local notifications"
[S18]: https://developer.apple.com/weatherkit/ "Apple — WeatherKit requirements and attribution"
[S19]: https://developer.apple.com/documentation/appintents "Apple — App Intents"
[S20]: https://developer.apple.com/documentation/intents/infocusstatuscenter "Apple — Focus status"
[S21]: https://developer.apple.com/videos/play/wwdc2022/10005/ "Apple — HealthKit sleep data"
[S22]: https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data "Apple — HealthKit authorization"
[S23]: https://developer.apple.com/videos/play/wwdc2024/10109/ "Apple — Wellbeing APIs"
[S24]: https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn "Apple — HRV SDNN"
[S25]: https://developer.apple.com/documentation/healthkit/hkactivitysummaryquery "Apple — Activity summary"
[S26]: https://developer.apple.com/documentation/healthkit/hkworkoutsession "Apple — Workout sessions"
[S27]: https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype "Apple — Workout activity types"
[S28]: https://developer.apple.com/videos/play/wwdc2023/10023/ "Apple — Multi-device workout apps"
[S29]: https://developer.apple.com/documentation/healthkit/hkworkoutconfiguration/activitytype "Apple — Workout configuration"
[S30]: https://developer.apple.com/design/human-interface-guidelines/nfc "Apple — NFC platform support"
[S31]: https://developer.apple.com/documentation/watchkit/interacting-with-bluetooth-peripherals-during-background-app-refresh "Apple — Bluetooth background sample"
[S32]: https://developer.apple.com/documentation/usernotifications/unnotificationsound "Apple — Notification sound"
[S33]: https://developer.apple.com/documentation/watchkit/enabling-background-sessions "Apple — Audio, location and workout sessions"
[S34]: https://developer.apple.com/documentation/eventkit/accessing-the-event-store "Apple — Calendar access"
[S35]: https://developer.apple.com/documentation/technotes/tn3153-adopting-api-changes-for-eventkit-in-ios-macos-and-watchos "Apple — EventKit version changes"
[S36]: https://support.apple.com/en-nz/guide/shortcuts/-apd690170742/ios "Apple — Personal automation"
[S37]: https://developer.apple.com/musickit/ "Apple — MusicKit"
[S38]: https://developer.apple.com/documentation/photokit/bringing-photos-picker-to-your-swiftui-app "Apple — Photos picker"
[S39]: https://clockologyapp.com/about-us/ "Clockology — Supported features"
[S40]: https://clockologyapp.com/faq/ "Clockology — Return to Clock limitations"
[S41]: https://faq.altstore.io/ "AltStore — Official docs"
[S42]: https://sideloadly.io/ "Sideloadly — Official supported platforms"
[S43]: https://support.apple.com/en-us/108352 "Apple — Water Lock prevents unintended taps and ejects speaker water"
[S44]: https://support.apple.com/en-ke/guide/watch/apd9073c83d6/watchos "Apple — Depth app, supported Watch models and depth limits"
[S45]: https://developer.apple.com/documentation/updates/watchos "Apple — Series 10 shallow-depth capability and HealthKit samples"
[S46]: https://developer.apple.com/documentation/coremotion/cmwatersubmersionmanager "Apple — Live submersion data, permission and capabilities"
[S47]: https://developer.apple.com/documentation/coremotion/accessing-submersion-data "Apple — Device availability, underwater sessions and device testing"
[S48]: https://support.apple.com/en-us/109522 "Apple — Water resistance, soap, bathing and steam-room conditions"
[S49]: https://support.apple.com/en-us/108766 "Apple — Ambient and underwater temperature ranges"
[S50]: https://support.apple.com/en-ae/102313 "Apple — Home scenes, accessory and sensor automations"
