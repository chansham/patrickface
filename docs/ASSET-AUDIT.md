# 素材審核與清理紀錄

審核日期：2026-09-27。畫風已重新開放選擇；2D、3D、水墨、抽象都保留為候選。技術檢查通過不代表使用者批准。清理過程沒有為湊數生成新美術；後續依新授權加入的概念圖另記於下方。

## 本輪範圍與證據

- 專案媒體逐檔盤點在 `asset-audit.json`；人工判斷及刪除記錄保存在 `asset-audit-decisions.json`，可由 `../tools/audit_assets.py` 重新整理。
- 檢查圖片實際編碼、尺寸、能否解碼、alpha、空圖；style-library 另檢查 1024/256 註冊畫布及手臂軸心。
- 逐張看過 120 張 style-library 原尺寸部件的六張聯絡表，並檢查其 120 張 runtime 檔；查看交付包全部圖片、舊 runtime／rejected-runtime 聯絡表。聯絡表只是現有檔案的檢視縮圖，沒有新增美術。
- motion-lab 只有一張六格 SVG 特效圖集，沒有獨立跑步／健身等運動角色素材。它的 CSS 引用與 SVG 幾何有效；它是泡泡／閃光播放佔位，不能描述成完整角色動作。
- 原 `references/`、來源比較圖與歷史原畫未刪除。不同畫風、未批准、或只可作概念參考不等於檔案不能用。

## 已實際刪除：22 檔

前一輪移除以下 8 檔；最後另退役 14 份無引用的 runtime 拷貝與其設定。合計 22 檔，不包含任何畫風候選原體。

| 原路徑（專案相對） | 依據與保留替代 |
|---|---|
| `delivery/theme-pack/qr/create-new-shortcut-900x900.png` | 第一輪 QR 帶多餘換行；保留 `verified-create-new-shortcut-900x900.png`。 |
| `delivery/theme-pack/qr/official-shortcuts-guide-900x900.png` | 第一輪 QR 帶多餘換行；保留 `verified-official-shortcuts-guide-900x900.png`。 |
| `delivery/theme-pack/qr/run-patrick-mode-900x900.png` | 第一輪 QR 帶多餘換行；保留 `verified-run-patrick-mode-900x900.png`。 |
| `delivery/theme-pack/qr/payloads/create-new-shortcut.txt` | 原 bytes 末尾為 CRLF；保留對應 `verified-` 精確連結。 |
| `delivery/theme-pack/qr/payloads/official-shortcuts-guide.txt` | 原 bytes 末尾為 CRLF；保留對應 `verified-` 精確連結。 |
| `delivery/theme-pack/qr/payloads/run-patrick-mode.txt` | 原 bytes 末尾為 CRLF；保留對應 `verified-` 精確連結。 |
| `delivery/theme-pack/source-layers/season1-3d-comparison-approved.png` | 交付包中的歷史重複合成圖，帶黑底，並非可用透明分層；SHA 完全相同的 `comparison-season1-3d/assets/season1-faithful-3d.png` 保留。不是因為不喜歡該畫風而刪除原圖。 |
| `motion-lab/.playwright-cli/page-2026-09-23T14-13-47-700Z.png` | 1029×742 RGB 圖片只有一種顏色：每個像素都是純白 `(255,255,255)`，沒有任何動畫或畫面驗收證據；原 console／DOM 記錄保留。 |

最後 runtime 退役前，已掃描目前 Swift、JS、HTML、CSS，未找到六個舊圖片名稱的使用引用。下列 14 檔全部逐一備份、SHA 比對，再用已確認在工作區內的明確路徑刪除：

| 退役路徑 | 依據 |
|---|---|
| `preview/assets/arm.png` | 無引用的舊手臂 runtime 拷貝，現用 season1 手臂保留。 |
| `preview/assets/body.png` | 無引用的舊角色 runtime 拷貝，現用 season1 身體保留。 |
| `preview/assets/body-night.png` | 無引用的舊睡衣角色 runtime 拷貝，歷史／候選來源保留。 |
| `preview/assets/dial.png` | 無引用的舊錶盘 runtime 拷貝，現用程式繪製錶盤保留。 |
| `preview/assets/icon.png` | 無引用的舊 runtime 拷貝；內容是 JPEG 配 PNG 副檔名。 |
| `preview/assets/wallpaper.png` | 無引用的舊 runtime 拷貝；內容是 JPEG 配 PNG 副檔名。 |
| `PatrickFace/Assets.xcassets/arm.imageset/arm.png` | 舊圖集無 Swift 引用。 |
| `PatrickFace/Assets.xcassets/arm.imageset/Contents.json` | 隨無引用圖集退役；完整保留使用者已修改 bytes。 |
| `PatrickFace/Assets.xcassets/body.imageset/body.png` | 舊圖集無 Swift 引用。 |
| `PatrickFace/Assets.xcassets/body.imageset/Contents.json` | 隨無引用圖集退役；完整保留使用者已修改 bytes。 |
| `PatrickFace/Assets.xcassets/body-night.imageset/body-night.png` | 舊圖集無 Swift 引用。 |
| `PatrickFace/Assets.xcassets/body-night.imageset/Contents.json` | 隨無引用圖集退役；完整保留使用者已修改 bytes。 |
| `PatrickFace/Assets.xcassets/dial.imageset/dial.png` | 舊圖集無 Swift 引用。 |
| `PatrickFace/Assets.xcassets/dial.imageset/Contents.json` | 隨無引用圖集退役；完整保留使用者已修改 bytes。 |

四份 `Contents.json` 的 BOM 相關既有修改沒有重置；退役前保存的是工作樹實際內容（目前四份都無 UTF-8 BOM），每份 SHA、大小與備份路徑記錄在機讀 decisions 及備份索引。

## 已替換：3 份落後版本的交付手臂

| 交付包內檔名 | 本輪替代來源 | 新尺寸 |
|---|---|---|
| `source-layers/season1-2d-hour-arm-approved.png` | `preview/assets/season1-hour-arm.png` | 431×904 |
| `source-layers/season1-2d-minute-arm-approved.png` | `preview/assets/season1-minute-arm.png` | 431×976 |
| `source-layers/season1-3d-arm-approved.png` | `preview/assets/season1-3d-arm.png` | 454×924 |

三者與現用來源逐位元相同，manifest 已更新尺寸、大小、SHA。舊檔名的 `approved` 只是歷史名稱，並不表示本次使用者批准。包內六份來源層分類已改成 `candidate-source-layer`。既有 wallpaper／widget／10:10 合成圖沒有重繪，仍是較早版本的靜態構圖候選，不能宣稱已全部跟隨新的軸心重建。

## 保留與待審

- **style-library 全部 240 張部件 PNG 保留。** 六種畫風、120 份來源與120份 runtime 都有透明畫布，沒有空圖、解碼失敗或軸心透明問題。手指尖、菱形眼、細腳比例、水墨半透明等需要使用者審美選擇；沒有把它們當壞圖刪掉。manifest 和生成器都標記 `pending-review`。
- **motion-lab SVG 特效保留。** 它有實際引用；缺完整角色動畫屬功能／內容尚未完成，不是圖集損壞。未刪除運動／動作功能類別。
- **靜態 widget 圖保留為待審構圖。** 部分矩形／圓形圖故意裁切角色、附佔位線條，不是可直接運作的 WidgetKit 小工具；仍需確認構圖、資料布局和實機效果。
- **舊 preview 和 Xcode runtime 拷貝已退役，sources/rejected-runtime 保留。** 舊 body／body-night／arm／dial 能正常顯示，不稱為壞圖；本次依無引用、已有現用替代而從 runtime 移除。`references/` 與 `sources/rejected-runtime/` 仍作歷史證據。
- 其他來源／比較圖也發現副檔名和實際編碼不同，已列入 `technicalIssues`。這與空圖或損壞不同；為保留來源證據，未擅自刪除或改名。

## 新增概念圖第二輪檢查

後續收到使用者匯出意見：正裝、下班、街頭3張v1不喜歡，現已標記 `rejected` 並保留舊版比較；另外2張本次未標記。重畫嘗試未生成新圖，詳細追蹤见 `FEEDBACK-2026-09-27.md`。下列5張成功數是當時的生成紀錄，不是目前待選圖數。

`concepts/2026-09-27-wardrobe/` 新增5張實際PNG：正裝、下班、泡澡、偵探、街頭。每張已解碼、驗SHA與透明通道，並檢視生成輸出及衣櫥顯示；仍屬尚未拆層的造型稿。下班及街頭3D圖有彩色光暈、alpha最大值254；泡澡及街頭的少量邊緣像素接觸畫布，正式透明部件需要修邊。這些限制已逐筆寫進decisions，保留原圖供選擇。

另3款睡衣遭圖片服務輸出檢查攔截，沒有圖檔；衣櫥顯示設計文字及「未生成／待補」，不把缺圖計入完成數。第二批提示與結果保存在同目錄的 `prompts.json`、`generation-report.json`。連同第一批共8張可檢視概念圖。

## 新增概念圖第一輪檢查

`concepts/2026-09-27/` 的以下三張 PNG 已收到使用者本輪正向回饋，全部保留。它代表這批造型的正向回饋，不等於整體畫風定案或正式素材批准；狀態仍為 `pending-review`、技術定位為 `concept-only`。本輪只讀圖片，沒有刪除、修改像素或重新去背。

| 概念圖 | 完整性、透明與小尺寸觀察 |
|---|---|
| `bedtime-cel-v1.png` | 1199×1312 RGBA；角色、睡帽、枕頭與脚部完整，alphaBounds `[33,24,1106,1272]`，四邊皆透明。220 px與80 px縮圖仍可辨識睡前情境；正式使用仍需修邊及拆分服裝／道具／手臂。 |
| `charging-cel-v1.png` | 1223×1286 RGBA；角色與坐墊目視完整，電池／閃電在220 px與80 px仍清晰。alphaBounds `[0,45,1222,1286]` 碰左側與底部；左緣8、底緣10個非零alpha像素皆非完全不透明，屬少量邊緣雜點。**concept-only，正式使用需修邊／清理雜點／拆層**，保留使用者喜歡的原圖。 |
| `fitness-toon-v1.png` | 1145×1374 RGBA；頭、手、腳與啞鈴未裁切，alphaBounds `[45,15,1083,1344]`，四邊皆透明。220 px可辨識頭帶、毛巾及啞鈴；80 px仍有運動辨識度但細節減少。輪廓有少量白色／彩色去背邊緣，正式使用仍需修邊／拆層。 |

三張目前均是單張合成概念，尚不能直接當獨立手臂報時、換裝或完整動畫素材。縮圖只在記憶體顯示作檢查，沒有另外輸出圖片。

## 驗證与防止舊產物重生

- 交付包目前 **105 份媒體：95 張圖片、10 份音訊**。新檢查 `delivery/theme-pack/reports/asset-cleanup-validation.*` 結果 **PASS**：檔案、尺寸、SHA、透明圖、QR 解碼精確 payload、音訊 codec／頻率／聲道／無靜音或削波、無漏列媒體。
- 驗證器新增已退役檔案禁入檢查，以及三張交付手臂和 runtime 必須一致的檢查。
- builder 不再登記舊 QR 或重複歷史比較圖，預設拒絕覆蓋已有包。需要明確 `--overwrite` 才重建，並先在專案外備份及驗證；已實際確認預設會停止，未重建美術。
- 原本已修改的兩份 `validation-report.*` 保持原 bytes；新結果寫不同檔名。四份 Xcode `Contents.json` 後來獲明確退役授權，先完整備份既有修改再刪除，沒有重置。
- `tools/validate_watch_project.py` 保留新原生功能檢查，改為要求舊 PNG／Contents 與 preview 舊檔不存在，並要求程式無引用；結果 **135 項通過**。原生來源回歸檢查 **6 項通過**。
- `tools/sync_xcode_assets.py` 只允許現用五個 season1 名稱，另加退役名稱防線；`tools/chroma.py` 改為必須指定新的歷史匯出資料夾，禁止寫進 preview／Watch／iPhone runtime，已實測拒絕 `--output preview/assets`。沒有執行任何新圖片輸出。
- **清理完成時為584筆**（包含已刪除檔案記錄）：待審434、歷史／參考保留125、替換3、移除22。後續新增概念圖會增加盤點筆數，當前數量以 `asset-audit.json` 為準；新增概念不改變本輪已移除22檔、替換3檔與37份備份的記錄。

## 恢復

外部備份：`<USER_HOME>/.codex/backups/PatrickFace-assets-20260927/`。`BACKUP-INDEX.json` 記錄 37 份原檔的路徑、SHA-256 與大小；刪除／覆蓋前都逐檔核對，包含四份已有使用者修改的 `Contents.json`。機讀 decisions 另記錄每份刪除／替換檔案的 backupPath。恢復前應確認後續修改，避免覆寫新的工作。

重跑盤點：`python -X utf8 tools/audit_assets.py --sheets`。這只更新盤點及聯絡表，不刪素材、不產生新美術、不給任何素材自動批准。
