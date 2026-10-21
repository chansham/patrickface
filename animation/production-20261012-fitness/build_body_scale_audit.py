"""Adapt this batch's individually reviewed and SHA-pinned sources to the real renderer."""
from pathlib import Path
import argparse,hashlib,importlib.util,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('completion_adapter',ROOT/'animation/production-20261007-completion/build_body_scale_audit.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
def digest(raw):return hashlib.sha256(raw).hexdigest()
def make_report():
    configs=[]
    for path in sorted((HERE/'measurements').glob('*.json')):
        raw=path.read_bytes();config=json.loads(raw)
        if not config.get('candidateIncluded',True):continue
        configs.append((config,{'path':path.relative_to(ROOT).as_posix(),'sha256':digest(raw)}))
    if not configs:raise ValueError('no independently reviewed source configs')
    base.DIRECTORY=HERE
    base.SPECS=tuple((c['clipID'],c['source']['path'],c['source']['sha256'],f'{c["asset"]}-body-qc.json','fitness') for c,_ in configs)
    report=base.make_report()
    manifest_raw=(HERE/'manifest.json').read_bytes();manifest=json.loads(manifest_raw)
    report['sourceReports'].append({'path':(HERE/'manifest.json').relative_to(ROOT).as_posix(),'sha256':digest(manifest_raw)})
    ref_path='animation/production-20261012-raincoat/raincoat-v1-qc.json';ref_raw=(ROOT/ref_path).read_bytes();ref=json.loads(ref_raw)
    if ref['source']['sha256']!='755d73b3e23149a1c82498f9103be1b7a3f80b42214a70890b7d44d08181f42b':raise ValueError('old standing source changed')
    reference_ratio=ref['frames'][0]['eyeLineToFootPx']/ref['frames'][0]['faceWidthPx']
    report['sourceReports'].append({'path':ref_path,'sha256':digest(ref_raw)})
    comparisons=[]
    for clip,(config,config_ref) in zip(report['clips'],configs):
        qc=json.loads((HERE/f'{config["asset"]}-body-qc.json').read_text(encoding='utf-8'))
        if qc['reviewConfiguration']!=config_ref:raise ValueError('review configuration/QC drift')
        report['sourceReports'].append(config_ref)
        entries=[s for s in manifest['sources'] if s['id']==clip['id']]
        if len(entries)!=1 or entries[0]['source']!=clip['atlas'] or entries[0]['sha256']!=clip['sourceSha256']:raise ValueError('final batch manifest/source identity drift')
        calibration=entries[0]['calibration']
        if abs(calibration['fixedFactor']-clip['sourcePixelToStagePixel'])>1e-9 or abs(calibration['catalogScale']-clip['catalogScale'])>1e-9:raise ValueError('calibration/render scale drift')
        metric=calibration['metric'];first_value=clip['frames'][0]['source'][metric]
        if first_value is None or abs(first_value-calibration['sourcePixels'])>1e-9:raise ValueError('calibration metric was not independently measured')
        clip['renderCalibration']=calibration
        clip['firstLast']=qc['firstLast'];clip['wholeClipSpread']=qc['wholeClipSpread']
        clip['flags']=[{'code':f'visual-review-{i+1}','severity':finding.get('severity','warning'),
                       'message':finding['message'],**({'frameIndices':[f-1 for f in finding['sourceFrames']]} if finding.get('sourceFrames') else {})}
                      for i,finding in enumerate(config['visualFindings'])]
        if calibration['shortfallPercent']>1:
            clip['flags'].append({'code':'primary-size-target-limited','severity':'warning',
              'message':f'全段與四種版式安全區封頂後，{metric}實際{calibration["actualStagePixels"]:.2f}，目標{calibration["targetStagePixels"]:.2f}，小{calibration["shortfallPercent"]:.2f}%；保留單一整段倍率，不把未達目標說成等大。'})
        reference_index=config.get('standingComparisonSourceFrame')
        if reference_index is not None:
            row=clip['frames'][reference_index-1]['source']
            if row['faceWidth'] is None or row['eyeToFoot'] is None:raise ValueError('standing comparison frame lacks reviewed anatomy')
            ratio=row['eyeToFoot']/row['faceWidth'];change=(ratio/reference_ratio-1)*100
            comparison={'clipID':clip['id'],'sourceFrame':reference_index-1,'sourceSha256':clip['sourceSha256'],
              'referenceSourceFrame':0,'referenceSourceSha256':ref['source']['sha256'],
              'referenceEyeFootToFaceRatio':reference_ratio,'eyeFootToFaceRatio':ratio,'changePercent':change,
              'basis':config['standingComparisonBasis'],'notCompleteBodyEquality':True}
            comparisons.append(comparison)
            clip['flags'].append({'code':'standing-body-proxy-comparison','severity':'warning' if abs(change)>10 else 'info',
              'message':f'指定站姿格眼足／臉截面比{ratio:.3f}，原站姿雨衣比{reference_ratio:.3f}，差{change:+.2f}%；只比較此姿勢代理，不代表骨架或全身等大。'})
        else:
            clip['flags'].append({'code':'standing-comparison-unavailable','severity':'info','message':config.get('standingComparisonUnavailableReason','姿勢或可見人體基準不同，不作跨服装站立身形比較。')})
    report.update(generatedAt='2026-10-12',method='individually-reviewed-source-pinned-fitness-body-QC-adapter-v1',
      outfitCount=sum(c.get('newOutfit',True) for c,_ in configs),newSourceFrames=report['totals']['sourceFrames'],
      standingReferenceComparisons=comparisons,
      limitations=['只使用逐來源視覺覆核的眼白下緣、可見皮膚截面、真裸腳填色下緣；鞋、拳套、水瓶、帽子不當人体基準。',
       '閉眼、道具擋臉或真腳不可見時保留null；完整記錄未知不等於可量或美術通過。',
       '每段沿用目錄的一個固定倍率；沒有逐格fit或更改PNG。',
       '跨服裝只在明示可比較的站姿格比較眼足／臉截面比例；坐姿、屈膝、踮腳不能混當站立身高。',
       '尺線約2source px的取點不確定度；表情亦會改變眼距和臉截面。動作順序與美術仍需正常速度審核。'])
    report['sourceReports']=list({r['path']:r for r in report['sourceReports']}.values())
    return report
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();report=make_report()
    payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';out=HERE/'body-scale-audit.json'
    if args.check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('fitness body audit stale')
    else:out.write_text(payload,encoding='utf-8')
    print(json.dumps({'totals':report['totals'],'standing':report['standingReferenceComparisons']},ensure_ascii=False))
if __name__=='__main__':main()
