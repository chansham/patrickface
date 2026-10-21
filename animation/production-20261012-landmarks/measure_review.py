"""Read-only source-pinned anatomical evidence, never an asset repair or art approval.

Measure only reviewed visible landmarks; retain closed/occluded/side-pose unknowns.
Diagnostic PNGs are annotated evidence crops, never catalog artwork.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re
from collections import deque
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
EVIDENCE = ROOT / 'output' / 'body-landmarks-20261012'
SPECS = [
    dict(id='exercise-repair-20261006', name='exercise-v3', grid=[4,4],
         sha='0a3fdcd7fc489fb89457b76145ce3e249f2a401c3ffc0a1a566872cb7da1627f',
         regionsSha='60b52d9cf086221cfe3f30731b3665bd657d81096b69f8392377ddfd6edf13d5',
         eyeROI=[145,60,240,140], closed=[12], side=[], feet=True),
    dict(id='running-first-20261006', name='running-v1', grid=[4,4],
         sha='f00e4c9d0cce8bcd9a5cdac5f7f9f91228086ce6d835e928cf4b36c7b6f1a1e4',
         regionsSha='9e858752a4cf852e173a80a72510999e7daf64b48ea31325aa061fb82c6cc276',
         eyeROI=[100,82,240,155], closed=[12], side=list(range(2,11)), feet=False),
    dict(id='charging-cozy-20261007', name='charging-cozy-v2', grid=[3,4],
         sha='993feacbb4e57dc9acd393be690e3f96321bf543921c2ccb5b971cd617fae194',
         regionsSha='10bc3295dcb15b327365c1c0985e14d0da0c1a798a35822551e1da5074541e74',
         eyeROI=[120,105,255,185], closed=[7], side=[], feet=False),
]
METRICS = ['faceWidth','eyeSeparation','eyeToFoot']
def sha(data): return hashlib.sha256(data).hexdigest()
def read(path): return json.loads(path.read_text(encoding='utf-8-sig'))
def finite(p): return all(isinstance(v,(float,int)) and math.isfinite(v) for v in p)
def skin(pixel):
    r,g,b,a=pixel
    return a>=200 and r>=220 and 65<=g<=190 and 60<=b<=185 and r-g>=45 and -25<=g-b<=50
def white(pixel):
    r,g,b,a=pixel
    return a>=200 and min(r,g,b)>=208 and max(r,g,b)-min(r,g,b)<=24
def components(im, box, predicate):
    x0,y0,x1,y1=map(int,box); pixels=im.load()
    active={(x,y) for y in range(y0,y1) for x in range(x0,x1) if predicate(pixels[x,y])}
    result=[]
    while active:
        start=min(active,key=lambda p:(p[1],p[0])); active.remove(start); queue=deque([start]); points=[]
        while queue:
            x,y=queue.popleft(); points.append((x,y))
            for nxt in ((x-1,y),(x+1,y),(x,y-1),(x,y+1)):
                if nxt in active: active.remove(nxt); queue.append(nxt)
        if len(points)>=35:
            xs,ys=zip(*points); result.append({'size':len(points),'bounds':[min(xs),min(ys),max(xs)+1,max(ys)+1]})
    return sorted(result,key=lambda p:p['bounds'][0])
def pixel_point(im,p):
    x,y=map(lambda v:int(round(v)),p)
    return im.getpixel((x,y)) if 0<=x<im.width and 0<=y<im.height else (0,0,0,0)
def face_caliper(im, eyes):
    mid=[(eyes[0][j]+eyes[1][j])/2 for j in (0,1)]
    length=math.dist(*eyes); unit=[(eyes[1][j]-eyes[0][j])/length for j in (0,1)]
    # Continue through eye-outline crossings but reject all non-skin pixels.
    # Bounded head-line scan never includes a hand, hat or the full character box.
    ts=[i/4 for i in range(-560,561) if skin(pixel_point(im,[mid[j]+i/4*unit[j] for j in (0,1)]))]
    if not ts or min(ts)>-length/2 or max(ts)<length/2: raise ValueError('face section not found')
    return [[round(mid[j]+t*unit[j],2) for j in (0,1)] for t in (min(ts),max(ts))]
def measure(spec, clip):
    image_path=ROOT/clip['atlas']; data=image_path.read_bytes()
    if sha(data)!=spec['sha'] or clip['sha256']!=spec['sha']: raise ValueError('source changed')
    regions_path=ROOT/clip['frameRegions']['path']; regions_data=regions_path.read_bytes(); regions=json.loads(regions_data)
    if sha(regions_data)!=spec['regionsSha'] or clip['frameRegions']['sha256']!=spec['regionsSha'] or regions['source']['sha256']!=spec['sha']: raise ValueError('regions changed')
    im=Image.open(image_path).convert('RGBA'); cols,rows=spec['grid']; cw,ch=im.width/cols,im.height/rows
    frames=[]
    for i,region in enumerate(regions['frames']):
        ox,oy=round(i%cols*cw),round(i//cols*ch)
        roi=[spec['eyeROI'][j]+(ox if j%2==0 else oy) for j in range(4)]
        if spec['name']=='charging-cozy-v2': roi[3]=oy+[180,180,180,170,170,170,170,170,165,150,150,150][i]
        source={key:None for key in METRICS}
        source['eyeToFootUnavailableReason']=('跑步側身、屈膝和抬腳變化，不使用支撐輪廓基線假冒可比的人體身高。' if spec['name']=='running-v1' else '真腳被紫色拖鞋與褲裝遮擋，不使用鞋底作人體足底。')
        source.update(edgeSamplingUncertaintySourcePixels=2, eyeROI=roi)
        if i in spec['closed']:
            source.update(eyeSeparationUnavailableReason='閉眼，沒有兩個可見眼白下緣，不能用眼皮或前一格推估。',
                          faceWidthUnavailableReason='本尺規沿眼白下緣線取臉部橫截；閉眼沒有這條基準。',
                          eyeToFootUnavailableReason='閉眼，眼白下緣基準未知，因此眼足距維持未知。')
        else:
            blobs=components(im,roi,white)
            if len(blobs)!=2: raise ValueError(f'{spec["name"]} frame {i+1}: expected 2 eye whites, got {blobs}')
            boxes=[b['bounds'] for b in blobs]
            eyes=[[(b[0]+b[2]-1)/2,b[3]-1] for b in boxes]
            source.update(eyeWhiteBounds=boxes,eyeLowerRimPoints=eyes,
                          eyeSeparation=math.dist(*eyes), eyeMidpoint=[sum(p[j] for p in eyes)/2 for j in (0,1)])
            source['eyeMeasurementMethod']='兩個可見眼白連通區包圍盒的下緣中點；非瞳孔距，表情/朝向敏感。'
            if i in spec['side']:
                source['faceWidthUnavailableReason']='此格側轉或大幅傾斜，投影橫截不與正面臉寬混比；只記錄可見眼白間距。'
                source['comparisonGroup']='side-pose-eye-proxy-only'
            elif spec['name']=='charging-cozy-v2' and i==8:
                source['faceWidthUnavailableReason']='電池遮擋右側臉部在眼下緣延長線上的輪廓；可見粉色截段不是完整臉寬。'
                source['comparisonGroup']='occluded-face-eye-proxy-only'
            else:
                line=face_caliper(im,eyes)
                source.update(faceCaliperPoints=line,faceWidth=math.dist(*line),comparisonGroup='visible-face-section')
            if spec['feet']:
                # All exercise frames are seated barefoot. The right visible pink foot
                # is separate from shorts/dumbbell: inspect this bounded foot-only ROI.
                foot_box=[ox+205,oy+205,ox+273,oy+253]
                feet=components(im,foot_box,skin)
                if len(feet)!=1: raise ValueError(f'exercise {i+1}: foot component ambiguous {feet}')
                baseline=feet[0]['bounds'][3]-1
                mid=source['eyeMidpoint']; end=[mid[0],baseline]
                source.update(eyeToFoot=baseline-mid[1],eyeToFootPoints=[mid,end],footSourcePoint=end,
                              footBaselineY=baseline, visibleFootPinkFillBounds=[feet[0]['bounds']], footROI=foot_box,
                              footPointMeaning='眼中線向下投影至已覆核裸腳填色下緣的水平基線；該投影x並非實際腳掌位置。',
                              footBaselineMethod='逐格覆核右側可見裸腳粉色填色下緣；量測坐姿代理，不是站立身高，也不包含黑色描邊。')
                source.pop('eyeToFootUnavailableReason',None)
        frames.append({'sourceFrame':i,'actualUsed':True,'source':source,'flags':[]})
    return im,regions,frames
def draw_evidence(spec,im,frames):
    EVIDENCE.mkdir(parents=True,exist_ok=True)
    cols,rows=spec['grid']; cw,ch=im.width/cols,im.height/rows
    tile_w,tile_h=400,330; sheet=Image.new('RGB',(4*tile_w,math.ceil(len(frames)/4)*tile_h),(24,25,30)); draw=ImageDraw.Draw(sheet)
    font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
    for i,frame in enumerate(frames):
        source=frame['source']; roi=source['eyeROI']; ox,oy=round(i%cols*cw),round(i//cols*ch)
        center=source.get('eyeMidpoint',[(roi[0]+roi[2])/2,(roi[1]+roi[3])/2]); crop_box=[round(center[0]-94),round(center[1]-84),round(center[0]+94),round(center[1]+62)]
        crop=Image.new('RGBA',(188,146),(44,47,58,255)); crop.alpha_composite(im.crop(crop_box)); crop=crop.convert('RGB').resize((376,292),Image.Resampling.NEAREST)
        d=ImageDraw.Draw(crop)
        for key,color in [('eyeLowerRimPoints','#44dbff'),('faceCaliperPoints','#ff60ba')]:
            pts=source.get(key)
            if pts:
                mapped=[((p[0]-crop_box[0])*2,(p[1]-crop_box[1])*2) for p in pts]; d.line(mapped,fill=color,width=2)
                for x,y in mapped:d.ellipse([x-3,y-3,x+3,y+3],fill=color)
        x,y=i%4*tile_w,i//4*tile_h; sheet.paste(crop,(x+10,y+28)); text=f'{spec["name"]} #{i+1:02d}'
        if i in spec['closed']:text+=' CLOSED: UNKNOWN'
        elif i in spec['side']:text+=' SIDE: EYE ONLY'
        draw.text((x+10,y+6),text,font=font,fill='white')
    path=EVIDENCE/f'{spec["name"]}-face-calipers.png';sheet.save(path)
    if spec['feet']:
        sheet=Image.new('RGB',(4*tile_w,4*tile_h),(24,25,30));draw=ImageDraw.Draw(sheet)
        for i,frame in enumerate(frames):
            source=frame['source'];ox,oy=round(i%cols*cw),round(i//cols*ch)
            box=[ox+105,oy+175,ox+300,oy+254];crop=im.crop(box).convert('RGB').resize((390,158),Image.Resampling.NEAREST);d=ImageDraw.Draw(crop)
            if source.get('footBaselineY') is not None:
                y=(source['footBaselineY']-box[1])*2;d.line([(196,y),(340,y)],fill='#72ff93',width=2)
                roi=source['footROI'];d.rectangle([(roi[0]-box[0])*2,(roi[1]-box[1])*2,(roi[2]-box[0])*2,(roi[3]-box[1])*2],outline='#ffe38a',width=2)
            x,y=i%4*tile_w,i//4*tile_h;sheet.paste(crop,(x+5,y+60));draw.text((x+10,y+10),f'Exercise #{i+1:02d} visible bare right foot',font=font,fill='white')
        sheet.save(EVIDENCE/'exercise-v3-feet-calipers.png')
    return path
def build_audit(catalog, landmarks):
    player=(ROOT/'preview/player-core.js').read_bytes()
    match=re.search(r'export const STAGE = Object\.freeze\(\{([^}]+)\}\)',player.decode('utf-8-sig'))
    stage={k:float(v) for k,v in re.findall(r'(\w+)\s*:\s*([\d.]+)',match.group(1))}
    layouts=read(ROOT/'experience/layouts.json')
    target=[stage['x']+stage['size']*catalog['master']['anchorNormalized'][0],stage['y']+stage['size']*catalog['master']['anchorNormalized'][1]]
    clips=[]
    warnings={
      'exercise-repair-20261006':[
        '第4至7格手腕、拳頭與啞鈴交接仍需改稿；第5至6格表情轉換仍需確認。',
        '本輪新發現：即使只比坐姿放鬆半睜眼，第6格臉截面較首格窄，眼線至裸腳更長；該組臉寬與眼足距極差約15.3%。首末接近不能證明中段比例一致，需修原稿。',
        '眼足距僅為坐姿眼線至右侧可見裸腳的垂直代理，不代表站立身高；第13格閉眼未知。'],
      'running-first-20261006':[
        '第4→5、6→7、8→9、9→10格朝向跳變和第13至16格眼神轉換仍待修復。',
        '第3至11格側轉的可見眼距只供該姿勢核查，不與正面混算頭部縮放；全段跑步眼足距未知。'],
      'charging-cozy-20261007':[
        '第7→8、第9→10格傾頭銜接仍待修復；量測增加不代表動畫已平順。',
        '真足被拖鞋遮擋，12格眼足距未知；第8格閉眼，第9格電池擋住右臉，臉寬未知。']}
    for source_record in landmarks['sources']:
        clip=next(c for c in catalog['clips'] if c['id']==source_record['id'])
        regions=read(ROOT/source_record['regionsPath']);factor=stage['size']*clip['scale']/regions['canvas']['width'];frames=[]
        sequence=clip.get('frameIndices',list(range(clip['frameCount'])))
        for original in source_record['frames']:
            i=original['sourceFrame'];source=original['source'];region=regions['frames'][i]
            mapped={key:None if source[key] is None else source[key]*factor for key in METRICS}
            for key in ('eyeLowerRimPoints','faceCaliperPoints','eyeToFootPoints'):
                if key in source:mapped[key]=[[target[j]+(p[j]-region['anchorSource'][j])*factor for j in (0,1)] for p in source[key]]
            by_layout={}
            for layout in layouts['layouts']:
                scale,tx,ty=layout['characterTransform'];values={key:None if mapped[key] is None else mapped[key]*scale for key in METRICS}
                transformed={'logicalPixels':values,'cssPixelsAt200Width':{k:None if v is None else v*200/stage['width'] for k,v in values.items()}}
                for key in ('eyeLowerRimPoints','faceCaliperPoints','eyeToFootPoints'):
                    if key in mapped:transformed[key]=[[p[0]*scale+tx,p[1]*scale+ty] for p in mapped[key]]
                by_layout[layout['id']]=transformed
            frames.append({**original,'actualUsed':i in sequence,'stage':mapped,'layouts':by_layout,
                           'alignmentEvidence':{'anchorSource':region['anchorSource'],'notAnatomicalMeasurement':True}})
        clips.append({'id':clip['id'],'title':clip['title'],'catalog':'candidates','atlas':clip['atlas'],
                      'sourceSha256':clip['sha256'],'regionsSha256':clip['frameRegions']['sha256'],
                      'catalogScale':clip['scale'],'sourcePixelToStagePixel':factor,'sourceFrameCount':len(frames),'playbackFrameCount':clip['frameCount'],
                      'actualUsedSourceFrames':sorted(set(sequence)),'frameIndices':sequence,'referenceFrame':0,
                      'calibration':{'currentScale':clip['scale'],'reason':'只記錄目前整段固定倍率；沒有逐格縮放、補幀或畫素修改。'},
                      'measurements':{'unit':'px','labels':{'faceWidth':'可見眼下緣線臉部截面','eyeSeparation':'可見眼白下緣中點距離，非瞳孔距','eyeToFoot':'坐姿眼線至裸腳下緣垂直距離'},'reference':frames[0]},
                      'frames':frames,'flags':[{'code':f'visual-review-{i+1}','severity':'warning','message':message} for i,message in enumerate(warnings[clip['id']])],
                      'artApproval':False,'reviewRequired':True})
    all_frames=[f for c in clips for f in c['frames']]
    landmarks_path=HERE/'landmarks-reviewed.json'
    return {'schemaVersion':1,'generatedAt':'2026-10-12','artApproval':False,'reviewRequired':True,'frameIndexBasis':'zero-based',
      'method':'source-pinned-visible-eye-white-and-reviewed-skin-section-v1','coordinateSize':[stage['width'],stage['height']],
      'catalogPath':'animation/candidates.json','catalogSha256':sha((ROOT/'animation/candidates.json').read_bytes()),
      'layoutsSha256':sha((ROOT/'experience/layouts.json').read_bytes()),'playerCoreSha256':sha(player),'stageConstants':stage,
      'landmarksPath':landmarks_path.relative_to(ROOT).as_posix(),'landmarksSha256':sha(landmarks_path.read_bytes()),
      'sources':[{k:s[k] for k in ('sourcePath','sourceSha256','regionsPath','regionsSha256')} for s in landmarks['sources']],
      'clips':clips,'limitations':['41/44格至少有一項可见人体尺规，不等於44格完整身高已量妥。',
        '眼距受表情、眼白面積、朝向影響；臉寬為下緣線皮膚截面，不是頭部完整寬度。',
        '跑步側轉臉寬、閉眼尺線、被電池遮住的臉、被拖鞋遮住的腳維持未知。',
        '讀取同一份PNG的獨立放大尺線作視覺覆核；沒有改任何來源畫素、輪廓、倍率或播放格序。',
        '四版式數值為當時版式快照；頁面以當前版式投影來源座標。'],
      'totals':{'uniqueSources':3,'sourceFrames':len(all_frames),'clipVariants':3,
        'measuredSourceFrames':sum(any(f['source'][k] is not None for k in METRICS) for f in all_frames),
        'unmeasuredSourceFrames':sum(all(f['source'][k] is None for k in METRICS) for f in all_frames),
        'measuredSourceFramesByMetric':{k:sum(f['source'][k] is not None for f in all_frames) for k in METRICS}}}
def main():
    parser=argparse.ArgumentParser();parser.add_argument('--draft',action='store_true');parser.add_argument('--write',action='store_true');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    if not (args.draft or args.write or args.check):parser.error('choose --draft, --write, or --check')
    catalog=read(ROOT/'animation/candidates.json');result=[]
    for spec in SPECS:
        clip=next(c for c in catalog['clips'] if c['id']==spec['id']);im,regions,frames=measure(spec,clip)
        evidence=EVIDENCE/f'{spec["name"]}-face-calipers.png'
        if not args.check:draw_evidence(spec,im,frames)
        result.append(dict(id=spec['id'],sourcePath=clip['atlas'],sourceSha256=clip['sha256'],regionsPath=clip['frameRegions']['path'],regionsSha256=clip['frameRegions']['sha256'],frames=frames,evidence=evidence.relative_to(ROOT).as_posix()))
    landmarks={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,
      'visualReview':'Original atlases and all four enlarged caliper sheets inspected; cozy frame 9 face line excluded after occlusion was seen.',
      'method':'Reviewed source-specific eye ROIs and white connected components, then visible skin-section endpoints; all coordinates in original source pixels.',
      'uncertaintySourcePixels':2,'sources':result}
    path=HERE/('landmarks-draft.json' if args.draft else 'landmarks-reviewed.json')
    serialized=json.dumps(landmarks,ensure_ascii=False,indent=2)+'\n'
    if args.check:
        if path.read_text(encoding='utf-8')!=serialized:raise ValueError('measured landmarks differ from reviewed snapshot')
        audit=build_audit(catalog,landmarks);existing=read(HERE/'body-scale-audit.json')
        if audit!=existing:raise ValueError('audit projection differs from snapshot; inspect current catalog/layout changes before refreshing')
    else:
        path.write_text(serialized,encoding='utf-8')
        if args.write:(HERE/'body-scale-audit.json').write_text(json.dumps(build_audit(catalog,landmarks),ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({r['id']:{k:sum(f['source'][k] is not None for f in r['frames']) for k in METRICS} for r in result},ensure_ascii=False))
if __name__=='__main__':main()
