"""Bind the completed browser evidence to exact candidate sources; never approve art."""
from pathlib import Path
import hashlib,json,subprocess
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def sha(raw):return hashlib.sha256(raw).hexdigest()
def read(p):return json.loads(p.read_bytes())
def evidence(relative):
    raw=(ROOT/relative).read_bytes();return read(ROOT/relative),{'path':relative,'sha256':sha(raw)}
def main():
    ui,ui_ref=evidence('output/playwright/20261007-completion/report.json')
    live,live_ref=evidence('output/playwright/20261007-completion/live-capture-report.json')
    contour,contour_ref=evidence('output/playwright/20261007-completion-contours/report.json')
    assert all(c['passed'] for c in ui['cases']) and not ui['errors']
    assert all(c['passed'] for c in contour['cases']) and live['passed']
    catalog=read(ROOT/'animation/candidates.json');main_bytes=(ROOT/'animation/catalog.json').read_bytes()
    previous=json.loads(subprocess.check_output(['git','show','HEAD:animation/candidates.json'],cwd=ROOT))
    # This batch has exactly three append-only candidates; older opinions/images
    # are not reset. Do not use this tool after a later candidate batch is added.
    prior=[c for c in catalog['clips'] if c.get('batch')!='20261007-completion']
    assert prior==[c for c in previous['clips'] if c.get('batch')!='20261007-completion'], 'Existing candidate meaning drifted'
    assert subprocess.check_output(['git','show','HEAD:animation/catalog.json'],cwd=ROOT)==main_bytes
    notes={
     'chef-cookie-repair-20261007':{'improved':'末格盤上餅乾缺口在200px可辨，10→11→12下放敘事保留。','remaining':'5→6餅乾離口與收手仍較快；細部握持和餅乾朝向可再審。'},
     'focus-transition-repair-20261007':{'improved':'第9格手臂在臉側與筆記本之間的姿勢可見，收手有實質新過渡。','remaining':'末段身形仍較首格短；眼線至真足底-5.195%、頭頂至真足底-4.196%，沒有修妥。'},
     'charging-cozy-20261007':{'improved':'v2第7、9格提供傾頭靠枕及回正中間姿勢；抬枕和擠壓在200px可讀。','remaining':'7→8與9→10角度仍有階躍，帽沿與睡衣形狀略變；首末不是完全閉環。'}
    }
    clips=[]
    for c in [c for c in catalog['clips'] if c.get('batch')=='20261007-completion']:
        m=read(ROOT/c['frameRegions']['path']);assert sha((ROOT/c['atlas']).read_bytes())==c['sha256'];assert sha((ROOT/c['frameRegions']['path']).read_bytes())==c['frameRegions']['sha256']
        old=next(x for x in ui['cases'] if x['name']=='actual-old-new-'+c['id'])
        assert old['sourceSha256']==c['sha256'] and old['regionsSha256']==c['frameRegions']['sha256']
        played=next(x for x in live['clips'] if x['id']==c['id']);assert [f['index'] for f in played['frames']]==list(range(12)) and played['endedAtLast']
        pixels=next(x for x in contour['cases'][0]['clips'] if x['id']==c['id'])
        assert pixels['imageHash']==c['sha256'] and pixels['regionsHash']==c['frameRegions']['sha256']
        assert pixels['extraction']['overlaps']==pixels['extraction']['unassigned']==0
        assert all(x['mismatchChannels']==x['neighborLabels']==x['missingCore']==0 for x in pixels['extraction']['observations'])
        clips.append({'id':c['id'],'source':m['source'],'regions':c['frameRegions'],'scale':c['scale'],'sourcePixelToStagePixel':665.6*c['scale']/m['canvas']['width'],
                      'frameCount':12,'allSourceFramesUsed':True,'allNonzeroAlphaPixelsPreserved':True,'perFrameScale':False,'fixedAnchor':True,
                      'normalSpeed':'actual-foreground-1x-all12frames-ended-on-last','visualReview':notes[c['id']],
                      'liveFrameSheet':'output/playwright/20261007-completion/'+c['id']+'-live-1x-frames.png','artApproved':False})
    audit=read(HERE/'body-scale-audit.json')
    report={'schemaVersion':1,'startedAt':'2026-10-07','reviewedAt':'2026-10-08','artApproved':False,'allArtworkComplete':False,
            'status':'candidate-delivery-browser-verified-art-review-pending','batch':'20261007-completion',
            'selectedSources':3,'selectedFrames':36,'generatedSourcesIncludingIntermediate':4,'generatedFramesIncludingIntermediate':48,
            'intermediateSource':'animation/charging-cozy-v1/atlas-generated.png','candidateCount':len(catalog['clips']),'candidateFrames':sum(c['frameCount'] for c in catalog['clips']),
            'mainCatalogSha256':sha(main_bytes),'mainCatalogUnchanged':True,'previousCandidateEntriesUnchanged':len(prior),
            'candidateCatalogSha256':sha((ROOT/'animation/candidates.json').read_bytes()),'measurements':audit['totals'],
            'checks':{'sizeReviewCasesPassed':len(ui['cases']),'contourCasesPassed':len(contour['cases']),'fourLayoutFrameChecks':144,'realTimePlaybackFrames':36,
                      'sourceRgbaChannelMismatch':0,'neighborCoreLeakage':0,'missingStrongCore':0,'savedOpinionIsolationPassed':True},
            'evidence':[ui_ref,live_ref,contour_ref],
            'visualSupplement':['output/playwright/20261007-completion/charging-v1-v2-fixed-scale.png','output/playwright/20261007-completion/charging-source-alpha-black-white.png'],
            'clips':clips,'limits':['Only the selected3clips were browser-tested this batch; no claim of full-library or native artwork acceptance.',
                                   'Original classic idle and additional focus torso edit produced no image; no v8 exists.',
                                   'Semantic metrics deliberately incomplete. Slippers are not anatomical feet; cozy eye-to-foot remains null.',
                                   'Main/native resources unchanged. Old candidate references and all source PNGs retained.']}
    (HERE/'runtime-review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({'status':report['status'],'checks':report['checks'],'measurements':report['measurements']},ensure_ascii=False))
if __name__=='__main__':main()
