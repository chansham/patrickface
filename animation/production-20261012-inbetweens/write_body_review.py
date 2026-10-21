"""Write a concise, reproducible account of new-source measurement and limits."""
from pathlib import Path
import argparse,json
HERE=Path(__file__).resolve().parent

def render():
    report=json.loads((HERE/'body-scale-audit.json').read_text(encoding='utf-8'))
    totals=report['totals'];metrics=('faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx')
    lines=['# 2026-10-12 抱枕與道服補姿勢稿人體覆核','',
        f'兩份新 PNG 重新覆核 {totals["sourceFrames"]} 格；{totals["measuredSourceFrames"]} 格至少有一項可量，臉寬 7、眼距 17、眼足距 17 格。其餘保留未知，全部美術尚未批准。',
        '', '這是兩套已有服裝的重畫，共 22 個新來源格身份；與舊 8＋8 格相比，淨增 6 個播放位置。不是 22 種新動作，也不是兩套新服裝。各來源一個固定倍率，不逐格 fit。',
        '', '所有格號均從 1 起算；尺規約有 2 個來源像素的取點不確定度。眼足距只是當下姿勢代理，低頭鞠躬造成的縮短不直接判為身體縮放。',
        '', '|來源|可量臉／眼／眼足|首末差 %：臉／眼／眼足|全段差 %：臉／眼／眼足|',
        '|---|---|---|---|']
    rows=[]
    for clip in report['clips']:
        asset=clip['atlas'].split('/')[1]
        qc=json.loads((HERE/f'{asset}-body-qc.json').read_text(encoding='utf-8'))
        rows.append((asset,clip,qc))
        counts='／'.join(str(sum(f[k] is not None for f in qc['frames'])) for k in metrics)
        delta='／'.join(f'{qc["firstLast"][k]["changePercent"]:+.2f}' for k in metrics)
        spread='／'.join(f'{qc["wholeClipSpread"][k]:.2f}' for k in metrics)
        lines.append(f'|{clip["title"]}|{counts}|{delta}|{spread}|')
    lines+=['', '抱枕第 10 格斜眼線的可見臉截線較寬，不能把全段 9.68% 直接稱作忽大忽小；中立 1／11／12 的臉寬最大／最小差 2.23%。道服中段眼足距差 37.5% 與真實鞠躬投影相符，禁止逐格放大補回同高度。',
        '', '|來源|新稿首格眼足／臉比|舊稿首格比|新／舊首格差 %|新／舊末格差 %|',
        '|---|---:|---:|---:|---:|']
    for asset,clip,qc in rows:
        first,last=clip['previousSourceComparison']['endpoints']
        lines.append(f'|{clip["title"]}|{first["newEyeFootToFaceRatio"]:.3f}|{first["previousEyeFootToFaceRatio"]:.3f}|{first["changePercent"]:+.2f}|{last["changePercent"]:+.2f}|')
    lines+=['','這些比例不受單一等比縮放影響，說明新稿不是只插格且原身形像素完全不變；不同造型没有共同短胖目標。舊稿只作對照，未複用其座標或數字。','']
    for asset,clip,qc in rows:
        lines.extend([f'## {clip["title"]}',''])
        cal=clip['renderCalibration']
        lines.append(f'來源→舞台固定倍率 {cal["fixedFactor"]:.10f}；首臉 {cal["actualStagePixels"]:.2f} 舞台像素。最終仍以真頁四版式與正常速度審閱，人體紀錄完整不等於呈現或美術批准。')
        lines.append('')
        for finding in qc['visualFindings']:
            frames='、'.join(str(n) for n in finding.get('sourceFrames',[]))
            lines.append(f'- 來源 {frames}：{finding["message"]}')
        lines.append('')
        for frame in qc['frames']:
            missing=[name for key,name in zip(metrics,('臉寬','眼距','眼足距')) if frame[key] is None]
            if not missing:continue
            reasons=list(dict.fromkeys(frame[k] for k in ('eyeUnavailableReason','faceWidthUnavailableReason','footUnavailableReason') if frame.get(k)))
            lines.append(f'- 來源 {frame["sourceFrame"]}，{"／".join(missing)}未知：'+ ' '.join(reasons))
        prefix=f'../../../output/body-landmarks-20261012-inbetweens/{asset}'
        lines.extend(['',f'[臉／眼尺線]({prefix}-face-calipers.png) · [真裸腳尺線]({prefix}-feet-calipers.png) · [完整來源尺線]({prefix}-full-calipers.png) · [來源 QC](../{asset}-body-qc.json)',''])
    lines.extend(['[總量尺資料](../body-scale-audit.json) 綁定新舊 PNG、regions、量測設定、QC 及目錄快照。來源、輪廓、量尺與 audit 的 `--check` 均可重跑。',''])
    return '\n'.join(lines)

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    text=render();target=HERE/'body-review/README.md'
    if args.check:
        if target.read_text(encoding='utf-8')!=text:raise ValueError('body review stale')
    else:target.parent.mkdir(exist_ok=True);target.write_text(text,encoding='utf-8')
    print('body review PASS')
if __name__=='__main__':main()
