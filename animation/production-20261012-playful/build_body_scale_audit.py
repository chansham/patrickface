"""Source-pinned playful audit with descriptive shape differences, not shape targets."""
from pathlib import Path
import argparse,hashlib,importlib.util,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('playful_completion_adapter',ROOT/'animation/production-20261007-completion/build_body_scale_audit.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
def digest(raw):return hashlib.sha256(raw).hexdigest()
def make_report():
    configs=[]
    for path in sorted((HERE/'measurements').glob('*.json')):
        raw=path.read_bytes();config=json.loads(raw)
        if config.get('candidateIncluded',True):configs.append((config,{'path':path.relative_to(ROOT).as_posix(),'sha256':digest(raw)}))
    if not configs:raise ValueError('no reviewed playful sources; do not create an empty success report')
    base.DIRECTORY=HERE
    base.SPECS=tuple((c['clipID'],c['source']['path'],c['source']['sha256'],f'{c["asset"]}-body-qc.json','playful') for c,_ in configs)
    report=base.make_report()
    manifest_raw=(HERE/'manifest.json').read_bytes();manifest=json.loads(manifest_raw)
    report['sourceReports'].append({'path':(HERE/'manifest.json').relative_to(ROOT).as_posix(),'sha256':digest(manifest_raw)})
    summaries=[]
    for clip,(config,config_ref) in zip(report['clips'],configs):
        qc=json.loads((HERE/f'{config["asset"]}-body-qc.json').read_text(encoding='utf-8'))
        if qc['reviewConfiguration']!=config_ref:raise ValueError('review configuration/QC drift')
        report['sourceReports'].append(config_ref)
        entries=[s for s in manifest['sources'] if s['id']==clip['id']]
        if len(entries)!=1 or entries[0]['source']!=clip['atlas'] or entries[0]['sha256']!=clip['sourceSha256']:raise ValueError('batch manifest/source identity drift')
        calibration=entries[0].get('calibration')
        if calibration:
            if abs(calibration['fixedFactor']-clip['sourcePixelToStagePixel'])>1e-9 or abs(calibration['catalogScale']-clip['catalogScale'])>1e-9:raise ValueError('calibration/render scale drift')
            first=clip['frames'][0]['source'][calibration['metric']]
            if first is None or abs(first-calibration['sourcePixels'])>1e-9:raise ValueError('display metric is not independently measured')
            clip['renderCalibration']=calibration
        clip['firstLast']=qc['firstLast'];clip['wholeClipSpread']=qc['wholeClipSpread']
        clip['flags']=[{'code':f'visual-review-{i+1}','severity':finding.get('severity','warning'),'message':finding['message'],
            **({'frameIndices':[f-1 for f in finding['sourceFrames']]} if finding.get('sourceFrames') else {})} for i,finding in enumerate(config['visualFindings'])]
        clip['referenceInterpretation']={'wholeReferenceImageApproved':False,'sourceArtApproved':False,
            'note':config.get('referenceInterpretation','參考圖的造型、比例、氛圍各自評估；喜歡其中一部分不表示整張參考圖或這份生成稿已批准。')}
        index=config.get('neutralComparisonSourceFrame')
        if index is None:
            summaries.append({'clipID':clip['id'],'eyeFootToFaceRatio':None,'unavailableReason':config.get('neutralComparisonUnavailableReason','没有已確認的中立站姿真臉及真腳，跨造型比例不填數字。')})
        else:
            row=clip['frames'][index-1]['source']
            if row['faceWidth'] is None or row['eyeToFoot'] is None:raise ValueError('chosen neutral frame has no reviewed face/foot metric')
            summaries.append({'clipID':clip['id'],'sourceFrame':index-1,'eyeFootToFaceRatio':row['eyeToFoot']/row['faceWidth'],
                'basis':config['neutralComparisonBasis'],'descriptiveOnly':True,'commonShapeTarget':False})
        if calibration and calibration.get('shortfallPercent',0)>1:
            clip['flags'].append({'code':'display-target-limited','severity':'warning',
                'message':f'整段保留一個倍率後，顯示尺規{calibration["metric"]}比此套目標小{calibration["shortfallPercent"]:.2f}%；不能聲稱已同大。這是畫面顯示差異，不是要求改成共同短胖身形。'})
    report.update(generatedAt='2026-10-12',method='source-pinned-playful-body-QC-adapter-v1',outfitCount=sum(c.get('newOutfit',True) for c,_ in configs),
        newSourceFrames=report['totals']['sourceFrames'],anatomicalProxySummary=summaries,
        referenceInterpretation={'wholeReferenceImageApproval':False,'uniformShortRoundShapeRequired':False},
        limitations=['逐來源全部格實看真眼白下緣、可見臉側及真裸腳；帽、鞋、抱枕與服裝不代替人體。',
        '閉眼、遮擋、側轉或不可靠的腳基線保持null；不沿用其他圖或鄰格數字。',
        '同套內核查camera與體積穩定，但低頭、擠壓抱枕、屈身和表情變化不直接當作縮放錯誤。',
        '跨造型比例只描述，不强制共同短胖輪廓；參考圖的一個受喜歡部分不等於整圖美術批准。',
        '每段只讀一個目錄倍率，沒有逐格fit或改PNG；約2source px測點不確定度。',
        '量尺與來源完整不表示動作接觸、眼睛颜色、表情或流暢度已合格。'])
    report['sourceReports']=list({r['path']:r for r in report['sourceReports']}.values())
    return report
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    report=make_report();payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';out=HERE/'body-scale-audit.json'
    if args.check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('playful body audit stale')
    else:out.write_text(payload,encoding='utf-8')
    print(json.dumps({'totals':report['totals'],'shapeProxies':report['anatomicalProxySummary']},ensure_ascii=False))
if __name__=='__main__':main()
