# 原創短音效

六個音效由本機數學波形合成，沒有錄音、人聲、既有卡通音訊或下載音樂。每個檔案都是 44.1 kHz、16-bit、單聲道 PCM WAV。來源公式在 `tools/build_experience_audio.py`，可重現相同位元組。

| ID | 時長 | 用途 |
|---|---:|---|
| bubble | 340 ms | 小泡泡／輕微環境互動 |
| pet | 460 ms | 摸摸回應 |
| feed | 420 ms | 投餵回饋 |
| complete | 780 ms | 計時完成／小成就 |
| wake | 820 ms | 手動早安／回到清醒狀態 |
| softclick | 110 ms | 輕觸選項 |

`manifest.json` 的 `path` 為專案相對路徑；原生資源包可移除開頭的 `experience/`。`durationMs` 是毫秒，`gain` 是播放音量乘數。峰值約 0.15（−16.48 dBFS），建議播放增益 0.45；这不能保證不同裝置的主觀音量相同。

`haptic` 是 `gentleTap`／`success` 的語義名稱，由原生程式自行對應可用的觸覺回饋，並不是已验证的 Apple API 名稱。

聲音預設關閉，只有使用者明確開啟後才在 App 前景播放，避免短時間重疊播放；靜音時視覺與文字仍要完整。這些音效不取代系統通知、來電或充電聲，也不能用來維持背景常駐。

實際檔案已通過標頭、SHA、時長、峰值、無削波、低直流偏移及頭尾靜音檢查。尚未完成手錶揚聲器／耳機的實際試聽，檢查通過不等於真機聽感已驗收。

重建：`python -B -X utf8 tools/build_experience_audio.py`。只讀核對：在同指令後加 `--check`；獨立檢查：`python -B -X utf8 tools/validate_experience_audio.py`。
