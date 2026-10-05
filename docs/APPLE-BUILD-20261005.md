# 2026-10-05 Apple 編譯接續

使用者要求繼續前輪工作；依先前提出的私人 GitHub 路線，準備 `codex/apple-watch-integration` 獨立分支。使用者後來明確選擇改用 chansham；已完成該帳號 repo/workflow 授權，並在 chansham/patrickface 建立 PRIVATE 倉庫。舊帳號倉庫未更改，沒有 App Store／TestFlight 發布。

## 本機實際復查

- 預覽服务恢復，11套衣服、15播放變體、13候選載入與隔離通過；無404／JS錯誤。報告：`output/playwright/20261005-resume/report.json`。
- 原生四項修正已落盤：舊計時同步護欄、睡衣待機眨眼、餵食前先結算飽足衰減、前景且非低耗電／減少動態的充電泡泡。
- 123項Watch工程檢查、companion結構、6項來源回歸、3項包裝負面測試、腳本語法通過。Swift與XCTest必須由Apple環境執行，不能拿前述項目代替。
- 主／候選來源、兩端資源和三批QC未漂移。每端共用資源22.141MiB；實際app大小待建置。
- 發現Git換行正規化會改掉有SHA契約的JSON bytes，已用`.gitattributes`保留JSON原bytes、shell腳本統一LF，提交前核對93個JSON逐bytes一致。

## 此次雲端工作

只在私人倉庫的獨立分支跑無簽名：Foundation邏輯測試、Watch與iPhone simulator建置、XCTest，以及iPhone包含Watch／小工具／資源的實際產物檢查。編譯通過後再做unsigned device archive。診斷log與XCTest result bundle保留7日；XCTest執行使用已安裝runtime，不下載額外系統。

上傳：舊帳號push因workflow scope不足而被拒（未建立分支）；目前已改用使用者指定的chansham，PRIVATE倉庫的main保存原基礎395d34c，開發分支已上傳整合版本及偵探候選1c78849。舊倉庫未改動。

| Apple 執行 | 版本 | 已取得的證據 |
|---|---|---|
| [首輪](https://github.com/chansham/patrickface/actions/runs/37253494668) | 1c78849 | Xcode 26.6／Apple SDK 26.5確實啟動；首個Foundation編譯在PatrickShared.swift guard尾隨closure語法失敗，尚未建置App |
| [第二輪](https://github.com/chansham/patrickface/actions/runs/37253740741) | 23600d1 | 1503項Foundation規則、109項動畫、51項體驗檢查實跑通過；Watch SwiftUI畫面因過長expression無法在合理時間type-check而失敗，尚未進手機建置或archive |
| [第三輪](https://github.com/chansham/patrickface/actions/runs/37254061355) | a6d0de5 | Watch與iPhone雙平台建置、widget／complication、實際嵌入包及素材SHA通過；Foundation 1503／129／54項通過；iPhone Air／iOS 26.5模擬器實跑XCTest 7項，存檔時間精度比較1項失敗，archive尚未執行 |
| [第四輪：通過](https://github.com/chansham/patrickface/actions/runs/37254670555) | f6daa08 | Foundation 1503／129／63項通過；兩端App與兩個extension編譯通過；iPhone Air／iOS 26.5上9項XCTest全過；Release裝置archive成功，實際封存包內4個product版本／ID／所有素材SHA通過。無簽名，不可安裝或提交 |
| [第五輪：通過](https://github.com/chansham/patrickface/actions/runs/37255135621) | bfaaa04 | 上述建置、1695項Foundation、9項XCTest及archive再通過；另取得iPhone Air／iOS26.5和Series11 42mm／watchOS26.5真正模擬器截圖。角色方向、頭腳及眼白正常；Watch頂部兩處時間過近，下一版修正安全區並改驗46mm |
| [第六輪：通過](https://github.com/chansham/patrickface/actions/runs/37256581810) | 9d6e095 | 1695項Foundation、9項XCTest、雙平台與4產品封存檢查再通過；另12項封裝測試全部通過（Mac符號連結案例也實跑）。產出未簽名IPA。Series11 46mm／watchOS26.4的416×496截圖已實看，系統時間與自訂時間分開、角色頭腳完整；iPhone Air／iOS26.5畫面正常 |

原始log保存在本機`output/apple-build/`；不把第一次失敗當作帳號或額度阻擋，因runner已實際執行編譯。

## Windows 試裝輸入已就緒

- 本機檔案：`output/apple-build/run-37256581810-artifacts/patrick-unsigned-resigning-input-6/PatrickCompanion-unsigned.ipa`，45,178,729 bytes，版本1.0／build6。
- SHA256：`a60802223ff36887de9ce4866e5ef2c1b1cc2bcc45d08ce882da54ecb2d34319`。下载后已重新核對SHA及ZIP內154個項目，每個原始檔案bytes、mode與link一致，保留iPhone、Watch、widget、complication。
- 同目錄包含完整manifest及SHA檔。四個可執行檔已檢查為真機平台、沒有簽名或provisioning profile；不是simulator改副檔名。**仍需以使用者帳號重簽，不能直接安裝。**
- 私人artifact名稱為`patrick-unsigned-resigning-input-6`，GitHub保留7天；已下載本機的檔案不受這個到期日影響。沒有公開release或Apple提交。
- 原始截圖與額外人工視覺檢查記錄位於`output/apple-build/run-37256581810-artifacts/apple-build-diagnostics-6/native-screens/run-20261005T024734Z-12421/`。檢查只涵蓋這次啟動畫面，不能替代所有動作、功能或Series12／OS27真機驗收。

## 仍未完成

沒有簽名IPA、Apple裝置安裝或耗電驗收。使用者已確認只有一般Apple帳號且沒有Mac，不預設TestFlight條件已具備。Sideloadly v0.70.1官方changelog已列出WatchKit保留及重簽支援，正在準備Windows試裝輸入；簽名及Watch端安裝結果仍未知。新美術仍未全部修好或批准，來源生成失敗項仍在素材清單；原生已補「找個小驚喜」入口、六句輪替、60秒冷卻與日記，並修正背景完成補播及過期音效。Apple編譯、邏輯測試和首輪simctl截圖已取得證據；這些仍不代表實機聲音、動畫效能、跨裝置同步或素材美術已驗收。
