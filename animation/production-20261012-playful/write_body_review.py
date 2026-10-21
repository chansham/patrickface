"""Describe source measurements without turning a reference into full art approval."""
from pathlib import Path
import argparse,json
HERE=Path(__file__).resolve().parent
KEYS=('faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx')
def fmt(x,signed=False):return '未知' if x is None else f'{x:+.2f}' if signed else f'{x:.2f}'
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    report=json.loads((HERE/'body-scale-audit.json').read_text(encoding='utf-8'));t=report['totals']
    data=[]
    for clip in report['clips']:
        asset=clip['atlas'].split('/')[1]
        qc=json.loads((HERE/f'{asset}-body-qc.json').read_text(encoding='utf-8'))
        config=json.loads((HERE/'measurements'/f'{asset}.json').read_text(encoding='utf-8'))
        data.append((asset,clip,qc,config))
    lines=['# 2026-10-12 新造型人體覆核','',
      f'本批獨立覆核 {t["uniqueSources"]} 份來源、{t["sourceFrames"]} 格原畫。{t["measuredSourceFrames"]} 格至少一項可量；臉寬 {t["measuredSourceFramesByMetric"]["faceWidth"]}、眼距 {t["measuredSourceFramesByMetric"]["eyeSeparation"]}、眼足距 {t["measuredSourceFramesByMetric"]["eyeToFoot"]} 格。這不是美術完成數。',
      '', '參考圖可能只提供受喜歡的服裝、比例或氛圍，不能當作整張參考圖都已批准。同一套內檢查畫面位置、體積及動作投影；不同造型的身形差異只描述，不強制改成共同短胖比例。所有格號均為 **1 起算來源閱讀順序**。',
      '', '## 同套內的量尺差異','',
      '以下三個數字順序都是臉／眼／眼足。首末為末格相對首格；全段為可量格最大 ÷ 最小 − 1。未知不借鄰格填值；約有 2 個來源像素的取點不確定度。低頭、側轉、擠壓道具與表情改變須看原畫，不能直接判成畫面縮放錯誤。','',
      '|造型|來源格數|可量格數|首末差 %|全段差 %|','|---|---:|---|---|---|']
    for asset,clip,qc,config in data:
        counts='／'.join(str(sum(r[k] is not None for r in qc['frames'])) for k in KEYS)
        delta='／'.join(fmt(qc['firstLast'][k]['changePercent'],True) for k in KEYS)
        spread='／'.join(fmt(qc['wholeClipSpread'][k]) for k in KEYS)
        lines.append(f'|{clip["title"]}|{len(qc["frames"])}|{counts}|{delta}|{spread}|')
    lines+=['','## 尺規未知與可見姿勢的限制','']
    for asset,clip,qc,config in data:
        lines.extend([f'### {clip["title"]}',''])
        notes=[]
        for row in qc['frames']:
            missing=[name for key,name in zip(KEYS,('臉','眼','眼足')) if row[key] is None]
            reasons=[]
            for key in ('eyeUnavailableReason','faceWidthUnavailableReason','footUnavailableReason','measurementCaveat'):
                if row.get(key) and row[key] not in reasons:reasons.append(row[key])
            if reasons:notes.append(f'- 來源 {row["sourceFrame"]}：'+('／'.join(missing)+'未知。' if missing else '尺規可見，但有姿勢限制。')+' '.join(reasons))
        lines.extend(notes or ['全部來源格的三項尺規可見；可量不代表接觸、顏色或動作已合格。'])
        lines.append('')
    lines+=['## 跨造型的描述與顯示大小','',
      '只有指定中立姿勢的真臉與真腳都可量時，才列眼足／臉比。此比值不受單一等比缩放影响，也沒有共同合格目標。抱枕、帽、鞋及服裝不作人體代理。','',
      '|造型|中立格眼足／臉比|解釋|','|---|---:|---|']
    proxies={p['clipID']:p for p in report['anatomicalProxySummary']}
    for asset,clip,qc,config in data:
        p=proxies[clip['id']]
        lines.append(f'|{clip["title"]}|{fmt(p["eyeFootToFaceRatio"])}|{p.get("basis") or p["unavailableReason"]}|')
    lines+=['','顯示目錄使用每套單一固定倍率；下列數字只說明螢幕大小，不是將不同造型身形改成一致的要求。','',
      '|造型|對齊尺度|舞台像素|比本套顯示目標小 %|','|---|---|---:|---:|']
    for asset,clip,qc,config in data:
        cal=clip.get('renderCalibration')
        label={'faceWidth':'臉寬','eyeSeparation':'眼距'}.get(cal['metric'],cal['metric']) if cal else None
        lines.append(f'|{clip["title"]}|{label}|{cal["actualStagePixels"]:.2f}|{max(0,cal["shortfallPercent"]):.2f}|' if cal else f'|{clip["title"]}|未另設顯示目標|未知|未知|')
    lines+=['','## 表情、接觸與未完成原畫','']
    for asset,clip,qc,config in data:
        lines.extend([f'### {clip["title"]}',''])
        for finding in config['visualFindings']:
            frames='、'.join(str(x) for x in finding.get('sourceFrames',[]))
            lines.append('- '+(f'來源 {frames}：' if frames else '')+finding['message'])
        lines.append('')
    lines+=['## 全部來源格的尺線證據','',
      '|造型|臉／眼|真腳|來源綁定資料|','|---|---|---|---|']
    for asset,clip,qc,config in data:
        prefix=f'../../../output/body-landmarks-20261012-playful/{asset}'
        lines.append(f'|{clip["title"]}|[尺線]({prefix}-face-calipers.png)|[尺線]({prefix}-feet-calipers.png)|[QC](../{asset}-body-qc.json)|')
    lines+=['','[總量尺資料](../body-scale-audit.json) 釘住 PNG、輪廓、逐格搜尋窗與目錄來源。三項工具的 `--check` 可重算資料；技術完整不表示實際動畫或美術批准。','']
    target=HERE/'body-review/README.md';payload='\n'.join(lines)
    if args.check:
        if target.read_text(encoding='utf-8')!=payload:raise ValueError('playful anatomy README stale')
    else:target.parent.mkdir(exist_ok=True);target.write_text(payload,encoding='utf-8')
    print('playful anatomy README matches' if args.check else 'playful anatomy README written')
if __name__=='__main__':main()
