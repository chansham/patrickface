# 2026-10-06 素材定位、版式與互動整合

使用者暫時無法連接手機，要求先補素材、運動、軟件適配與錶盤版本。本輪不是安裝，也沒有把所有素材標為完成或批准。

後續的「人物本體大小」校準已另完成，見[本體盤點](BODY-SCALE-AUDIT-20261006.md)及[原生實測](RENDER-SCALE-CROSSCHECK-20261006.md)。該版本Apple run37403688597已通過；最新試裝輸入為[build9及校驗資料](INSTALLATION.md)。以下build7／8資料保留為當次整合的歷史證據。

## 實際變更

| 項目 | 本輪完成 | 仍未完成 |
|---|---|---|
| 裁剪／定位 | 15張圖集、172原格、10,502,246非透明像素全部唯一分配，零漏失零重複；修exercise的腳底定位，13張活躍圖集資源同步兩端 | 原畫缺失、道具握持與身形過渡不是裁剪能修；慶祝16格來源碰底仍存在 |
| 運動動畫 | 啞鈴16格正常1×播放3380ms到末格停止；上部頭輪廓橫向range從18.61降至2.68原像素，原PNG、整段畫布／倍率不变 | 腕部、握持、表情仍需重畫；沒有新的跑步／伸展畫稿 |
| 錶面版式 | classic經典、bold大字、theater劇場、activity運動資訊；共用layouts資料、選擇保存與舊檔fallback | 是App內版式，不替換watchOS系統錶盤；真機尺寸和耗電待驗 |
| 運動陪伴 | 新增walking／running／strength倒數，存檔／日記／原生同步；UI清楚標示共用舉啞鈴造型 | 不啟動Apple健身訓練、不記錄距離或卡路里 |
| 互動／捷徑 | 第8個預置捷徑控制暫停／繼續／結束；原生和網頁到期先結算，重複控制不改期限或重複完成 | 個人自動化、真錶同步、音效／震感、健康權限待裝置驗證 |
| 新原畫 | 兩個獨立內建image_gen請求，提示和原錯誤保留 | 跑步12格、雨衣8格均output moderation_blocked，沒有產出；本輪新增0張 |

主體驗仍是11套造型／15播放編排；候選14組／164張，加原8格哈欠共172張獨立原畫。更多服裝、節日、不同運動與時計接合未齊，見[素材缺口](ASSET-BACKLOG.md)。

## 本機驗證

- 全量圖集來源與輪廓：[contour-audit.json](../animation/production-20261006/contour-audit.json)。所有來源PNG SHA保持不變，原拒絕意見未被改為批准。
- 網頁整體8項通過：`output/playwright/20261006-experience/report.json`，含衣櫥、照顧、音效／安靜、日期、手臂角度、缺圖fallback、三種運動計時與重載。
- 四版式3項通過：`output/playwright/20261006-layouts/report.json`，153個實際使用的來源姿勢×4=612組core像素範圍，12/24時間、日期、資訊區無交疊；320／390手機與200px腕上視窗、設定保存、候選隔離均通過。
- 啞鈴正常速度：`output/playwright/20261006-exercise-anchor/report.json`；此證據不是重畫或美術批准。
- 定位工具12項、資源同步9項、模擬器截圖工具11項、6來源回歸、123 Watch工程檢查及companion結構通過；主／候選目錄0錯誤，保留1個已知來源碰邊warning。

## Apple 環境

私人開發分支版本`82389a9`的[run 37400000919](https://github.com/chansham/patrickface/actions/runs/37400000919)已全部成功：双平台及兩個extensions編譯、1,734項Foundation檢查（1503＋129＋102）、11項XCTest、12項封裝測試、裝置封存、未簽名IPA包裝，以及兩端各四款版式的真正simulator截圖。

已逐張實看8張版式截圖：iPhone Air／iOS26.5與Series11 46mm／watchOS26.4，時間、日期、帽尖、腳底與運動資訊沒有互相遮擋，四款確實呈現不同排列。Watch的bold與theater截圖沒有顯示系統時間及動作選單；這些按鈕受active／wristDown條件控制，本次截圖沒有記錄該條件，不把這兩張當成前景按鈕已驗證。畫面證據限這次初始睡衣畫面，不表示全服裝／全動作、輔助字級或真機已驗收。

另外修正首次收到Watch已暫停倒數時，iPhone Live Activity仍寫成「Timer running」的漏洞。建立與更新改用同一份由snapshot產生的狀態，新增running／paused測例。修復版本`8582124`的[run 37400635967](https://github.com/chansham/patrickface/actions/runs/37400635967)已全部成功：Foundation仍為1734項，XCTest增至12項且0 failure（包含新增Live Activity測例），12項封裝測試、四產品編譯、無簽名封存及两端四版式截圖再次完成。

工具與裝置仍為Xcode26.6／SDK26.5、iPhone Air／iOS26.5、Series11 46mm／watchOS26.4。不是使用者真機或OS27結果。第7輪逐張視覺判讀記錄保存在`output/apple-build/run-37400000919-artifacts/apple-build-diagnostics-7/native-screens/run-20261006T013912Z-15840/visual-review.json`；第8輪捕捉報告在`output/apple-build/run-37400635967-artifacts/apple-build-diagnostics-8/native-screens/run-20261006T014747Z-8956/report.json`。

## 最新試裝輸入：build 8

- 本機：`output/apple-build/run-37400635967-artifacts/patrick-unsigned-resigning-input-8/PatrickCompanion-unsigned.ipa`。
- 版本1.0／build8，45,251,085 bytes；SHA256：`d3011b73a023144ebc2593fa3e226bd0bd33c643f1cae872b6a1e2393615729a`。
- 下載後再次依manifest逐項核對156個項目的原始bytes、類型、Unix權限與符號連結；四產品的ID／版本／平台正確，checksum檔吻合。結果保存於同目錄`local-verification.json`。
- `signed=false`、`directlyInstallable=false`。它是後續Windows重簽的歷史輸入，不能直接裝入Watch；Apple帳號、實際權限、Watch端安裝和續期尚未驗證。build6／7／8保留為歷史產物，後續試裝以build9或更新已驗版本為準。

截圖覆寫參數僅在DEBUG simulator有效，不保存、不傳同步；正式裝置版忽略它。未登入Apple帳號、未簽名、未安裝至使用者Watch。使用者已說稍後再試裝，待其方便時接續Windows路線。
