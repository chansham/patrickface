# 每批動畫的尺寸與美術驗收

每批新增或改稿，都要完成以下三道檢查。它們不修改 PNG、輪廓或倍率，也不會把候選加入日常或原生資源。

## 1. 先核對量測證據

從本批 catalog 的實際 ID 選取，執行唯讀門檻：

```powershell
node tools/check_animation_acceptance.mjs `
  --audit animation/production-20261007-completion/body-scale-audit.json `
  --clip-ids chef-cookie-repair-20261007,focus-transition-repair-20261007,charging-cozy-20261007 `
  --output output/playwright/20261008-acceptance/evidence.json
```

`--audit` 可以重複；日常資源另加 `--catalog animation/catalog.json`。必須明確提供本批 ID，不能因新稿尚未列入固定清單而漏驗。輸出檔限 `output/`。

門檻實際核對原 PNG、輪廓、原量測來源／landmark 的 SHA，以及每個原始來源格的紀錄；即使播放沒有啟用某格，也不能漏掉。臉寬、两眼下緣間距和真腳底距離必須有對應尺線；未知要保留原因，不准拿透明畫布、帽子、衣服、道具或坐墊外框補值。

- Exit `0`：證據完整；仍需逐格及正常速度的人工審稿。
- Exit `2`：漏格、重複格、過期 SHA、無效尺規或缺少圖稿等，停止宣稱該批已完成尺寸驗收。
- 所有結果保留 `artApproval: false`、`reviewRequired: true`。零個警告也不是美術批准。

整份 catalog 的 SHA 是歷史快照，不以新增其他候選造成的 catalog 變動誤判舊圖過期；採用精確 clip ID、catalog 類別、PNG SHA、輪廓 SHA。顯示尺寸按目前整段固定倍率換算，不能把舊報告預算的舞台大小當作目前畫面。

## 2. 同尺規人工看角色本體

在 `/size-review/?review=candidates&right=<ID>` 看大圖與 200 px 內容舞台、舊稿／新稿、首格／末格及全部四款版式。卡片會明示每段每個人體尺規的可量格數、首末差異，以及全部來源格中哪些仍未知；任何完整性錯誤會停用該段量測數字和尺線，圖稿及既有意見仍可查看。

首末相差或全段最大／最小相差超過 8% 只要求人工確認。表情、轉頭、傾斜、坐姿、側身都會改變可見代理值，不能据此自動縮放。首或末格未知時，差異也必須是未知，不用附近可量格代替。

必看：臉和身體相對其他造型的大小、頭身比例、眼嘴位置、真正腳底與道具支撐的區別；再看時間、日期、資訊欄是否被任何一格遮擋。四款版式使用同一段倍率；不得逐格 fit、縮放或全身擺動掩蓋原畫問題。200 px 是內容舞台寬，並非原生 Watch 全螢幕的等比例承諾。

## 3. 正常 1× 播放與交付

逐格完整可見之後，仍須正常 1× 播一次，確認臉／身體尺寸沒有突然跳變，手、道具和表情過渡合理，末格停住而非偷偷循環。保存所看 clip／PNG／輪廓版本、畫格與版式，以及對應截圖／錄影或實際 draw 時序證據。未能量測的格必須人工看，不能因證據完整就跳過。

交付列出：本批實際來源數／原始格數、每項人體尺規覆蓋、首末未知、固定整段倍率、人工看過的畫格／播放和剩餘缺陷。清楚分開「證據完整」「播放正常」「人物比例仍待修」「使用者批准」。本工具不產生最後一項。

## 回歸

```powershell
node --test tools/test_animation_acceptance.mjs
node size-review/test-acceptance-browser.cjs
```

瀏覽器測試沿用專案 Playwright runtime，可用 `PLAYWRIGHT_PACKAGE` 與 `CHROMIUM_EXECUTABLE_PATH` 指向已安裝版本；不需安裝新瀏覽器。使用隔離 context，驗漏格／過期 SHA 會阻擋數字與尺線、首末固定倍率、390 px 手機介面和本機意見不變。它不代替人工視覺驗收。
