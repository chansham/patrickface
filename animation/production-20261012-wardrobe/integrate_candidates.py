"""Append reviewed-source wardrobe candidates; preserve prior candidates and source art."""
from pathlib import Path
import argparse,copy,hashlib,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
def read(p):return json.loads(p.read_bytes())
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def prepare(catalog):
    source=ROOT/'animation/raincoat-v3/atlas-generated.png';rp=source.with_name('regions-v1.json');regions=read(rp)
    qc=read(HERE/'raincoat-v3-qc.json');body=read(HERE/'raincoat-v3-body-qc.json');oldbody=read(ROOT/'animation/production-20261012-raincoat/raincoat-v1-qc.json')
    old=next(c for c in catalog['clips'] if c['id']=='raincoat-first-20261012');oldr=read(ROOT/old['frameRegions']['path'])
    for q in [qc,body]:
        if q['source']!=regions['source'] or q['source']['sha256']!=sha(source) or q['regions']['sha256']!=sha(rp):raise ValueError('new source/regions/QC drift')
    if oldbody['source']['sha256']!=old['sha256'] or oldbody['regions']['sha256']!=old['frameRegions']['sha256']:raise ValueError('prior standing reference drift')
    oldwidth=oldbody['frames'][0]['faceWidthPx'];newwidth=body['frames'][0]['faceWidthPx'];oldfactor=665.6*old['scale']/oldr['canvas']['width']
    factor=oldwidth*oldfactor/newwidth;scale=factor*regions['canvas']['width']/665.6
    rain=[{'id':'raincoat-smooth-20261012','title':'雨衣・站姿抬手過渡修訂','category':'修訂稿待審','version':1,'batch':'20261012-wardrobe','reviewGroup':'scene',
             'atlas':regions['source']['path'],'width':regions['source']['width'],'height':regions['source']['height'],'columns':3,'rows':4,'frameCount':12,
             'frameIndices':qc['frameIndices'],'durationsMs':[650,300,180,180,180,260,320,180,180,180,130,700],
             'sha256':sha(source),'anchorNormalized':regions['canvas']['anchorNormalized'],'masterId':catalog['master']['id'],'scale':scale,
             'status':'quality-revision-required','scenes':['awake'],'triggerKinds':['manual-review'],
             'description':'保留站姿雨衣，新增腰前、胸口與收手姿勢。12原畫重排讓抬手較連續；眼神與嘴部仍有跳換，首末臉寬約差2.6%，仍待審。',
             'frameLabels':['站姿休息','抬眼看傘','手到腰前','抬至胸口','抬至肩側','举手看天','攤手笑','開始收手','收至胸前','收至腰前','半睜眼收回','回到微笑'],
             'frameRegions':{**qc['regions'],'version':1},'renderingRevision':'wardrobe-20261012-v1','comparisonClipId':'raincoat-first-20261012',
             'artApproved':False,'variantGroup':'yellow-raincoat-blue-umbrella','pose':'standing','newOutfit':False,
             'designFeedback':'延續使用者喜歡的站姿造型；新增動作畫稿未經逐格批准。',
             'scaleProvenance':{'method':'match-prior-standing-first-visible-face-caliper','referenceCandidate':old['id'],'referenceSourceSHA':old['sha256'],
                                'referenceFirstFaceWidthSource':oldwidth,'referenceSourcePixelToStagePixel':oldfactor,'newFirstFaceWidthSource':newwidth,
                                'sourcePixelToStagePixel':factor,'catalogScale':scale,'canvas':regions['canvas']['width'],'perFrameScale':False,
                                'note':'只將新段首格臉截線與既有站姿對齊；其餘各格保持同倍率，原畫尺寸變化仍保留。雨傘外框不是人體尺規。'},
             'reviewProvenance':{'qc':'animation/production-20261012-wardrobe/raincoat-v3-qc.json','bodyQC':'animation/production-20261012-wardrobe/raincoat-v3-body-qc.json',
                                 'repairReferenceCandidate':old['id'],'sourceFrameCount':12,'reorderingIsNotRedrawing':True}}]
    source=ROOT/'animation/sport-towel-v2/atlas-generated.png';rp=source.with_name('regions-v1.json');regions=read(rp)
    qc=read(HERE/'sport-towel-v2-qc.json');body=read(HERE/'sport-towel-v2-body-qc.json')
    for q in [qc,body]:
        if q['source']!=regions['source'] or q['source']['sha256']!=sha(source) or q['regions']['sha256']!=sha(rp):raise ValueError('sport source/regions/QC drift')
    # A fixed scene-safe factor, never per-frame fit. The taller body stays visible
    # as an unresolved art difference instead of hiding it by matching a full bbox.
    factor=1.35;scale=factor*regions['canvas']['width']/665.6
    sport={'id':'sport-towel-first-20261012','title':'運動背心・毛巾擦汗','category':'新造型待審','version':1,'batch':'20261012-wardrobe','reviewGroup':'scene',
           'atlas':regions['source']['path'],'width':regions['source']['width'],'height':regions['source']['height'],'columns':4,'rows':2,'frameCount':8,
           'frameIndices':list(range(8)),'durationsMs':[650,250,200,180,320,200,230,700],
           'sha256':sha(source),'anchorNormalized':regions['canvas']['anchorNormalized'],'masterId':catalog['master']['id'],'scale':scale,
           'status':'quality-revision-required','scenes':['exercise'],'triggerKinds':['manual-review'],
           'description':'新運動背心、髮帶與白毛巾。粉眼皮已修；8格仍有抬手／降毛巾跳換，身形比雨衣高瘦，首疲憊末微笑，尚待動作與比例修訂。',
           'frameLabels':['運動後喘氣','拿起毛巾','抬到臉旁','輕擦臉頰','閉眼擦汗','睜眼停留','毛巾降到胸前','微笑放手'],
           'frameRegions':{**qc['regions'],'version':1},'renderingRevision':'wardrobe-20261012-v1','comparisonClipId':'exercise',
           'artApproved':False,'variantGroup':'teal-sport-orange-headband-white-towel','pose':'standing','newOutfit':True,
           'designFeedback':'新穿搭探索；色彩修訂沿用同一套衣服，不將中間紫眼皮稿另算新造型。',
           'scaleProvenance':{'method':'fixed-whole-clip-factor-with-visible-face-and-four-layout-safety-review',
                              'newFirstFaceWidthSource':body['frames'][0]['faceWidthPx'],'sourcePixelToStagePixel':factor,'catalogScale':scale,
                              'canvas':regions['canvas']['width'],'perFrameScale':False,
                              'note':'以可見臉截線核對，整段固定1.35來源像素／舞台像素換算。高瘦比例差保留為待修，不用毛巾或全身外框冒充人體一致。'},
           'reviewProvenance':{'qc':'animation/production-20261012-wardrobe/sport-towel-v2-qc.json','bodyQC':'animation/production-20261012-wardrobe/sport-towel-v2-body-qc.json',
                               'sourceFrameCount':8,'intermediateSource':'animation/sport-towel-v1/atlas-generated.png','intermediateNotCandidate':True}}
    return rain+[sport]
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();path=ROOT/'animation/candidates.json';before=path.read_bytes();catalog=json.loads(before);old=copy.deepcopy(catalog['clips']);new=prepare(catalog)
    for item in new:
        existing=[c for c in catalog['clips'] if c['id']==item['id']]
        if existing:
            if existing!=[item]:raise ValueError('new candidate identity differs; no silent overwrite')
        elif args.check:raise ValueError('new candidate absent')
        else:catalog['clips'].append(item)
    if not args.check:
        if path.read_bytes()!=before:raise ValueError('catalog changed concurrently')
        catalog['updatedAt']='2026-10-12';path.write_bytes((json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))
    if any(next(c for c in catalog['clips'] if c['id']==item['id'])!=item for item in old):raise ValueError('prior candidate changed')
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'newOutfits':1,'revisedClips':1,'newSourceFrames':20,
            'candidateCount':len(catalog['clips']),'candidateFrames':sum(c['frameCount'] for c in catalog['clips']),
            'mainCatalogSha256':sha(ROOT/'animation/catalog.json'),'clips':new};out=HERE/'catalog-integration.json'
    if args.check:
        if read(out)!=report:raise ValueError('integration report stale')
    else:out.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:report[k] for k in ['candidateCount','candidateFrames','newOutfits','revisedClips','newSourceFrames']}));print(json.dumps(new[0]['scaleProvenance']))
if __name__=='__main__':main()
