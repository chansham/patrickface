# 2026-10-12 健身素材：人體尺規與尚未完成的部分

本報告覆核 8 套、68 張來源原畫。64 格至少有一項可量尺規；臉寬 46、眼下緣距 64、眼足距 64 格可量。每格都有覆核記錄，並不代表每格都可量，也不代表美術通過。

所有來源臉部與真腳放大證據已逐格實看。原 PNG、輪廓表及人工選定的搜尋窗均綁定 SHA；不把衣服、帽子、拳套、壺鈴或矩形格尺寸当成人體。以下格號為 **1 起算的來源閱讀順序**，不是播放重排序號。

## 可量覆蓋與明確未知

|穿搭|來源格數|臉／眼／眼足可量格数|未知原因|
|---|---:|---|---|
|籃球|8|8／8／8|沒有全遮擋；2、7 低頭／半睜眼會影響投影，不能當固定骨架高度。|
|拳擊|8|3／8／8|3–7 拳套擋住左臉邊界，臉寬未知；眼下緣與真腳可見。|
|教練|8|6／8／8|6、7 側轉及鼓頰吹哨，不當中立正臉，臉寬未知；眼／真腳仍可見。|
|騎行|8|0／7／7|全部 8 格的頭盔帶擋住左臉邊界，臉寬全未知；5 墨鏡遮雙眼，三項未知。v2 的 4、6 鏡片已高於眼白，重新實看後可量眼下緣。|
|壺鈴|8|8／8／8|8 格眼下緣／臉側／真腳可見；2、3、4 的上眼白粉紫帶仍是待修美術問題。|
|道服|8|3／7／7|2–6 鞠躬投影不當正面臉寬；5 完全閉眼三項未知。其餘鞠躬眼足值只是姿勢投影。|
|伸展|12|11／11／11|8 紫色閉眼，三項未知；7 高舉手臂沒有被計入臉截線。|
|外套|8|7／7／7|6 完全閉眼，三項未知。|

## 首末與全段差異

百分比順序都是 **臉／眼／眼足**。首末為末格相對首格；全段差為可量格的最大值 ÷ 最小值 − 1。未知沒有以鄰格補值。測點約有 2 個來源像素的不確定度，表情／低頭會改變這些代理尺規。

|穿搭|首末變化 %|全段可量範圍差 %|
|---|---|---|
|籃球|-1.81／-1.61／+4.46|9.46／6.67／12.21|
|拳擊|-2.38／-3.07／-0.89|2.43／6.25／1.44|
|教練|-4.47／+0.05／+2.50|7.80／9.99／5.22|
|騎行|未知／-1.44／-0.78|未知／2.75／4.33|
|壺鈴|-1.62／+0.00／+0.44|3.29／6.01／3.10|
|道服|+4.96／+1.56／-4.49|6.95／3.17／66.67|
|伸展|+2.51／-2.00／-1.32|3.81／4.17／6.78|
|外套|-1.54／-1.35／-1.14|2.37／2.82／1.54|

道服眼足全段差約 66.67% 來自真實鞠躬投影，不是把人物畫小；不可逐格放大來抹去彎腰。籃球眼足差約 12.21% 及教練眼距約 9.99% 仍需對照低頭、側轉與表情原畫看，不以數字自動批准。

## 跨服裝比例與畫面大小

站姿比例比較選來源 1，基準是原站姿雨衣的眼足／臉截面比 2.418。衣服遮住軀幹，因此這不是完整骨架測量。比值不受整段等比縮放影響；臉寬對齊並不代表全身相同。

|穿搭|眼足／臉截面|相對原站姿雨衣 %|
|---|---:|---:|
|籃球|2.023|-16.34|
|拳擊|2.432|+0.59|
|教練|2.327|-3.77|
|騎行|未知，頭盔帶遮臉|未知|
|壺鈴|1.826|-24.46|
|道服|2.432|+0.58|
|伸展|2.370|-1.98|
|外套|2.035|-15.84|

顯示尺寸以主睡衣首格臉寬 182.721 舞台像素為目標；騎行臉不可量，改用眼距 64.311。每套全段只用一個倍率，且受全部姿勢、四種版式的留白上限限制。下表的不足必須保留，不能稱為全部已同大。

|穿搭|對齊基準|實際舞台像素|距目標小 %|
|---|---|---:|---:|
|籃球|臉寬|182.72|0.00|
|拳擊|臉寬|170.74|6.56|
|教練|臉寬|178.24|2.45|
|騎行|眼距|51.56|19.82|
|壺鈴|臉寬|182.72|0.00|
|道服|臉寬|172.14|5.79|
|伸展|臉寬|159.39|12.77|
|外套|臉寬|182.72|0.00|

## 仍需修正的原畫與動作

- 伸展第 8 格紫色閉眼，以及壺鈴第 2、3、4 格上眼白粉紫帶仍未修好。生成修圖没有輸出，沒有當成成功版本。
- 拳擊出拳／收回、外套拉開／呼氣、教練提哨／收哨、道服起身、伸展收手、壺鈴放下仍有姿勢跨度，需要補中間原畫；調速度不能補出缺少的姿勢。
- 籃球目前是抱球上提／放下；騎行目前是穿騎行服調墨鏡。它們不等於運球、投籃或實際踩車。
- 多套首末表情、手臂或服裝狀態不同，應按一次性動作銜接待機，不能當作已完成無縫循環。
- 壺鈴第 1、8 格紫壺底低於真腳。輪廓完整保留，放置基準使用兩個真裸腳強透明度支撐点；眼足測量使用裸腳填色底線。兩種基準分開，不用道具最低點冒充腳。

## 可核查證據

[總量尺資料](../body-scale-audit.json) 同時釘住来源、配置、輪廓、候選與校準記錄。下列每套連結包含全部來源格，沒有只挑最好的首格。

|穿搭|臉／眼放大尺線|真腳放大尺線|逐格資料|
|---|---|---|---|
|籃球|[查看](../../../output/body-landmarks-20261012-fitness/fitness-basketball-v1-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-basketball-v1-feet-calipers.png)|[QC](../fitness-basketball-v1-body-qc.json)|
|拳擊|[查看](../../../output/body-landmarks-20261012-fitness/fitness-boxing-v1-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-boxing-v1-feet-calipers.png)|[QC](../fitness-boxing-v1-body-qc.json)|
|教練|[查看](../../../output/body-landmarks-20261012-fitness/fitness-coach-v2-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-coach-v2-feet-calipers.png)|[QC](../fitness-coach-v2-body-qc.json)|
|騎行|[查看](../../../output/body-landmarks-20261012-fitness/fitness-cycling-v2-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-cycling-v2-feet-calipers.png)|[QC](../fitness-cycling-v2-body-qc.json)|
|壺鈴|[查看](../../../output/body-landmarks-20261012-fitness/fitness-kettlebell-v2-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-kettlebell-v2-feet-calipers.png)|[QC](../fitness-kettlebell-v2-body-qc.json)|
|道服|[查看](../../../output/body-landmarks-20261012-fitness/fitness-martial-v1-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-martial-v1-feet-calipers.png)|[QC](../fitness-martial-v1-body-qc.json)|
|伸展|[查看](../../../output/body-landmarks-20261012-fitness/fitness-stretch-v1-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-stretch-v1-feet-calipers.png)|[QC](../fitness-stretch-v1-body-qc.json)|
|外套|[查看](../../../output/body-landmarks-20261012-fitness/fitness-tracksuit-v2-face-calipers.png)|[查看](../../../output/body-landmarks-20261012-fitness/fitness-tracksuit-v2-feet-calipers.png)|[QC](../fitness-tracksuit-v2-body-qc.json)|

核對入口：`measure_source.py <measurements/...json> --check`、`build_body_scale_audit.py --check`、`write_body_review.py --check`。完整來源和明確未知驗證通過，只能證明報告可追溯；仍需實際動畫及美術審閱。
