"""Verify the completed local batch and summarize evidence without approving art."""
import hashlib,json
from pathlib import Path
import review_batch as batch

ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
read=batch.read
catalog=read(ROOT/'animation/candidates.json')
batch.verify_baseline(catalog)
specs=read(HERE/'manifest.json')['sources']
assert len(specs)==8 and all(s['status']=='candidate-ready' for s in specs)
selected=[c for c in catalog['clips'] if c.get('batch')=='20261012-fitness']
assert {c['id'] for c in selected}=={s['id'] for s in specs}
assert all(c['artApproved'] is False for c in selected)
requests=[]
for owner,key in [('root','requests'),('agent','attempts')]:
    for item in read(HERE/f'generation-{owner}.json')[key]:
        p=item.get('path') if owner=='root' else item.get('projectPath')
        if p:
            source=ROOT/p
            assert source.resolve().is_relative_to((ROOT/'animation').resolve()) and source.is_file()
        requests.append({'owner':owner,'id':item['id'],'status':item['status'],'path':p,
                         'sourceFrames':(8 if owner=='root' else item['columns']*item['rows']) if p else 0,
                         'sha256':batch.sha(ROOT/p) if p else None})
paths=[r['path'] for r in requests if r['path']]
assert len(paths)==len(set(paths)), 'Revisions must have their own preserved source.'
runtime=[]
for c in selected:
    out=ROOT/'output/playwright/fitness-20261012'/c['id']
    play=read(out/'browser/report.json');contour=read(out/'contours/report.json')
    assert not play.get('error') and play['errors']==[]
    case=next(r for r in play['cases'] if r['id']==c['id'])
    assert case['passed'] and case['sourceSHA']==c['sha256'] and case['regionsSHA']==c['frameRegions']['sha256']
    assert [r['frame'] for r in case['normal1x']]==list(range(c['frameCount']))
    assert all(r['passed'] for r in contour['cases'])
    pixels=next(r for r in contour['cases'] if r['name']=='all-real-contours-source-pixels-ownership-and-three-views')
    exact=next(r for r in pixels['clips'] if r['id']==c['id'])
    assert exact['imageHash']==c['sha256'] and exact['regionsHash']==c['frameRegions']['sha256']
    runtime.append({'id':c['id'],'version':c['version'],'sourceFrames':c['frameCount'],
                    'sourceSha256':c['sha256'],'regionsSha256':c['frameRegions']['sha256'],
                    'normalPlaybackVerified':True,'layoutFrameChecks':c['frameCount']*4})
ui=read(ROOT/'output/playwright/fitness-20261012/final-ui/report.json')
assert ui['passed'] and set(ui['fitnessIDs'])=={c['id'] for c in selected}
summary={'schemaVersion':1,'date':'2026-10-12','scope':'local candidate review; no Apple build or device validation',
         'artApproval':False,'requestCount':len(requests),'successfulSourceFiles':len(paths),
         'failedNoOutput':len(requests)-len(paths),'generatedSourceFramesIncludingIntermediates':sum(r['sourceFrames'] for r in requests),
         'newOutfits':len(selected),'newCandidateFrames':sum(c['frameCount'] for c in selected),
         'candidateTotal':len(catalog['clips']),'candidateFrameTotal':sum(c['frameCount'] for c in catalog['clips']),
         'previousCandidatesUnchanged':True,'mainCatalogUnchanged':True,'runtime':runtime,
         'layoutFrameChecks':sum(r['layoutFrameChecks'] for r in runtime),'uiCases':len(ui['cases']),
         'requests':requests,'nativePromotion':False}
batch.write_json(HERE/'completion-summary.json',summary)
print(json.dumps({k:v for k,v in summary.items() if k not in ['requests','runtime']},ensure_ascii=False))
