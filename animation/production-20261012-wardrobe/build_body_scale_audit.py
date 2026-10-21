"""Adapt two independently inspected final sources; never edit source art or fill unknowns."""
from pathlib import Path
import argparse,hashlib,importlib.util,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('completion_adapter',ROOT/'animation/production-20261007-completion/build_body_scale_audit.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
base.DIRECTORY=HERE
base.SPECS=(('raincoat-smooth-20261012','animation/raincoat-v3/atlas-generated.png',
             'e3fdb977617c6a73718a6bb12b31d27be1e1a737a5ccba4304c39417d2ff2e74','raincoat-v3-body-qc.json','raincoat'),
            ('sport-towel-first-20261012','animation/sport-towel-v2/atlas-generated.png',
             '01e212bf5c64471fec5f6c836e88e54406803562da0f8e2a0eea4a2e9d1abead','sport-towel-v2-body-qc.json','sport'))
def make_report():
    report=base.make_report();qc=json.loads((HERE/'raincoat-v3-body-qc.json').read_text(encoding='utf-8-sig'))
    catalog=json.loads((ROOT/'animation/candidates.json').read_text(encoding='utf-8-sig'))
    old=next(c for c in catalog['clips'] if c['id']=='raincoat-first-20261012')
    old_regions=json.loads((ROOT/old['frameRegions']['path']).read_text(encoding='utf-8-sig'))
    if hashlib.sha256((ROOT/old['atlas']).read_bytes()).hexdigest()!=old['sha256']:raise ValueError('old standing source changed')
    if hashlib.sha256((ROOT/old['frameRegions']['path']).read_bytes()).hexdigest()!=old['frameRegions']['sha256']:raise ValueError('old standing contour changed')
    ref=qc['originalStandingReference'];old_qc_bytes=(ROOT/ref['path']).read_bytes()
    if hashlib.sha256(old_qc_bytes).hexdigest()!=ref['sha256']:raise ValueError('old standing body comparison changed')
    old_qc=json.loads(old_qc_bytes);old_factor=report['stageConstants']['size']*old['scale']/old_regions['canvas']['width']
    clip=report['clips'][0];new_factor=clip['sourcePixelToStagePixel'];mapping={'faceWidth':'faceWidthPx','eyeSeparation':'eyeLowerRimSeparationPx','eyeToFoot':'eyeLineToFootPx'}
    comparison={}
    for metric,key in mapping.items():
        before=old_qc['frames'][0][key]*old_factor;after=qc['frames'][0][key]*new_factor
        comparison[metric]={'oldSourcePixels':old_qc['frames'][0][key],'newSourcePixels':qc['frames'][0][key],
                           'oldStagePixels':before,'newStagePixels':after,'changePercent':(after/before-1)*100,
                           'oldCSSPixelsAt200Width':before*200/832,'newCSSPixelsAt200Width':after*200/832}
    clip['flags']=[
      {'code':'hand-gaze-transitions-pending','severity':'warning','message':'原3→4抬手回退改用重排減少；原6→7→8仍缺表情／手勢中間稿，12格不代表動畫已平順。','frameIndices':[2,3,5,6,7]},
      {'code':'expression-proxy-variation','severity':'warning','message':'全段臉截面極差3.61%、眼下緣距12.43%、眼足距4.86%；眼距變化受表情影響，不解讀為人物整體縮放。'},
      {'code':'standing-reference-proportion','severity':'warning','message':f'與舊站姿第一格在各自固定倍率下比較：臉截面{comparison["faceWidth"]["changePercent"]:+.2f}%、眼足距{comparison["eyeToFoot"]["changePercent"]:+.2f}%；不宣稱人物全部比例一致。'}]
    sport=report['clips'][1];sport_qc=json.loads((HERE/'sport-towel-v2-body-qc.json').read_text(encoding='utf-8-sig'))
    cross={}
    for metric,key in mapping.items():
        rain_value=clip['frames'][0]['stage'][metric];sport_value=sport['frames'][0]['stage'][metric]
        cross[metric]={'raincoatSourcePixels':qc['frames'][0][key],'sportSourcePixels':sport_qc['frames'][0][key],
          'raincoatStagePixels':rain_value,'sportStagePixels':sport_value,'changePercent':(sport_value/rain_value-1)*100,
          'raincoatCSSPixelsAt200Width':rain_value*200/832,'sportCSSPixelsAt200Width':sport_value*200/832}
    rain_ratio=qc['frames'][0]['eyeLineToFootPx']/qc['frames'][0]['faceWidthPx']
    sport_ratio=sport_qc['frames'][0]['eyeLineToFootPx']/sport_qc['frames'][0]['faceWidthPx']
    sport['flags']=[
      {'code':'eyelid-colour-repaired','severity':'info','message':'來源1/5紫眼皮已重畫成粉色；新8格重新量測，來源5閉眼仍全部未知。','frameIndices':[0,4]},
      {'code':'tall-body-proportion-unresolved','severity':'warning','message':f'第一格眼足距／臉截面比為{sport_ratio:.3f}，雨衣為{rain_ratio:.3f}，約高{(sport_ratio/rain_ratio-1)*100:.2f}%；單一倍率不能同時修正體形比例。'},
      {'code':'towel-face-occlusion','severity':'warning','message':'來源3/4/6左臉截線被毛巾遮擋，臉寬保持未知；不把短皮膚截面當完整臉寬。','frameIndices':[2,3,5]},
      {'code':'towel-return-transition-pending','severity':'warning','message':'來源3/4近似；6→7收毛巾缺中間姿勢。第一格疲累伸舌、末格微笑，未批准為無縫待機。','frameIndices':[0,2,3,5,6,7]}]
    report.update(generatedAt='2026-10-12',method='source-pinned-raincoat-v3-sport-v2-body-QC-adapter-v1',outfitCount=1,
                  revisionOf='raincoat-first-20261012',newSourceFrames=20,
                  standingReferenceComparison={'clipID':old['id'],'sourceSha256':old['sha256'],'regionsSha256':old['frameRegions']['sha256'],
                    'oldScale':old['scale'],'newScale':clip['catalogScale'],'oldSourcePixelToStagePixel':old_factor,'newSourcePixelToStagePixel':new_factor,
                    'frameBasis':'first source frame of both standing drawings','metrics':comparison,
                    'limitations':'眼足距是中立站姿代理；衣服遮住軀幹，沒有量到真正骨架／完整身高。臉呈現匹配不等於全身比例匹配。'},
                  crossOutfitComparison={'frameBasis':'first source frame; eye-lid expression differs, standing body proxy only',
                    'clipIDs':[clip['id'],sport['id']],'metrics':cross,
                    'scaleIndependentEyeFootToFaceRatio':{'raincoat':rain_ratio,'sport':sport_ratio,'changePercent':(sport_ratio/rain_ratio-1)*100},
                    'limitations':'兩套服裝的頭腳姿勢與表情不完全相同，約2px邊緣取點誤差不等於整段體型等同；量到明顯瘦長差異，不透過逐格fit或坐姿替代藏起。'})
    report['sourceReports'].append({'path':ref['path'],'sha256':ref['sha256']})
    comparison_path=HERE/'sport-towel-v1-v2-comparison.json';comparison_raw=comparison_path.read_bytes();revision=json.loads(comparison_raw)
    if revision['sources'][1]['sha256']!=sport['sourceSha256']:raise ValueError('sport revision proof stale')
    for dependency in revision['sourceReports']+revision['sources']:
        if hashlib.sha256((ROOT/dependency['path']).read_bytes()).hexdigest()!=dependency['sha256']:raise ValueError('sport revision dependency changed')
    report['sourceReports'].append({'path':comparison_path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(comparison_raw).hexdigest()})
    report['sourceReports'].extend(revision['sourceReports'])
    report['sourceReports']=list({item['path']:item for item in report['sourceReports']}.values())
    report['revisionEvidence']={'sportV1V2':{'path':comparison_path.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(comparison_raw).hexdigest()},
                               'v1IsIntermediateOnly':True,'newSourceCount':2,'newOutfits':1,'raincoatRevisions':1}
    for c,q in [(clip,qc),(sport,sport_qc)]:
        c['firstLast']=q['firstLast'];c['wholeClipSpread']=q['wholeClipSpread']
    report['limitations']=['本報告含12格站姿雨衣修訂、8格新運動服，共2來源20格；新增1套服裝，不把運動中間稿算另一套。',
      '雨衣12格均有可見眼白與兩隻裸腳，第11格半睜眼可量；未使用舊圖眼座標。',
      '運動第5格全閉眼，三項全未知；第3/4/6格毛巾遮左臉截面，只有眼距／眼足距。',
      '新舊PNG原畫像素大小不同，跨版本比較使用各自已固定的整段倍率，沒有逐格fit。',
      '臉寬是可見眼下緣方向的皮膚橫截；眼距是眼白下緣中點距，不是瞳孔距。',
      '眼足距使用兩個可見裸腳填色下緣平均作基線；傘、雨衣、輪廓anchor不當人體尺規。',
      '完整裸頭高／骨架受傘與衣服遮擋保持未知；邊緣取點約2source px不確定度。',
      '運動眼皮已修復，身形仍偏瘦長；調整整段倍率不能消除眼足／臉寬比例差。',
      '動作重排可減少手勢回退，未新增中間畫稿；首末非已驗收無縫循環，美術未批准。']
    return report
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();report=make_report()
    payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';out=HERE/'body-scale-audit.json'
    if args.check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('wardrobe body audit stale')
    else:out.write_text(payload,encoding='utf-8')
    print(json.dumps({'totals':report['totals'],'comparison':report['standingReferenceComparison']['metrics']},ensure_ascii=False))
if __name__=='__main__':main()
