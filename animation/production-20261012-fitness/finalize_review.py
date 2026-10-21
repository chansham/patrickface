"""Pin actual disposable-browser evidence; technical success never approves art."""
from pathlib import Path
import argparse,hashlib,json,math
from review_batch import verify_baseline
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
OUTPUT_SLUG='fitness-20261012';EXPECTED_CLIP_COUNT=8

def read(p):return json.loads(p.read_bytes())
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}

def report():
    catalog=read(ROOT/'animation/candidates.json');layouts=read(ROOT/'experience/layouts.json')['layouts'];clips=[];evidence=[];manifest=read(HERE/'manifest.json')
    verify_baseline(catalog)
    assert len(manifest['sources'])==EXPECTED_CLIP_COUNT and EXPECTED_CLIP_COUNT>0 and all(s['status']=='candidate-ready' for s in manifest['sources']), 'batch still incomplete'
    for spec in manifest['sources']:
        clip_id=spec['id']
        browser=ROOT/f'output/playwright/{OUTPUT_SLUG}/{clip_id}/browser/report.json'
        contours=ROOT/f'output/playwright/{OUTPUT_SLUG}/{clip_id}/contours/report.json'
        b,c=read(browser),read(contours);assert not b.get('error') and not b['errors']
        assert len(b['cases'])==1 and b['cases'][0]['id']==clip_id and all(x['passed'] for x in b['cases']) and all(x['passed'] for x in c['cases'])
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
                          'version':raw['version'],'scale':raw['scale'],'calibration':spec['calibration'],'sourcePixelToStagePixel':665.6*raw['scale']/regions['canvas']['width'],'sourceFrameOrder':item['sourceOrder'],
                          'normal1xObservedPlaybackFrames':[x['frame'] for x in item['normal1x']],'totalMs':item['totalMs'],
                          'lastFrameStartedAfterMs':item['normal1x'][-1]['at']-item['normal1x'][0]['at'],
                          'pixelOracle':{'mismatchChannels':0,'neighborLabels':0,'missingCore':0,'overlaps':0,'unassigned':0},
                          'layouts':[{'id':l['id'],'checkedFrames':len(l['frames']),'minStrongY':min(f['bounds'][1] for f in l['frames']),
                                      'maxStrongY':max(f['bounds'][1]+f['bounds'][3] for f in l['frames']),'timeDateInformationCollisions':0}for l in item['geometry']],
                          'screen200pxChecked':True,'localUserStorageChanged':False,
                          'screenshots':[f'output/playwright/{OUTPUT_SLUG}/{clip_id}/browser/{raw["id"]}-{name}.png'for name in ['reference-first','reference-last','four-layouts']]})
    total=sum(len(c['normal1xObservedPlaybackFrames']) for c in clips)
    return {'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'browserEvidence':evidence,
            'testedLayoutManifest':identity(ROOT/'experience/layouts.json'),'sourceFrames':total,'layoutFrameChecks':total*4,
            'newOutfits':sum(bool(s['newOutfit'])for s in manifest['sources']),'newCandidateClips':len(clips),'clips':clips,
            'sourceUnchanged':True,'priorCandidateBaselinePreserved':True,
            'remaining':[{'id':spec['id'],'findings':spec['visualReview']['findings']} for spec in manifest['sources']],
            'notes':manifest.get('runtimeNotes',['先前教練頁面初始化曾碰到同步編輯HTML期間的載入失敗；頁面完整後單套重跑通過，不掩蓋先前失敗。',
                     '四版式檢查使用全來源strong alpha，保留全部alpha像素；極淡碎點不當人物或道具本體。',
                     '拳擊/外套由v1小尺寸明確升為v2校準；舊候選資料和舊測試另存，不增候選數。',
                     'UI人體量尺的最終接入由獨立body audit與父代理頁面測試驗證；部分早期截圖當時該數字仍未知。']),
            'mainAndNativeUpdated':False,'deviceTested':False}

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();data=report();out=HERE/'runtime-review.json'
    payload=(json.dumps(data,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if out.read_bytes()!=payload:raise ValueError('runtime report stale')
    else:out.write_bytes(payload)
    print(json.dumps({'path':out.relative_to(ROOT).as_posix(),'frames':data['sourceFrames'],'layoutFrameChecks':data['layoutFrameChecks'],'artApproval':False}))
if __name__=='__main__':main()
