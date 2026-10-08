# 星星睡衣充電 v2：本批選定候選

2026-10-08 修訂，`charging-cozy-20261007` 使用這張新 PNG。v1 原檔及量測保留為對照，沒有重複計入候選。美術未批准，日常／原生資源不變。

- 第 7 格加入靠上抱枕的傾頭中間姿勢，第 9 格加入回正中間姿勢；正常 1× 比 v1 的直接跳接更清楚。
- 第 7→8、9→10 格角度仍有階躍；帽沿、睡衣、抱枕體積略變，首末也不是完全閉環。這些是原畫待審項目。
- 奶油黃星星睡衣、睡帽、紫拖鞋、白眼白及粉色閉眼眼皮保留。正確 alpha 黑白底合成沒有把透明 RGB 當彩色背景；沒有編輯原 PNG。
- 原圖 1086×1448，3×4 共 12 格。716,097 個 alpha>0 像素唯一分配，0 漏失／重疊，來源四邊 0 非透明像素；強輪廓距四邊最少 53／20／42／30px，頭腳沒有被來源邊截斷。
- 首末臉寬 121→123.5px（+2.07%）、眼下緣距 35.69→35.51px（-0.51%）；含帽輪廓高 345→337px（-2.32%），後者不是人體身高。只量過可靠中性首末眼白，其餘眼尺規留空；全部真足底數值留空，因為拖鞋遮住腳。
- 共同画布 700；整段 scale=1.75，與 v1 的 N500／scale1.25 同為 1 source px→1.664 stage px。畫布變大來自保留微弱離散像素，不是把人物縮小或每格自動 fit。

重跑 `python -B animation/charging-cozy-v2/measure_review.py --check`。來源量測見 [`charging-cozy-v2-qc.json`](../production-20261007-completion/charging-cozy-v2-qc.json)，選版理由見 [`charging-selection.json`](../production-20261007-completion/charging-selection.json)。

[`實播12格`](../../output/playwright/20261007-completion/charging-cozy-20261007-live-1x-frames.png)、[`v1/v2同倍率對照`](../../output/playwright/20261007-completion/charging-v1-v2-fixed-scale.png)、[`原圖黑白底`](../../output/playwright/20261007-completion/charging-source-alpha-black-white.png)；整體驗證見 [`runtime-review.json`](../production-20261007-completion/runtime-review.json)。
