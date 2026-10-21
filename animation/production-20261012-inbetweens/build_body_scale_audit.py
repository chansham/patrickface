"""Fresh source measurements for two redrawn clips; prior source is comparison only."""
from pathlib import Path
import argparse,hashlib,importlib.util,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('inbetween_playful_adapter',ROOT/'animation/production-20261012-playful/build_body_scale_audit.py')
engine=importlib.util.module_from_spec(spec);spec.loader.exec_module(engine)
engine.HERE=HERE

def read(relative):
    raw=(ROOT/relative).read_bytes()
    return json.loads(raw),{'path':relative,'sha256':hashlib.sha256(raw).hexdigest()}

def make_report():
    report=engine.make_report()
    catalog,_=read('animation/candidates.json');clips={r['id']:r for r in catalog['clips']}
    manifest,_=read((HERE/'manifest.json').relative_to(ROOT).as_posix());specs={r['id']:r for r in manifest['sources']}
    comparisons=[]
    for entry in report['clips']:
        source=specs[entry['id']];previous=clips[source['comparisonClipId']]
        old_qc,old_ref=read(previous['reviewProvenance']['bodyQC'])
        old_regions,region_ref=read(previous['frameRegions']['path'])
        engine.base.validate_identity(previous,previous['atlas'],previous['sha256'],hashlib.sha256((ROOT/previous['atlas']).read_bytes()).hexdigest(),old_regions,region_ref['sha256'],old_qc)
        old_config,config_ref=read(old_qc['reviewConfiguration']['path'])
        if old_qc['reviewConfiguration']!=config_ref or old_config['clipID']!=previous['id']:raise ValueError('previous-source QC/config identity drift')
        new_qc,new_ref=read(entry['measurementProvenance']['path'])
        endpoints=[]
        for index,label in ((0,'neutral-first'),(-1,'neutral-last')):
            old,new=old_qc['frames'][index],new_qc['frames'][index]
            for row in (old,new):
                if row['faceWidthPx'] is None or row['eyeLineToFootPx'] is None:raise ValueError('comparison needs reviewed neutral face and foot')
            old_ratio=old['eyeLineToFootPx']/old['faceWidthPx'];new_ratio=new['eyeLineToFootPx']/new['faceWidthPx']
            endpoints.append({'label':label,'previousSourceFrame':old['sourceFrame'],'newSourceFrame':new['sourceFrame'],
                'previousEyeFootToFaceRatio':old_ratio,'newEyeFootToFaceRatio':new_ratio,'changePercent':(new_ratio/old_ratio-1)*100,
                'notWholeBodyEquality':True,'measurementUncertaintySourcePixels':2})
        entry['previousSourceComparison']={'previousClipID':previous['id'],'previousSourceSha256':previous['sha256'],
            'previousRegionsSha256':previous['frameRegions']['sha256'],'previousBodyQC':old_ref,
            'newBodyQC':new_ref,'endpoints':endpoints,
            'meaning':'Separate fresh measurements; source pixel sizes are not directly comparable across different atlas resolutions. Neutral eye-to-foot/face ratios describe changed drawing proportions, not an imposed target.'}
        if abs(endpoints[0]['changePercent'])>5:
            entry['flags'].append({'code':'redrawn-neutral-proportion-difference','severity':'warning',
                'message':f'新稿首格眼足／臉比{endpoints[0]["newEyeFootToFaceRatio"]:.3f}，舊稿{endpoints[0]["previousEyeFootToFaceRatio"]:.3f}，差{endpoints[0]["changePercent"]:+.2f}%；重畫有比例差異，不能稱為只加中間格且身形完全不變。這是描述性代理，不要求不同造型同體型。'})
        comparisons.append({'clipID':entry['id'],**entry['previousSourceComparison']})
        report['sourceReports'].extend([old_ref,config_ref])
    report.update(method='fresh-source-inbetween-body-review-v1',outfitCount=0,
                  newlyDrawnSourceFrameIdentities=report['totals']['sourceFrames'],
                  netAdditionalPlaybackPositionsComparedWithOriginals=sum(c['playbackFrameCount']-clips[specs[c['id']]['comparisonClipId']]['frameCount'] for c in report['clips']),
                  previousSourceComparisons=comparisons)
    report['limitations'].extend([
        '本批兩個舊服裝的重畫來源共22格，按新PNG身份算新來源；相對舊8+8格只是增加6個播放位置，不能稱新增22種動作或兩套新服裝。',
        '舊稿只供中立首末姿勢對照，不向新稿複用ROI、尺線或數字。生成提示要求保持角色不構成實際像素保持證據。',
        '道服7/8姿勢近似、8→9仍較大；抱枕新增下降和轉枕姿勢仍需正常速度與接觸審閱，沒有美術批准。'])
    report['sourceReports']=list({r['path']:r for r in report['sourceReports']}.values())
    return report

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    report=make_report();payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';target=HERE/'body-scale-audit.json'
    if args.check:
        if target.read_text(encoding='utf-8')!=payload:raise ValueError('inbetween body audit stale')
    else:target.write_text(payload,encoding='utf-8')
    print(json.dumps({'totals':report['totals'],'newOutfits':0,'netAdditionalPlaybackPositions':report['netAdditionalPlaybackPositionsComparedWithOriginals'],'endpointComparisons':[{'clipID':r['clipID'],'endpoints':r['endpoints']} for r in report['previousSourceComparisons']]},ensure_ascii=False))
if __name__=='__main__':main()
