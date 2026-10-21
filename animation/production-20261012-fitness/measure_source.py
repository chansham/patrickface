"""Recompute only source-specific, visually reviewed eye/foot search windows.

The JSON config must pin a PNG and contour SHA and describe every source frame.
Occluded anatomy is explicit null. The script never edits source images/scales.
"""
from pathlib import Path
import argparse,hashlib,json,math,sys
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
EVIDENCE_DIR=ROOT/'output/body-landmarks-20261012-fitness'
sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import connected_components,validate_regions
from audit_body_scale import measure_face,rim_point
KEYS=('faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx')
def digest(data):return hashlib.sha256(data).hexdigest()
def parts_at(a,roi,kind,minimum):
    x0,y0,x1,y1=roi
    if not(0<=x0<x1<=a.shape[1] and 0<=y0<y1<=a.shape[0]):raise ValueError('ROI outside source')
    crop=a[y0:y1,x0:x1].astype(int);red,green,blue,alpha=crop.transpose(2,0,1)
    if kind=='eye':
        light=np.minimum(np.minimum(red,green),blue);spread=np.maximum(np.maximum(red,green),blue)-light
        mask=(light>=205)&(spread<=24)&(alpha>=200)
    else:mask=(red>160)&(green>75)&(blue>70)&(red-green>25)&(red-blue>20)&(abs(green-blue)<65)&(alpha>=128)
    _,components=connected_components(mask)
    return sorted([[x+x0,y+y0,xx+x0,yy+y0] for part in components if part['pixelCount']>=minimum
                   for x,y,xx,yy in [part['bounds']]],key=lambda b:b[0])
def measure(config):
    source=config['source'];source_raw=(ROOT/source['path']).read_bytes();regions_raw=(ROOT/config['regions']['path']).read_bytes()
    if digest(source_raw)!=source['sha256'] or digest(regions_raw)!=config['regions']['sha256']:raise ValueError('source or contour SHA drift')
    im=Image.open(ROOT/source['path']).convert('RGBA');a=np.array(im);regions=json.loads(regions_raw)
    if regions['source']!=source or list(im.size)!=[source['width'],source['height']]:raise ValueError('source geometry drift')
    if len(config['frames'])!=len(regions['frames']):raise ValueError('every source frame needs a review row')
    coverage=validate_regions(regions,a[:,:,3]);frames=[]
    for i,(review,region) in enumerate(zip(config['frames'],regions['frames'])):
        if review['sourceFrame']!=i+1:raise ValueError('review order must be complete one-based source order')
        row={'sourceFrame':i+1,**dict.fromkeys(KEYS),'anchorSource':region['anchorSource']}
        if review.get('footROI'):
            roi=review['footROI'];feet=parts_at(a,roi,'foot',review.get('footMinimumPixels',100))
            if len(feet)!=review.get('visibleFootCount',2):raise ValueError(f'frame {i+1}: bare feet ambiguous {feet}')
            if any(b[0]<=roi[0] or b[1]<=roi[1] or b[2]>=roi[2] or b[3]>=roi[3] for b in feet):raise ValueError(f'frame {i+1}: foot fill reaches ROI boundary')
            row.update(footROI=roi,visibleFootPinkFillBounds=feet,visibleFootBaselineY=sum(b[3]-1 for b in feet)/len(feet))
        else:row['footUnavailableReason']=review['footUnavailableReason']
        if review.get('eyeROI'):
            roi=review['eyeROI'];boxes=parts_at(a,roi,'eye',review.get('eyeMinimumPixels',70))
            if review.get('eyeUpperYCutoff') is not None:boxes=[b for b in boxes if b[1]<review['eyeUpperYCutoff']]
            if len(boxes)!=2:raise ValueError(f'frame {i+1}: eye whites ambiguous {boxes}')
            if any(b[0]<=roi[0] or b[1]<=roi[1] or b[2]>=roi[2] or b[3]>=roi[3] for b in boxes):raise ValueError(f'frame {i+1}: eye white reaches ROI boundary')
            points=[rim_point(b).tolist() for b in boxes];mid=[sum(p[j] for p in points)/2 for j in (0,1)]
            row.update(eyeROI=roi,eyeWhiteBounds=boxes,eyeLowerRimPoints=points,eyeMidpoint=mid,eyeLowerRimSeparationPx=math.dist(*points))
            if review.get('faceWidthUnavailableReason'):row['faceWidthUnavailableReason']=review['faceWidthUnavailableReason']
            else:
                face=measure_face(a,boxes,None)
                if 'faceWidth' not in face:raise ValueError(f'frame {i+1}: face not reliable; inspect before marking explicit unknown')
                row.update(faceWidthPx=face['faceWidth'],faceCaliperPoints=face['faceCaliperPoints'])
            if 'visibleFootBaselineY' in row:
                foot=[mid[0],row['visibleFootBaselineY']]
                if foot[1]<=mid[1]:raise ValueError('foot baseline must be below eye line')
                row.update(footSourcePoint=foot,eyeToFootPoints=[mid,foot],eyeLineToFootPx=foot[1]-mid[1])
        else:
            reason=review['eyeUnavailableReason'];row.update(eyeUnavailableReason=reason,unavailableReason=reason,
              faceWidthUnavailableReason=review.get('faceWidthUnavailableReason','眼下緣基準不可見，因此臉部截線未知。'),
              footUnavailableReason='沒有可見眼下緣基準，眼足距未知；不以眼皮或鄰格估算。')
        if review.get('measurementCaveat'):row['measurementCaveat']=review['measurementCaveat']
        if review.get('faceReviewROI'):row['faceReviewROI']=review['faceReviewROI']
        frames.append(row)
    return im,regions,coverage,frames
def evidence(config,im,frames):
    columns=config.get('evidenceColumns',4);rows=math.ceil(len(frames)/columns);w,h=400,320
    out=EVIDENCE_DIR;out.mkdir(parents=True,exist_ok=True)
    faces=Image.new('RGB',(columns*w,rows*h),'#202127');fd=ImageDraw.Draw(faces)
    feet=Image.new('RGB',(columns*w,rows*230),'#202127');td=ImageDraw.Draw(feet)
    full=Image.new('RGBA',im.size,'#292933');full.alpha_composite(im);draw=ImageDraw.Draw(full);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',15)
    for i,row in enumerate(frames):
        review=config['frames'][i];roi=review.get('faceReviewROI') or review.get('eyeROI')
        if roi:
            mx,my=row.get('eyeMidpoint') or [(roi[0]+roi[2])/2,(roi[1]+roi[3])/2]
            box=review.get('faceReviewROI') or [round(mx-90),round(my-85),round(mx+90),round(my+55)]
            crop=Image.new('RGBA',(box[2]-box[0],box[3]-box[1]),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB')
            scale=min(370/crop.width,270/crop.height);crop=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
            for key,color in [('eyeLowerRimPoints','#54c6ff'),('faceCaliperPoints','#ff7bc4')]:
                if key not in row:continue
                points=row[key];mapped=[((p[0]-box[0])*scale,(p[1]-box[1])*scale) for p in points];cd.line(mapped,fill=color,width=2)
                for x,y in mapped:cd.ellipse((x-3,y-3,x+3,y+3),fill=color)
                draw.line([tuple(p) for p in points],fill=color,width=2)
            faces.paste(crop,(i%columns*w+15,i//columns*h+35))
        label=f'#{i+1:02d} '+(f'face {row["faceWidthPx"]:.2f}px' if row['faceWidthPx'] is not None else 'FACE UNKNOWN')
        fd.text((i%columns*w+15,i//columns*h+10),label,font=font,fill='white')
        if 'eyeToFootPoints' in row:draw.line([tuple(p) for p in row['eyeToFootPoints']],fill='#8fe5a1',width=2)
        if row.get('footROI'):
            box=row['footROI'];crop=Image.new('RGBA',(box[2]-box[0],box[3]-box[1]),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB')
            scale=min(380/crop.width,180/crop.height);crop=crop.resize((round(crop.width*scale),round(crop.height*scale)),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
            for b in row['visibleFootPinkFillBounds']:cd.rectangle([(b[0]-box[0])*scale,(b[1]-box[1])*scale,(b[2]-box[0])*scale,(b[3]-box[1])*scale],outline='#8fe5a1',width=2)
            yy=(row['visibleFootBaselineY']-box[1])*scale;cd.line([(0,yy),(crop.width,yy)],fill='#f8db73',width=2)
            feet.paste(crop,(i%columns*w+10,i//columns*230+36))
        td.text((i%columns*w+12,i//columns*230+10),f'#{i+1:02d} '+('bare foot fill' if row.get('footROI') else 'FOOT UNKNOWN'),font=font,fill='white')
    stem=config['asset'];faces.save(out/f'{stem}-face-calipers.png');feet.save(out/f'{stem}-feet-calipers.png');full.convert('RGB').save(out/f'{stem}-full-calipers.png')
def run(config_path,check=False):
    raw=config_path.read_bytes();config=json.loads(raw);im,regions,coverage,frames=measure(config)
    first_last={};spread={}
    for key in KEYS:
        before,after=frames[0][key],frames[-1][key];values=[r[key] for r in frames if r[key] is not None]
        first_last[key]={'first':before,'last':after,'changePercent':None if before is None or after is None else(after/before-1)*100}
        spread[key]=None if not values else(max(values)/min(values)-1)*100
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'reviewRequired':True,'frameIndexBasis':'one-based source reading order',
      'source':config['source'],'regions':config['regions'],'canvas':regions['canvas'],'coverage':coverage,'sourceUnchanged':True,
      'reviewConfiguration':{'path':config_path.relative_to(ROOT).as_posix(),'sha256':digest(raw)},'frames':frames,'firstLast':first_last,'wholeClipSpread':spread,
      'edgeSamplingUncertaintySourcePixels':2,'limitations':config['limitations'],'visualFindings':config['visualFindings']}
    payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';out=HERE/f'{config["asset"]}-body-qc.json'
    if check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('source body QC stale')
    else:out.write_text(payload,encoding='utf-8');evidence(config,im,frames)
    print(json.dumps({'asset':config['asset'],'first':{k:frames[0][k] for k in KEYS},'firstLast':first_last,'spread':spread},ensure_ascii=False))
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('config');p.add_argument('--check',action='store_true');args=p.parse_args();run(ROOT/args.config,args.check)
