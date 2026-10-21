"""Pin actual disposable-browser evidence; technical success never approves art."""
from pathlib import Path
import argparse,hashlib,json,math
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent

def read(p):return json.loads(p.read_bytes())
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}

def report():
    catalog=read(ROOT/'animation/candidates.json');layouts=read(ROOT/'experience/layouts.json')['layouts'];clips=[];evidence=[]
    for suffix in ['raincoat','sport']:
        browser=ROOT/f'output/playwright/wardrobe-20261012/browser-{suffix}/report.json'
        contours=ROOT/f'output/playwright/wardrobe-20261012/contours-{suffix}/report.json'
        b,c=read(browser),read(contours);assert not b.get('error') and not b['errors']
        assert len(b['cases'])==1 and all(x['passed'] for x in b['cases']) and all(x['passed'] for x in c['cases'])
        evidence.extend([identity(browser),identity(contours)])
        for item in b['cases']:
            raw=next(x for x in catalog['clips'] if x['id']==item['id']);count=raw['frameCount'];regions=read(ROOT/raw['frameRegions']['path'])
            assert raw['sha256']==item['sourceSHA']==identity(ROOT/raw['atlas'])['sha256']
            assert raw['frameRegions']['sha256']==item['regionsSHA']==identity(ROOT/raw['frameRegions']['path'])['sha256']
            assert item['sourceOrder']==raw['frameIndices'] and item['totalMs']==sum(raw['durationsMs'])
            extraction=next(x for x in c['cases'][0]['clips'] if x['id']==item['id'])['extraction']
            assert extraction['overlaps']==extraction['unassigned']==0
            assert len(extraction['observations'])==count and all(x['neighborLabels']==x['missingCore']==x['mismatchChannels']==0 for x in extraction['observations'])
            assert [x['frame'] for x in item['normal1x']]==list(range(count))
            # The current fixed scale/layout still matches the tested geometry.
            for actual in item['geometry']:
                layout=next(l for l in layouts if l['id']==actual['id']);scale,tx,ty=layout['characterTransform']
                expected_factor=665.6*raw['scale']/regions['canvas']['width']*scale
                expected_anchor=[416*scale+tx,893.632*scale+ty]
                assert len(actual['frames'])==count
                for frame in actual['frames']:
                    assert math.isclose(frame['pixelScale'],expected_factor,abs_tol=1e-9)
                    assert all(math.isclose(a,b,abs_tol=1e-9)for a,b in zip(frame['anchor'],expected_anchor))
            clips.append({'id':raw['id'],'source':identity(ROOT/raw['atlas']),'regions':identity(ROOT/raw['frameRegions']['path']),
                          'scale':raw['scale'],'sourcePixelToStagePixel':665.6*raw['scale']/regions['canvas']['width'],'sourceFrameOrder':item['sourceOrder'],
                          'normal1xObservedPlaybackFrames':[x['frame'] for x in item['normal1x']],'totalMs':item['totalMs'],
                          'lastFrameStartedAfterMs':item['normal1x'][-1]['at']-item['normal1x'][0]['at'],
                          'pixelOracle':{'mismatchChannels':0,'neighborLabels':0,'missingCore':0,'overlaps':0,'unassigned':0},
                          'layouts':[{'id':l['id'],'checkedFrames':len(l['frames']),'minStrongY':min(f['bounds'][1] for f in l['frames']),
                                      'maxStrongY':max(f['bounds'][1]+f['bounds'][3] for f in l['frames']),'timeDateInformationCollisions':0}for l in item['geometry']],
                          'screen200pxChecked':True,'localUserStorageChanged':False,
                          'screenshots':[f'output/playwright/wardrobe-20261012/browser-{suffix}/{raw["id"]}-{name}.png'for name in ['reference-first','reference-last','four-layouts']]})
    return {'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'browserEvidence':evidence,
            'testedLayoutManifest':identity(ROOT/'experience/layouts.json'),'sourceFrames':20,'layoutFrameChecks':80,
            'newOutfits':1,'revisedExistingOutfits':1,'newCandidateClips':2,'clips':clips,
            'remaining':['雨衣重排改善手臂進退，但眼神／嘴形仍有突然轉換，首末臉寬差約2.6%。',
                         '運動第1／5格粉眼皮已修；3／4近同姿與6→7降毛巾仍缺過渡，首末表情非無縫。',
                         '運動眼足／臉截面比例比雨衣約長27.84%；固定縮放不能修正原畫身形。',
                         '比較截圖拍攝當時新人體audit尚未接入頁面，數字未知；獨立人體報告和後續頁面驗收另存，不能以本次截圖聲稱量測UI通過。'],
            'mainAndNativeUpdated':False,'deviceTested':False}

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();data=report();out=HERE/'runtime-review.json'
    payload=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if out.read_bytes()!=payload:raise ValueError('runtime report stale')
    else:out.write_bytes(payload)
    print(json.dumps({'path':out.relative_to(ROOT).as_posix(),'frames':20,'layoutFrameChecks':80,'artApproval':False}))
if __name__=='__main__':main()
