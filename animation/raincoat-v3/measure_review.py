"""Source-specific anatomical inspection; no editing, cropping or scaling of art.

Diagnostic crops/lines are written only as evidence, never playback assets.
Source/contour identities are pinned independently from the candidate catalog.
"""
from pathlib import Path
import argparse, hashlib, json, math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import validate_regions, connected_components
from audit_body_scale import rim_point, measure_face
SOURCE='animation/raincoat-v3/atlas-generated.png'
SHA='e3fdb977617c6a73718a6bb12b31d27be1e1a737a5ccba4304c39417d2ff2e74'
REGIONS='animation/raincoat-v3/regions-v1.json'
REGIONS_SHA='8eeb5a8722d024941f54cf801333418d99f8eb67af2ac6c9e6d5c17d8273fb71'
OUT=ROOT/'animation/production-20261012-wardrobe'
EVIDENCE=ROOT/'output/body-landmarks-20261012'
def digest(data):return hashlib.sha256(data).hexdigest()
def measure():
    data=(ROOT/SOURCE).read_bytes();rb=(ROOT/REGIONS).read_bytes()
    if digest(data)!=SHA or digest(rb)!=REGIONS_SHA:raise ValueError('reviewed source/contour changed')
    regions=json.loads(rb);im=Image.open(ROOT/SOURCE).convert('RGBA');a=np.array(im)
    if regions['source']!={'path':SOURCE,'sha256':SHA,'width':1086,'height':1448}:raise ValueError('contour source identity changed')
    coverage=validate_regions(regions,a[:,:,3]);frames=[]
    for i,region in enumerate(regions['frames']):
        ox,oy=(i%3)*362,(i//3)*362
        # All twelve drawings were inspected: #11 is half-lidded, not closed.
        # This bounded face-only ROI excludes the hood, drawstrings and umbrella.
        eye_roi=[ox+175,oy+118,ox+255,oy+188]
        x0,y0,x1,y1=eye_roi;crop=a[y0:y1,x0:x1].astype(int);red,green,blue,alpha=crop.transpose(2,0,1)
        mask=(np.minimum(np.minimum(red,green),blue)>=205)&(np.maximum(np.maximum(red,green),blue)-np.minimum(np.minimum(red,green),blue)<=24)&(alpha>=200)
        _,parts=connected_components(mask);parts=[c for c in parts if c['pixelCount']>=70]
        boxes=sorted([[x+x0,y+y0,xx+x0,yy+y0] for c in parts for x,y,xx,yy in [c['bounds']]],key=lambda b:b[0])
        if len(boxes)!=2:raise ValueError(f'frame {i+1}: eye whites ambiguous {boxes}')
        points=[rim_point(b).tolist() for b in boxes];face=measure_face(a,boxes,None)
        if 'faceWidth' not in face:raise ValueError(f'frame {i+1}: face section unavailable')
        # The two bare feet below the shorts are visible in every drawing.
        # A separate bounded skin mask excludes sleeves/hands and all clothing.
        foot_roi=[ox+140,oy+310,ox+285,oy+360]
        x0,y0,x1,y1=foot_roi;crop=a[y0:y1,x0:x1].astype(int);red,green,blue,alpha=crop.transpose(2,0,1)
        _,parts=connected_components((red>160)&(green>75)&(blue>70)&(red-green>25)&(red-blue>20)&(abs(green-blue)<65)&(alpha>=128))
        parts=[c for c in parts if c['pixelCount']>=100]
        feet=sorted([[x+x0,y+y0,xx+x0,yy+y0] for c in parts for x,y,xx,yy in [c['bounds']]],key=lambda b:b[0])
        if len(feet)!=2:raise ValueError(f'frame {i+1}: two bare feet ambiguous {feet}')
        mid=face['eyeMidpoint'];foot=sum(b[3]-1 for b in feet)/2;end=[mid[0],foot]
        frames.append({'sourceFrame':i+1,'eyeROI':eye_roi,'footROI':foot_roi,'eyeWhiteBounds':boxes,
         'faceWidthPx':face['faceWidth'],'faceCaliperPoints':face['faceCaliperPoints'],'eyeLowerRimPoints':points,
         'eyeLowerRimSeparationPx':math.dist(*points),'eyeLineToFootPx':foot-mid[1],
         'eyeMidpoint':mid,'visibleFootPinkFillBounds':feet,'visibleFootBaselineY':foot,
         'footSourcePoint':end,'eyeToFootPoints':[mid,end],'anchorSource':region['anchorSource'],
         'comparisonGroup':'looking-up' if i in [1,5] else ('half-lidded' if i==10 else ('wide-smile-looking-hand' if i==6 else 'open-neutral-standing'))})
    return im,regions,coverage,frames
def evidence(im,frames):
    EVIDENCE.mkdir(parents=True,exist_ok=True);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
    sheet=Image.new('RGB',(1600,900),(24,25,30));d=ImageDraw.Draw(sheet)
    footsheet=Image.new('RGB',(1600,660),(24,25,30));fd=ImageDraw.Draw(footsheet)
    overlay=Image.new('RGBA',im.size,'#292933');overlay.alpha_composite(im);od=ImageDraw.Draw(overlay)
    for i,row in enumerate(frames):
        mx,my=row['eyeMidpoint'];crop_box=[int(mx-92),int(my-90),int(mx+92),int(my+38)]
        crop=Image.new('RGBA',(184,128),'#292933');crop.alpha_composite(im.crop(crop_box));crop=crop.convert('RGB').resize((368,256),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
        for key,color in [('eyeLowerRimPoints','#54c6ff'),('faceCaliperPoints','#ff7bc4')]:
            points=row[key];mapped=[((x-crop_box[0])*2,(y-crop_box[1])*2) for x,y in points];cd.line(mapped,fill=color,width=2)
            for x,y in mapped:cd.ellipse((x-3,y-3,x+3,y+3),fill=color)
            od.line([tuple(p) for p in points],fill=color,width=2)
        od.line([tuple(p) for p in row['eyeToFootPoints']],fill='#8fe5a1',width=2)
        x,y=i%4*400,i//4*300;sheet.paste(crop,(x+16,y+35));d.text((x+16,y+8),f'#{i+1:02d} face {row["faceWidthPx"]:.2f}px  eyes {row["eyeLowerRimSeparationPx"]:.2f}px',font=font,fill='white')
        roi=row['footROI'];box=[roi[0]-6,roi[1]-10,roi[2]+6,roi[3]+2];crop=Image.new('RGBA',(box[2]-box[0],box[3]-box[1]),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB').resize(((box[2]-box[0])*2,(box[3]-box[1])*2),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
        for foot in row['visibleFootPinkFillBounds']:cd.rectangle([(foot[0]-box[0])*2,(foot[1]-box[1])*2,(foot[2]-box[0])*2,(foot[3]-box[1])*2],outline='#8fe5a1',width=2)
        line=(row['visibleFootBaselineY']-box[1])*2;cd.line([(0,line),(crop.width,line)],fill='#f8db73',width=2)
        x,y=i%4*400,i//4*220;footsheet.paste(crop,(x+35,y+45));fd.text((x+16,y+8),f'#{i+1:02d} two bare feet / no shoes',font=font,fill='white')
    sheet.save(EVIDENCE/'raincoat-v3-face-calipers.png');footsheet.save(EVIDENCE/'raincoat-v3-feet-calipers.png');overlay.convert('RGB').save(EVIDENCE/'raincoat-v3-full-calipers.png')
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
    im,regions,coverage,frames=measure();metrics=['faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx']
    old=json.loads((ROOT/'animation/production-20261012-raincoat/raincoat-v1-qc.json').read_text(encoding='utf-8-sig'))
    old_sha=digest((ROOT/'animation/production-20261012-raincoat/raincoat-v1-qc.json').read_bytes())
    if old['source']['sha256']!='755d73b3e23149a1c82498f9103be1b7a3f80b42214a70890b7d44d08181f42b':raise ValueError('original standing reference changed')
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'reviewRequired':True,'frameIndexBasis':'one-based source reading order',
      'source':regions['source'],'regions':{'path':REGIONS,'sha256':REGIONS_SHA},'canvas':regions['canvas'],'coverage':coverage,
      'sourceUnchanged':True,'frames':frames,'edgeSamplingUncertaintySourcePixels':2,
      'originalStandingReference':{'path':'animation/production-20261012-raincoat/raincoat-v1-qc.json','sha256':old_sha,'sourceSha256':old['source']['sha256']},
      'firstLast':{key:{'first':frames[0][key],'last':frames[-1][key],'changePercent':(frames[-1][key]/frames[0][key]-1)*100} for key in metrics},
      'wholeClipSpread':{key:(max(f[key] for f in frames)/min(f[key] for f in frames)-1)*100 for key in metrics},
      'firstFrameComparedWithOldSourcePixels':{key:{'old':old['frames'][0][key],'new':frames[0][key],'ratio':frames[0][key]/old['frames'][0][key]} for key in metrics},
      'comparisonWarning':'Two PNGs have different drawing sizes; source-pixel ratios are not on-watch size. Compare after each whole-clip scale is fixed; never fit individual frames.',
      'methods':['獨立看12格原畫後限制眼白ROI；第11格半睜眼仍有兩個可見眼白，不當閉眼。',
        '粉色臉横截跟隨眼白下緣方向；眼距不是瞳孔距，受表情與注視方向影響。',
        '兩隻可見裸腳粉色填色下緣平均作真足基線，不是衣服／傘／輪廓anchor。',
        '眼中線垂直投影至真足水平基線；投影x上不必真的有腳。',
        '所有PNG畫素與regions不變；量測不調倍率或批准動畫。'],
      'visualFindings':[{'sourceFrames':[3,4],'message':'原讀序第3格手已抬至肩旁，第4格又回腰前；不得照原順序宣稱平順。'},
        {'sourceFrames':[2,4,5,3,6],'message':'重排抬手仍有目光上看／正視／上看的變換；重排只減少大幅手勢回退，不等於補足中間原畫。'},
        {'sourceFrames':[6,7,8],'message':'高舉手與大笑、收回半高度之間仍缺真正中間表情和手勢。'},
        {'sourceFrames':[10,11,12],'message':'收手後半睜眼不是完整眨眼；首末未構成已驗收無縫循環。'}]}
    out=OUT/'raincoat-v3-body-qc.json';payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n'
    if args.check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('body evidence changed')
    else:OUT.mkdir(parents=True,exist_ok=True);out.write_text(payload,encoding='utf-8');evidence(im,frames)
    print(json.dumps({'first':{k:frames[0][k] for k in metrics},'firstLast':report['firstLast'],'wholeClipSpread':report['wholeClipSpread'],'frames':len(frames)},ensure_ascii=False))
if __name__=='__main__':main()
