"""Write the human-readable anatomy review from the final pinned audit."""
from pathlib import Path
import argparse,json
HERE=Path(__file__).resolve().parent
NAMES={'boxing':'拳擊','tracksuit':'外套','basketball':'籃球','cycling':'騎行','coach':'教練','martial':'道服','stretch':'伸展','kettlebell':'壺鈴'}
METRICS=('faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx')
def pretty(value,signed=False):return '未知' if value is None else f'{value:+.2f}' if signed else f'{value:.2f}'
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    audit=json.loads((HERE/'body-scale-audit.json').read_text(encoding='utf-8'))
    data=[]
    for clip in audit['clips']:
        asset=clip['atlas'].split('/')[1]
        config=json.loads((HERE/'measurements'/f'{asset}.json').read_text(encoding='utf-8'))
        qc=json.loads((HERE/f'{asset}-body-qc.json').read_text(encoding='utf-8'))
        data.append((NAMES[asset.split('-')[1]],asset,clip,config,qc))
    totals=audit['totals'];counts=totals['measuredSourceFramesByMetric']
    lines=['# 2026-10-12 健身素材：人體尺規與尚未完成的部分','',
      f'本報告覆核 {len(data)} 套、{totals["sourceFrames"]} 張來源原畫。{totals["measuredSourceFrames"]} 格至少有一項可量尺規；臉寬 {counts["faceWidth"]}、眼下緣距 {counts["eyeSeparation"]}、眼足距 {counts["eyeToFoot"]} 格可量。每格都有覆核記錄，並不代表每格都可量，也不代表美術通過。',
      '', '所有來源臉部與真腳放大證據已逐格實看。原 PNG、輪廓表及人工選定的搜尋窗均綁定 SHA；不把衣服、帽子、拳套、壺鈴或矩形格尺寸当成人體。以下格號為 **1 起算的來源閱讀順序**，不是播放重排序號。','',
      '## 可量覆蓋與明確未知','',
      '|穿搭|來源格數|臉／眼／眼足可量格数|未知原因|','|---|---:|---|---|']
    unknowns={
      'boxing':'3–7 拳套擋住左臉邊界，臉寬未知；眼下緣與真腳可見。',
      'tracksuit':'6 完全閉眼，三項未知。',
      'basketball':'沒有全遮擋；2、7 低頭／半睜眼會影響投影，不能當固定骨架高度。',
      'cycling':'全部 8 格的頭盔帶擋住左臉邊界，臉寬全未知；5 墨鏡遮雙眼，三項未知。v2 的 4、6 鏡片已高於眼白，重新實看後可量眼下緣。',
      'coach':'6、7 側轉及鼓頰吹哨，不當中立正臉，臉寬未知；眼／真腳仍可見。',
      'martial':'2–6 鞠躬投影不當正面臉寬；5 完全閉眼三項未知。其餘鞠躬眼足值只是姿勢投影。',
      'stretch':'8 紫色閉眼，三項未知；7 高舉手臂沒有被計入臉截線。',
      'kettlebell':'8 格眼下緣／臉側／真腳可見；2、3、4 的上眼白粉紫帶仍是待修美術問題。'}
    for name,asset,clip,config,qc in data:
        count='／'.join(str(sum(r[k] is not None for r in qc['frames'])) for k in METRICS)
        lines.append(f'|{name}|{len(qc["frames"])}|{count}|{unknowns[asset.split("-")[1]]}|')
    lines+=['','## 首末與全段差異','',
      '百分比順序都是 **臉／眼／眼足**。首末為末格相對首格；全段差為可量格的最大值 ÷ 最小值 − 1。未知沒有以鄰格補值。測點約有 2 個來源像素的不確定度，表情／低頭會改變這些代理尺規。','',
      '|穿搭|首末變化 %|全段可量範圍差 %|','|---|---|---|']
    for name,asset,clip,config,qc in data:
        changes='／'.join(pretty(qc['firstLast'][k]['changePercent'],True) for k in METRICS)
        spreads='／'.join(pretty(qc['wholeClipSpread'][k]) for k in METRICS)
        lines.append(f'|{name}|{changes}|{spreads}|')
    lines+=['','道服眼足全段差約 66.67% 來自真實鞠躬投影，不是把人物畫小；不可逐格放大來抹去彎腰。籃球眼足差約 12.21% 及教練眼距約 9.99% 仍需對照低頭、側轉與表情原畫看，不以數字自動批准。',
      '', '## 跨服裝比例與畫面大小','',
      '站姿比例比較選來源 1，基準是原站姿雨衣的眼足／臉截面比 2.418。衣服遮住軀幹，因此這不是完整骨架測量。比值不受整段等比縮放影響；臉寬對齊並不代表全身相同。','',
      '|穿搭|眼足／臉截面|相對原站姿雨衣 %|','|---|---:|---:|']
    comparison={c['clipID']:c for c in audit['standingReferenceComparisons']}
    for name,asset,clip,config,qc in data:
        comp=comparison.get(clip['id'])
        lines.append(f'|{name}|{comp["eyeFootToFaceRatio"]:.3f}|{comp["changePercent"]:+.2f}|' if comp else f'|{name}|未知，頭盔帶遮臉|未知|')
    lines+=['','顯示尺寸以主睡衣首格臉寬 182.721 舞台像素為目標；騎行臉不可量，改用眼距 64.311。每套全段只用一個倍率，且受全部姿勢、四種版式的留白上限限制。下表的不足必須保留，不能稱為全部已同大。','',
      '|穿搭|對齊基準|實際舞台像素|距目標小 %|','|---|---|---:|---:|']
    for name,asset,clip,config,qc in data:
        cal=clip['renderCalibration']
        lines.append(f'|{name}|'+('眼距' if cal['metric']=='eyeSeparation' else '臉寬')+f'|{cal["actualStagePixels"]:.2f}|{max(0,cal["shortfallPercent"]):.2f}|')
    lines+=['','## 仍需修正的原畫與動作','',
      '- 伸展第 8 格紫色閉眼，以及壺鈴第 2、3、4 格上眼白粉紫帶仍未修好。生成修圖没有輸出，沒有當成成功版本。',
      '- 拳擊出拳／收回、外套拉開／呼氣、教練提哨／收哨、道服起身、伸展收手、壺鈴放下仍有姿勢跨度，需要補中間原畫；調速度不能補出缺少的姿勢。',
      '- 籃球目前是抱球上提／放下；騎行目前是穿騎行服調墨鏡。它們不等於運球、投籃或實際踩車。',
      '- 多套首末表情、手臂或服裝狀態不同，應按一次性動作銜接待機，不能當作已完成無縫循環。',
      '- 壺鈴第 1、8 格紫壺底低於真腳。輪廓完整保留，放置基準使用兩個真裸腳強透明度支撐点；眼足測量使用裸腳填色底線。兩種基準分開，不用道具最低點冒充腳。',
      '', '## 可核查證據','',
      '[總量尺資料](../body-scale-audit.json) 同時釘住来源、配置、輪廓、候選與校準記錄。下列每套連結包含全部來源格，沒有只挑最好的首格。','',
      '|穿搭|臉／眼放大尺線|真腳放大尺線|逐格資料|','|---|---|---|---|']
    for name,asset,clip,config,qc in data:
        prefix=f'../../../output/body-landmarks-20261012-fitness/{asset}'
        lines.append(f'|{name}|[查看]({prefix}-face-calipers.png)|[查看]({prefix}-feet-calipers.png)|[QC](../{asset}-body-qc.json)|')
    lines+=['','核對入口：`measure_source.py <measurements/...json> --check`、`build_body_scale_audit.py --check`、`write_body_review.py --check`。完整來源和明確未知驗證通過，只能證明報告可追溯；仍需實際動畫及美術審閱。','']
    target=HERE/'body-review/README.md';text='\n'.join(lines)
    if args.check:
        if target.read_text(encoding='utf-8')!=text:raise ValueError('body review README stale')
    else:target.parent.mkdir(exist_ok=True);target.write_text(text,encoding='utf-8')
    print('body-review README matches current audit' if args.check else 'body-review README written')
if __name__=='__main__':main()
