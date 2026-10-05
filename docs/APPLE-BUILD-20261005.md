# 2026-10-05 Apple 編譯接續

使用者要求繼續前輪工作；依先前提出的私人 GitHub 路線，準備 `codex/apple-watch-integration` 獨立分支。既有 main 不變，沒有 App Store／TestFlight 發布。

## 本機實際復查

- 預覽服务恢復，11套衣服、15播放變體、13候選載入與隔離通過；無404／JS錯誤。報告：`output/playwright/20261005-resume/report.json`。
- 原生四項修正已落盤：舊計時同步護欄、睡衣待機眨眼、餵食前先結算飽足衰減、前景且非低耗電／減少動態的充電泡泡。
- 123項Watch工程檢查、companion結構、6項來源回歸、3項包裝負面測試、腳本語法通過。Swift與XCTest必須由Apple環境執行，不能拿前述項目代替。
- 主／候選來源、兩端資源和三批QC未漂移。每端共用資源22.141MiB；實際app大小待建置。
- 發現Git換行正規化會改掉有SHA契約的JSON bytes，已用`.gitattributes`保留JSON原bytes、shell腳本統一LF，提交前核對93個JSON逐bytes一致。

## 此次雲端工作

只在私人倉庫的獨立分支跑無簽名：Foundation邏輯測試、Watch與iPhone simulator建置、XCTest編譯，以及iPhone包含Watch／小工具／資源的實際產物檢查。編譯通過後再做unsigned device archive。診斷log保留7日。

狀態：分支已在本機準備，等待推送取得run結果。此記錄尚無Apple編譯通過的證據。

## 仍未完成

沒有簽名IPA、Apple裝置安裝或耗電驗收。Apple Developer會員／簽名資料尚未確認。新美術仍未全部修好或批准，來源生成失敗項仍在素材清單；網頁小彩蛋尚未全部移植原生。所有後續結果會附實際run連結和commit，避免把準備當作成功。
