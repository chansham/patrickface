"""Pin the actual local browser evidence, without converting QA into art approval."""
from pathlib import Path
import argparse,hashlib,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def read(p):return json.loads(p.read_bytes())
def identity(p):return {'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(p.read_bytes()).hexdigest()}
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    browser=ROOT/'output/playwright/raincoat-20261012/browser/report.json';contours=ROOT/'output/playwright/raincoat-20261012/contours/report.json'
    b,c=read(browser),read(contours);assert not b.get('error') and not b['errors'];assert len(b['cases'])==2 and all(x['passed'] for x in b['cases']);assert all(x['passed'] for x in c['cases'])
    catalog=read(ROOT/'animation/candidates.json');clips=[]
    for item in b['cases']:
        raw=next(x for x in catalog['clips'] if x['id']==item['id']);assert raw['sha256']==item['sourceSHA'] and raw['frameRegions']['sha256']==item['regionsSHA']
        extraction=next(x for x in c['cases'][0]['clips'] if x['id']==item['id'])['extraction']
        assert extraction['overlaps']==extraction['unassigned']==0
        assert len(extraction['observations'])==8 and all(x['neighborLabels']==x['missingCore']==x['mismatchChannels']==0 for x in extraction['observations'])
        assert [x['frame'] for x in item['normal1x']]==list(range(8))
        clips.append({'id':raw['id'],'source':identity(ROOT/raw['atlas']),'regions':identity(ROOT/raw['frameRegions']['path']),'scale':raw['scale'],'sourceFrameOrder':item['sourceOrder'],
                      'normal1xObservedPlaybackFrames':[x['frame'] for x in item['normal1x']],'totalMs':item['totalMs'],'frame8StartedAfterMs':item['normal1x'][-1]['at']-item['normal1x'][0]['at'],
                      'pixelOracle':{'mismatchChannels':0,'neighborLabels':0,'missingCore':0,'overlaps':0,'unassigned':0},
                      'layouts':[{'id':l['id'],'checkedFrames':len(l['frames']),'minStrongY':min(f['bounds'][1] for f in l['frames']),'maxStrongY':max(f['bounds'][1]+f['bounds'][3] for f in l['frames']),'timeDateInformationCollisions':0} for l in item['geometry']]})
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'userDesignPreference':'站姿設計受到正向回饋，坐姿並列可選；不表示動畫通過。',
            'browserEvidence':[identity(browser),identity(contours)],'sourceFrames':16,'layoutFrameChecks':64,'outfits':1,'poses':2,'clips':clips,
            'remaining':['抬手及收手缺中間姿勢。','表情笑→閉眼不滿→微笑因果不足。','首末細節非無縫循環。','站姿臉呈現較主睡衣小約26.6%；保留使用者喜歡的站姿，不掩飾尺度差異。'],
            'mainAndNativeUpdated':False,'deviceTested':False}
    out=HERE/'runtime-review.json';data=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if out.read_bytes()!=data:raise ValueError('runtime report stale')
    else:out.write_bytes(data)
    print(json.dumps({'path':out.relative_to(ROOT).as_posix(),'sourceFrames':16,'layoutFrameChecks':64,'artApproval':False}))
if __name__=='__main__':main()
