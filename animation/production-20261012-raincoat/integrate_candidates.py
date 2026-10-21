"""Append both user-requested raincoat poses, preserving all prior candidates."""
from pathlib import Path
import argparse,copy,hashlib,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
SPECS=[('raincoat-first-20261012','雨衣・站姿看天','raincoat-v1',[0,2,1,3,4,5,6,7],1.203125),
       ('raincoat-seated-20261012','雨衣・坐姿看天','raincoat-v2',list(range(8)),1.3040865384615383)]
def read(p):return json.loads(p.read_bytes())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def clip(catalog,spec):
    id,title,folder,order,scale=spec;p=ROOT/'animation'/folder/'atlas-generated.png';rp=p.with_name('regions-v1.json');r=read(rp);q=read(HERE/(folder+'-qc.json'))
    if sha(p)!=q['source']['sha256'] or q['source']!=r['source'] or sha(rp)!=q['regions']['sha256']:raise ValueError('source/regions/QC drift')
    standing=folder=='raincoat-v1'
    return {'id':id,'title':title,'category':'新造型待審','version':1,'batch':'20261012-raincoat','reviewGroup':'scene',
            'atlas':r['source']['path'],'width':1536,'height':1024,'columns':4,'rows':2,'frameCount':8,'frameIndices':order,
            'durationsMs':[700,330,240,300,350,220,350,800],'sha256':sha(p),'anchorNormalized':r['canvas']['anchorNormalized'],
            'masterId':catalog['master']['id'],'scale':scale,'status':'quality-revision-required','scenes':['awake'],'triggerKinds':['manual-review'],
            'description':('使用者喜歡的站姿設計，保留高傘與雨衣。原8格重新排序；臉部比睡衣小，抬手收手與表情跳換仍待修。' if standing else '同一套雨衣的坐姿短柄傘選項，原8格順序。角色可放較大；仍缺抬手與收手中間姿勢，不取代站姿。'),
            'frameLabels':['休息看前方','抬眼看傘','小幅抬手','舉手看天','攤手微笑','閉眼不滿','收手微笑','回到休息'],
            'frameRegions':{**q['regions'],'version':1},'renderingRevision':'raincoat-20261012-v1','comparisonClipId':'yawn','artApproved':False,
            'variantGroup':'yellow-raincoat-blue-umbrella','pose':'standing' if standing else 'seated',
            'designFeedback':'使用者明確喜歡站姿設計；不代表動畫逐格通過。' if standing else '並列姿態選項，尚未得到使用者偏好評價。',
            'scaleProvenance':{**q['scaleProposal'],'canvas':r['canvas']['width'],'firstFaceWidthSource':q['frames'][0]['faceWidthPx']},
            'reviewProvenance':{'qc':(HERE/(folder+'-qc.json')).relative_to(ROOT).as_posix(),'sourceFrameCount':8,'outfitCountSharedWithVariant':1}}
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();path=ROOT/'animation/candidates.json';before=path.read_bytes();c=json.loads(before);old=copy.deepcopy(c['clips']);new=[clip(c,s) for s in SPECS]
    for item in new:
        matches=[x for x in c['clips'] if x['id']==item['id']]
        if matches:
            if matches!=[item]:raise ValueError('existing raincoat candidate differs')
        elif args.check:raise ValueError('candidate missing')
        else:c['clips'].append(item)
    if not args.check:
        if path.read_bytes()!=before:raise ValueError('catalog changed concurrently')
        c['updatedAt']='2026-10-12';path.write_bytes((json.dumps(c,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))
    if any(next(x for x in c['clips'] if x['id']==item['id'])!=item for item in old):raise ValueError('old candidate changed')
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'newOutfits':1,'poseVariants':2,'newSourceFrames':16,
            'candidateCount':len(c['clips']),'candidateFrames':sum(x['frameCount'] for x in c['clips']),
            'mainCatalogSha256':sha(ROOT/'animation/catalog.json'),'clips':new}
    out=HERE/'catalog-integration.json'
    if args.check:
        if read(out)!=report:raise ValueError('integration report stale')
    else:out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['candidateCount','candidateFrames','newOutfits','poseVariants','newSourceFrames']}))
if __name__=='__main__':main()
