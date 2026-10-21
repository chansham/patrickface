"""Measure only this inspected sport/towel source; retain known art defects."""
from pathlib import Path
import argparse, hashlib, json, math, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFont
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import connected_components,validate_regions
from audit_body_scale import measure_face,rim_point
SOURCE='animation/sport-towel-v2/atlas-generated.png'
SHA='01e212bf5c64471fec5f6c836e88e54406803562da0f8e2a0eea4a2e9d1abead'
REGIONS='animation/sport-towel-v2/regions-v1.json'
REGIONS_SHA='87be718d717990969317c3b6ff964161c9ce3709c0fdb76d56bdf221cf1d787e'
OUT=ROOT/'animation/production-20261012-wardrobe';EVIDENCE=ROOT/'output/body-landmarks-20261012'
def digest(data):return hashlib.sha256(data).hexdigest()
def measure():
    raw=(ROOT/SOURCE).read_bytes();rb=(ROOT/REGIONS).read_bytes()
    if digest(raw)!=SHA or digest(rb)!=REGIONS_SHA:raise ValueError('sport source/contour drift')
    regions=json.loads(rb);im=Image.open(ROOT/SOURCE).convert('RGBA');a=np.array(im)
    if regions['source']!={'path':SOURCE,'sha256':SHA,'width':1536,'height':1024}:raise ValueError('sport contour identity drift')
    coverage=validate_regions(regions,a[:,:,3]);frames=[]
    for i,region in enumerate(regions['frames']):
        ox,oy=i%4*384,i//4*512
        row={'sourceFrame':i+1,'faceWidthPx':None,'eyeLowerRimSeparationPx':None,'eyeLineToFootPx':None,'anchorSource':region['anchorSource']}
        # Only exposed bare feet below shorts. Drawstring, towel and fists excluded.
        foot_roi=[ox+90,oy+415,ox+290,oy+483];x0,y0,x1,y1=foot_roi
        crop=a[y0:y1,x0:x1].astype(int);red,green,blue,alpha=crop.transpose(2,0,1)
        _,parts=connected_components((red>160)&(green>75)&(blue>70)&(red-green>25)&(red-blue>20)&(abs(green-blue)<65)&(alpha>=128))
        parts=[p for p in parts if p['pixelCount']>=250]
        feet=sorted([[x+x0,y+y0,xx+x0,yy+y0] for p in parts for x,y,xx,yy in [p['bounds']]],key=lambda b:b[0])
        if len(feet)!=2:raise ValueError(f'sport {i+1}: bare feet not resolved {feet}')
        foot=sum(b[3]-1 for b in feet)/2
        row.update(footROI=foot_roi,visibleFootPinkFillBounds=feet,visibleFootBaselineY=foot)
        eye_roi=[ox+150,oy+90,ox+245,oy+(175 if i<4 else 152)];row['eyeROI']=eye_roi
        if i==4:
            row.update(unavailableReason='第5來源格雙眼完全閉合，沒有可見眼白下緣；臉截線、眼距與眼足距全部未知。',
                       faceWidthUnavailableReason='完全閉眼，這個方法的眼下緣臉截線不存在。',
                       eyeUnavailableReason='完全閉眼，不把已修復的粉色眼皮當眼白。',
                       footUnavailableReason='真裸腳可見，但眼下緣基準不存在，因此眼足距未知。')
        else:
            x0,y0,x1,y1=eye_roi;crop=a[y0:y1,x0:x1].astype(int);red,green,blue,alpha=crop.transpose(2,0,1)
            light=np.minimum(np.minimum(red,green),blue);spread=np.maximum(np.maximum(red,green),blue)-light
            _,parts=connected_components((light>=205)&(spread<=24)&(alpha>=200))
            # The cheek towel can enter the lower ROI: true eye whites begin above
            # the source-specific upper cutoff (never silently select towel white).
            cutoff=150 if i<4 else 130
            parts=[p for p in parts if p['pixelCount']>=70 and p['bounds'][1]+y0<oy+cutoff]
            boxes=sorted([[x+x0,y+y0,xx+x0,yy+y0] for p in parts for x,y,xx,yy in [p['bounds']]],key=lambda b:b[0])
            if len(boxes)!=2:raise ValueError(f'sport {i+1}: eye whites ambiguous {boxes}')
            points=[rim_point(b).tolist() for b in boxes];face=measure_face(a,boxes,None)
            mid=[sum(p[j] for p in points)/2 for j in (0,1)]
            row.update(eyeWhiteBounds=boxes,eyeLowerRimPoints=points,eyeLowerRimSeparationPx=math.dist(*points),eyeMidpoint=mid)
            if i in [2,3,5]:row['faceWidthUnavailableReason']='毛巾貼住左臉，眼下緣延長線上的完整皮膚邊界受遮擋，不把短截面充當完整臉寬。'
            elif 'faceWidth' not in face:row['faceWidthUnavailableReason']='無法可靠分離可見臉部兩侧邊界，臉寬留空。'
            else:row.update(faceWidthPx=face['faceWidth'],faceCaliperPoints=face['faceCaliperPoints'])
            end=[mid[0],foot];row.update(footSourcePoint=end,eyeToFootPoints=[mid,end],eyeLineToFootPx=foot-mid[1])
            if i==0:row['measurementCaveat']='第1格半睜眼，只取下方可見白眼白；本次重新量測新PNG，不沿用v1眼白座標。'
        frames.append(row)
    return im,regions,coverage,frames
def evidence(im,frames):
    EVIDENCE.mkdir(parents=True,exist_ok=True);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
    faces=Image.new('RGB',(1600,640),(24,25,30));fd=ImageDraw.Draw(faces);feet_sheet=Image.new('RGB',(1600,520),(24,25,30));td=ImageDraw.Draw(feet_sheet)
    full=Image.new('RGBA',im.size,'#292933');full.alpha_composite(im);d=ImageDraw.Draw(full)
    for i,row in enumerate(frames):
        roi=row['eyeROI'];mx,my=row.get('eyeMidpoint') or [(roi[0]+roi[2])/2,(roi[1]+roi[3])/2]
        box=[round(mx-90),round(my-85),round(mx+90),round(my+55)]
        crop=Image.new('RGBA',(180,140),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB').resize((360,280),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
        for key,color in [('eyeLowerRimPoints','#54c6ff'),('faceCaliperPoints','#ff7bc4')]:
            if key not in row:continue
            pts=row[key];mapped=[((p[0]-box[0])*2,(p[1]-box[1])*2) for p in pts];cd.line(mapped,fill=color,width=2)
            for x,y in mapped:cd.ellipse((x-3,y-3,x+3,y+3),fill=color)
            d.line([tuple(p) for p in pts],fill=color,width=2)
        if 'eyeToFootPoints' in row:d.line([tuple(p) for p in row['eyeToFootPoints']],fill='#8fe5a1',width=2)
        x,y=i%4*400,i//4*320;faces.paste(crop,(x+20,y+32));fd.text((x+15,y+8),f'#{i+1:02d} '+('CLOSED: UNKNOWN' if i==4 else (f'face {row["faceWidthPx"]:.2f}px' if row['faceWidthPx'] is not None else 'FACE OCCLUDED / EYES VISIBLE')),font=font,fill='white')
        roi=row['footROI'];box=[roi[0]-1,roi[1]-1,roi[2]+1,roi[3]+1];crop=Image.new('RGBA',(202,70),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB').resize((384,133),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
        for b in row['visibleFootPinkFillBounds']:cd.rectangle([(b[0]-box[0])*384/202,(b[1]-box[1])*133/70,(b[2]-box[0])*384/202,(b[3]-box[1])*133/70],outline='#8fe5a1',width=2)
        py=(row['visibleFootBaselineY']-box[1])*133/70;cd.line([(0,py),(384,py)],fill='#f8db73',width=2)
        x,y=i%4*400,i//4*260;feet_sheet.paste(crop,(x+8,y+60));td.text((x+15,y+12),f'#{i+1:02d} bare foot fill baseline',font=font,fill='white')
    faces.save(EVIDENCE/'sport-towel-v2-face-calipers.png');feet_sheet.save(EVIDENCE/'sport-towel-v2-feet-calipers.png');full.convert('RGB').save(EVIDENCE/'sport-towel-v2-full-calipers.png')
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();im,regions,coverage,frames=measure();keys=['faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx']
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'reviewRequired':True,'frameIndexBasis':'one-based source reading order',
      'source':regions['source'],'regions':{'path':REGIONS,'sha256':REGIONS_SHA},'canvas':regions['canvas'],'coverage':coverage,'sourceUnchanged':True,
      'frames':frames,'edgeSamplingUncertaintySourcePixels':2,
      'firstLast':{k:{'first':frames[0][k],'last':frames[-1][k],'changePercent':(frames[-1][k]/frames[0][k]-1)*100} for k in keys},
      'wholeClipSpread':{k:(max(r[k] for r in frames if r[k] is not None)/min(r[k] for r in frames if r[k] is not None)-1)*100 for k in keys},
      'limitations':['第1/5格眼皮已在這份原圖恢復粉色；第1半睜白眼白仍可量，第5全閉未知。所有格的數字與尺線重新從v2讀取。',
        '人物高瘦與雨衣比例不同，臉寬匹配不代表整體高度匹配；不得逐格縮放。',
        '毛巾在第3/4/6格遮擋左側臉截線，這三格臉寬未知；可見裸腳獨立於衣服/毛巾/輪廓anchor。',
        '臉截面、眼距與眼足距為表情和姿勢代理，非真正骨架/完整身高。'],
      'visualFindings':[{'sourceFrames':[1,5],'message':'重新實看v2原圖，原紫色眼皮已變為粉色；此修復不等於其他動畫問題通過。'},
        {'sourceFrames':[3,4],'message':'兩格擦臉姿勢近似，不能當作已補足有意義中間动作。'},
        {'sourceFrames':[6,7],'message':'毛巾手從臉邊下降到胸前仍跳，缺中間收手姿勢。'},
        {'sourceFrames':[1,8],'message':'首格疲累半睜伸舌，末格精神微笑，非無縫待機循環。'}]}
    out=OUT/'sport-towel-v2-body-qc.json';payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n'
    if args.check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('sport body evidence changed')
    else:OUT.mkdir(parents=True,exist_ok=True);out.write_text(payload,encoding='utf-8');evidence(im,frames)
    print(json.dumps({'first':{k:frames[0][k] for k in keys},'firstLast':report['firstLast'],'spread':report['wholeClipSpread']},ensure_ascii=False))
if __name__=='__main__':main()
