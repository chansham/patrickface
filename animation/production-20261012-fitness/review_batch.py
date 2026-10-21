"""Incremental contour QA and append-only candidate integration. Never edits PNGs."""
from pathlib import Path
import argparse,copy,hashlib,json,math,sys
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
BATCH_ID='20261012-fitness';OUTPUT_SLUG='fitness-20261012';RENDERING_REVISION='fitness-20261012-v1'
sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import validate_regions

def read(path):return json.loads(path.read_bytes())
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def write_json(path,data):path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
def verify_baseline(catalog):
    baseline=read(HERE/'baseline.json')
    if sha(ROOT/'animation/catalog.json')!=baseline['mainCatalogSha256']:raise ValueError('main catalog changed during candidate-only work')
    for before in baseline['previousCandidates']:
        matches=[c for c in catalog['clips']if c['id']==before['id']]
        if len(matches)!=1:raise ValueError('prior candidate removed or duplicated')
        current=hashlib.sha256(json.dumps(matches[0],sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()
        if current!=before['canonicalSha256']:raise ValueError('prior candidate changed: '+before['id'])
def confined(relative):
    path=ROOT/relative
    if not path.resolve().is_relative_to((ROOT/'animation').resolve()) or path.resolve()!=path.absolute():raise ValueError('source/sidecar path must remain in animation/')
    return path

def inspect(spec,write_images):
    source=confined(spec['source']);region_path=source.with_name('regions-v1.json');regions=read(region_path)
    if sha(source)!=spec['sha256'] or regions['source']['sha256']!=spec['sha256'] or regions['source']['path']!=spec['source']:raise ValueError('source changed')
    with Image.open(source)as image:
        if image.format!='PNG' or 'A' not in image.getbands():raise ValueError('explicit alpha PNG required')
        im=image.convert('RGBA');pixels=np.array(im)
    if regions['source']['width']!=im.width or regions['source']['height']!=im.height:raise ValueError('source dimensions changed')
    if len(regions['frames'])!=spec['columns']*spec['rows']:raise ValueError('source grid/count mismatch')
    coverage=validate_regions(regions,pixels[:,:,3]);alpha=pixels[:,:,3];edge=np.zeros(alpha.shape,bool);edge[[0,-1],:]=True;edge[:,[0,-1]]=True
    if write_images:
        out=ROOT/'output/playwright'/OUTPUT_SLUG/spec['id']/'source';out.mkdir(parents=True,exist_ok=True)
        for color in ['black','white']:
            bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);bg.convert('RGB').save(out/f'source-{color}.png')
        size=regions['canvas']['width'];order=spec.get('frameIndices',list(range(len(regions['frames']))));cols=min(4,len(order));rows=math.ceil(len(order)/cols)
        sheet=Image.new('RGB',(cols*size,rows*(size+30)),'#17131e');draw=ImageDraw.Draw(sheet)
        for playback,index in enumerate(order):
            f=regions['frames'][index];dx,dy=f['translation'];frame=np.zeros((size,size,4),dtype=np.uint8)
            for row in f['rows']:
                yy=row[0]
                for start,end in zip(row[1::2],row[2::2]):frame[yy+dy,start+dx:end+dx]=pixels[yy,start:end]
            tile=Image.fromarray(frame);x=playback%cols*size;y=playback//cols*(size+30);sheet.paste(tile,(x,y),tile)
            draw.text((x+8,y+size+6),f'play {playback+1} / source {index+1}',fill='white')
        sheet.save(out/'contour-play-order.png')
    return {'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'candidateID':spec['id'],'source':regions['source'],
            'regions':{'path':region_path.relative_to(ROOT).as_posix(),'sha256':sha(region_path)},'canvas':regions['canvas'],
            'sourceUnchanged':sha(source)==spec['sha256'],'sourceFrames':len(regions['frames']),'coverage':coverage,
            'sourceAlpha':{'transparentPixels':int((alpha==0).sum()),'alphaOnePixels':int((alpha==1).sum()),'edgeNonzeroPixels':int(((alpha>0)&edge).sum()),
                           'edgeStrongPixels':int(((alpha>=128)&edge).sum()),'maximumEdgeAlpha':int(alpha[edge].max()),'detachedComponents':regions['diagnostics']['detachedComponentCount']},
            'frames':[{'sourceFrame':i+1,'sourceBounds':f['sourceBounds'],'coreBounds':f['diagnostics']['coreBounds'],'anchorSource':f['anchorSource'],
                       'translation':f['translation'],'placement':f['placement'],'alignmentIsAnatomy':False}for i,f in enumerate(regions['frames'])],
            'sourceReview':spec.get('visualReview',{'status':'not-yet-reviewed'}),'bodyMeasurementReport':spec.get('bodyQC'),
            'status':spec.get('status','source-not-reviewed')}

def candidate(spec,qc,catalog):
    if spec['status']!='candidate-ready':raise ValueError('manual source review must precede candidate integration')
    visual=spec['visualReview']
    if not visual.get('sourceViewed') or not visual.get('blackWhiteViewed') or not visual.get('alignmentReviewed'):raise ValueError('source visual/alignment review missing')
    body=read(confined(spec['bodyQC']))
    if body['source']!=qc['source'] or body['regions']!=qc['regions']:raise ValueError('body QC is for another source or contour')
    factor=spec['fixedSourcePixelToStagePixel']
    if isinstance(factor,bool) or not math.isfinite(factor) or factor<=0:raise ValueError('positive fixed factor required')
    count=qc['sourceFrames'];order=spec.get('frameIndices',list(range(count)))
    if sorted(order)!=list(range(count)):raise ValueError('this batch requires each actual drawing once; no invented/duplicated frames')
    if len(spec['durationsMs'])!=count or len(spec['frameLabels'])!=count:raise ValueError('playback details incomplete')
    if any(isinstance(n,bool) or not isinstance(n,int) or n<16 or n>30000 for n in spec['durationsMs']):raise ValueError('invalid frame duration')
    scale=factor*qc['canvas']['width']/665.6
    if not 0.1<=scale<=4:raise ValueError('scale outside renderer bounds')
    # Preserve one factor for the entire clip and enforce all current stage edges.
    for layout in read(ROOT/'experience/layouts.json')['layouts']:
        s,tx,ty=layout['characterTransform']
        for frame in qc['frames']:
            x0,y0,x1,y1=frame['coreBounds'];ax,ay=frame['anchorSource']
            bounds=[(416+(x0-ax)*factor)*s+tx,(893.632+(y0-ay)*factor)*s+ty,
                    (416+(x1-ax)*factor)*s+tx,(893.632+(y1-ay)*factor)*s+ty]
            if bounds[0]<0 or bounds[1]<0 or bounds[2]>832 or bounds[3]>992:raise ValueError(f'{spec["id"]} crosses {layout["id"]} stage; inspect before integrating')
    return {'id':spec['id'],'title':spec['title'],'category':'新造型待審' if spec['newOutfit'] else '修訂稿待審','version':spec.get('version',1),'batch':BATCH_ID,'reviewGroup':'scene',
            'atlas':spec['source'],'width':qc['source']['width'],'height':qc['source']['height'],'columns':spec['columns'],'rows':spec['rows'],'frameCount':count,
            'frameIndices':order,'durationsMs':spec['durationsMs'],'frameLabels':spec['frameLabels'],'sha256':spec['sha256'],
            'anchorNormalized':qc['canvas']['anchorNormalized'],'masterId':catalog['master']['id'],'scale':scale,'status':'quality-revision-required',
            'scenes':spec.get('scenes',['exercise']),'triggerKinds':['manual-review'],'description':spec['description'],'frameRegions':{**qc['regions'],'version':1},
            'renderingRevision':RENDERING_REVISION,'comparisonClipId':spec['comparisonClipId'],'artApproved':False,'variantGroup':spec['variantGroup'],'pose':spec['pose'],'newOutfit':spec['newOutfit'],
            'scaleProvenance':{'method':spec['scaleReason'],'sourcePixelToStagePixel':factor,'catalogScale':scale,'canvas':qc['canvas']['width'],'perFrameScale':False,**({'calibration':spec['calibration']}if 'calibration'in spec else {})},
            'reviewProvenance':{'qc':f'{HERE.relative_to(ROOT).as_posix()}/{spec["id"]}-qc.json','bodyQC':spec['bodyQC'],'sourceFrameCount':count,'reorderingIsNotRedrawing':True}}

def main():
    p=argparse.ArgumentParser();p.add_argument('--id');p.add_argument('--images',action='store_true');p.add_argument('--integrate',action='store_true');p.add_argument('--check',action='store_true');args=p.parse_args()
    if args.check and args.images:raise ValueError('--check never writes images')
    manifest=read(HERE/'manifest.json');specs=[s for s in manifest['sources']if not args.id or s['id']==args.id]
    if args.id and not specs:raise ValueError('requested source not registered')
    if len({s['id']for s in manifest['sources']})!=len(manifest['sources']):raise ValueError('duplicate source IDs')
    path=ROOT/'animation/candidates.json';before=path.read_bytes();catalog=json.loads(before);verify_baseline(catalog);old=copy.deepcopy(catalog['clips']);additions=[]
    for spec in specs:
        qc=inspect(spec,args.images);out=HERE/f'{spec["id"]}-qc.json'
        if args.check:
            if read(out)!=qc:raise ValueError('QC stale: '+spec['id'])
        else:write_json(out,qc)
        if args.integrate and spec['status']=='candidate-ready':
            item=candidate(spec,qc,catalog);existing=[c for c in catalog['clips']if c['id']==item['id']]
            if existing and existing!=[item]:
                snapshot=read(confined(spec['calibrationBefore']))if spec.get('calibrationBefore')else None
                if (not snapshot or snapshot['candidate']!=existing[0] or item['version']!=existing[0]['version']+1
                        or item['sha256']!=existing[0]['sha256'] or item['frameRegions']!=existing[0]['frameRegions']):raise ValueError('existing candidate differs; explicit pinned calibration version required')
                if args.check:raise ValueError('explicit calibration not yet integrated')
                catalog['clips'][catalog['clips'].index(existing[0])]=item
            if not existing:
                if args.check:raise ValueError('ready candidate is missing')
                catalog['clips'].append(item)
            additions.append(item)
    if args.integrate and not args.check:
        if path.read_bytes()!=before:raise ValueError('catalog concurrently changed')
        verify_baseline(catalog)
        if catalog['clips']!=old:
            catalog['updatedAt']='2026-10-12';path.write_bytes((json.dumps(catalog,ensure_ascii=False,indent=2)+'\n').replace('\n','\r\n').encode('utf-8'))
        write_json(HERE/'catalog-integration.json',{'schemaVersion':1,'artApproval':False,'manifestSha256':sha(HERE/'manifest.json'),
                   'mainCatalogSha256':sha(ROOT/'animation/catalog.json'),'candidateCount':len(catalog['clips']),'candidateFrames':sum(c['frameCount']for c in catalog['clips']),
                   'processedSourceIDs':[s['id']for s in specs],'integratedCandidateIDs':[c['id']for c in additions]})
    print(json.dumps({'processed':len(specs),'ready':len(additions),'candidateCount':len(catalog['clips']),'candidateFrames':sum(c['frameCount']for c in catalog['clips'])}))
if __name__=='__main__':main()
