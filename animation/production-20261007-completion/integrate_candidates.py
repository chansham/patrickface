"""Append source-pinned review candidates; never replace an old candidate or main catalog."""
from pathlib import Path
import argparse,copy,hashlib,json
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
SPECS=[
 {'id':'chef-cookie-repair-20261007','title':'小廚師・餅乾咬痕收尾改稿','folder':'feeding-chef-v6','reference':'chef-repair-20261006','comparison':'feed','columns':4,'rows':3,'group':'interaction','scene':'awake','scaleMode':'preserve-source-density','description':'末格盤上餅乾保留咬痕，完整12格可看；5→6收手及細部變形仍待審，未換入日常。'},
 {'id':'focus-transition-repair-20261007','title':'正裝・收手中間姿勢改稿','folder':'focus-v7','reference':'focus-followup-20261006','comparison':'focus','columns':3,'rows':4,'group':'scene','scene':'focus','scaleMode':'preserve-source-density','description':'第9格增加收手中間姿勢；首末眼線至真足底仍短約5.19%，身形尚未修妥。完整12格保留對照。'},
 {'id':'charging-cozy-20261007','title':'星星睡衣・抱電池充電','folder':'charging-cozy-v2','reference':None,'comparison':'charging','columns':3,'rows':4,'group':'scene','scene':'charging','scaleMode':'fixed-new-costume','scale':1.75,'description':'新奶油黃星星睡衣、睡帽與紫拖鞋，抬起並擠壓電池抱枕。第7、9格補傾頭中間姿勢，首末不是完全閉環，仍待審。'},
]
def sha(raw):return hashlib.sha256(raw).hexdigest()
def read(path):return json.loads(path.read_bytes())
def prepare(catalog,spec):
    folder=ROOT/'animation'/spec['folder'];source=folder/'atlas-generated.png';rp=folder/'regions-v1.json'
    m=read(rp);q=read(HERE/(spec['folder']+'-qc.json'))
    if m['source']!=q['source'] or sha(source.read_bytes())!=q['source']['sha256'] or sha(rp.read_bytes())!=q['regions']['sha256']:raise ValueError('QC/source/regions mismatch')
    ref=next((c for c in catalog['clips'] if c['id']==spec['reference']),None)
    if spec['scaleMode']=='preserve-source-density':
        if ref is None:raise ValueError('missing prior candidate')
        old=read(ROOT/ref['frameRegions']['path']);scale=ref['scale']*m['canvas']['width']/old['canvas']['width']
        provenance={'method':'preserve-reviewed-source-pixel-density','referenceCandidate':ref['id'],'oldScale':ref['scale'],'oldCanvas':old['canvas']['width'],'newCanvas':m['canvas']['width'],'newScale':scale,'perFrameScaling':False}
        durations=ref['durationsMs']
    else:
        scale=spec['scale'];durations=[500]+[220]*10+[600]
        provenance={'method':'single-new-costume-scale-after-neutral-face-and-layout-review','newScale':scale,'perFrameScaling':False,'note':'Fixed1.75 on700px canvas retains original source pixel density1.664 stage pixels; not a claim of identical bodies or anatomical normalization.'}
    return {'id':spec['id'],'title':spec['title'],'category':'修訂稿待審' if ref else '新造型待審','version':1,'batch':'20261007-completion','reviewGroup':spec['group'],
            'atlas':m['source']['path'],'width':m['source']['width'],'height':m['source']['height'],'columns':spec['columns'],'rows':spec['rows'],'frameCount':len(m['frames']),
            'durationsMs':durations,'sha256':m['source']['sha256'],'anchorNormalized':m['canvas']['anchorNormalized'],'masterId':catalog['master']['id'],'scale':scale,
            'status':'quality-revision-required','scenes':[spec['scene']],'triggerKinds':['manual-review'],'description':spec['description'],
            'frameRegions':{**q['regions'],'version':1},'renderingRevision':'completion-20261007-v1','comparisonClipId':spec['comparison'],
            'artApproved':False,'scaleProvenance':provenance,'reviewProvenance':{'qc':(HERE/(spec['folder']+'-qc.json')).relative_to(ROOT).as_posix(),'repairReferenceCandidate':spec['reference']}}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args()
    path=ROOT/'animation/candidates.json';before=path.read_bytes();catalog=json.loads(before);old=copy.deepcopy(catalog['clips']);new=[prepare(catalog,s) for s in SPECS]
    for clip in new:
        matches=[x for x in catalog['clips'] if x['id']==clip['id']]
        if matches:
            if matches!=[clip]:raise ValueError('existing new ID differs; do not silently overwrite')
        elif args.check:raise ValueError('candidate missing')
        else:catalog['clips'].append(clip)
    if not args.check:
        catalog['updatedAt']='2026-10-08';payload=(json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8')
        if path.read_bytes()!=before:raise ValueError('candidate catalog changed concurrently')
        path.write_bytes(payload)
    for clip in old:
        if next(x for x in catalog['clips'] if x['id']==clip['id'])!=clip:raise ValueError('prior candidate changed')
    report={'schemaVersion':1,'date':'2026-10-08','batchStartedAt':'2026-10-07','artApproved':False,'mainCatalogUnchanged':True,'sourcePNGsUnchanged':True,
            'batch':'20261007-completion','candidateCount':len(catalog['clips']),'candidateFrames':sum(c['frameCount'] for c in catalog['clips']),
            'newSourceFrames':sum(c['frameCount'] for c in new),'clips':[{k:c[k] for k in ['id','atlas','sha256','frameRegions','scale','frameCount','comparisonClipId','scaleProvenance']} for c in new]}
    out=HERE/'catalog-integration.json'
    if args.check:
        if read(out)!=report:raise ValueError('integration snapshot stale')
    else:out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(report,ensure_ascii=False))
if __name__=='__main__':main()
