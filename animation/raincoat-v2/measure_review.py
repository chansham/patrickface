"""Source-pinned raincoat QA. Never edit source pixels or fit frames separately."""
from pathlib import Path
import argparse,hashlib,json,math,sys
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import validate_regions,connected_components
from audit_body_scale import rim_point,measure_face
SOURCE='animation/raincoat-v2/atlas-generated.png'
SHA='dc4cb4f2d66bb7d6cc56291003214a911e51f8f75bccd83cbcc42d68ebc08410'
OUT=ROOT/'animation/production-20261012-raincoat'
EYES={1:[[166,191,203,251],[204,189,238,250]],2:[[551,189,588,245],[587,186,619,240]],
      3:[[932,192,969,247],[969,189,1000,242]],4:[[1304,192,1340,248],[1340,188,1373,243]],
      5:[[180,667,216,725],[216,664,248,720]],7:[[930,669,965,727],[966,667,998,724]],
      8:[[1293,669,1330,729],[1330,667,1364,727]]}
PLAY=[0,1,2,3,4,5,6,7]

def make_report():
    raw=(ROOT/SOURCE).read_bytes()
    if hashlib.sha256(raw).hexdigest()!=SHA:raise ValueError('reviewed source identity changed')
    p=(ROOT/SOURCE).with_name('regions-v1.json');rb=p.read_bytes();r=json.loads(rb)
    a=np.array(Image.open(ROOT/SOURCE).convert('RGBA'));alpha=a[:,:,3]
    if r['source']!={'path':SOURCE,'sha256':SHA,'width':1536,'height':1024}:raise ValueError('regions source identity changed')
    coverage=validate_regions(r,alpha);frames=[]
    overlay=Image.new('RGBA',(1536,1024),'#17131e');overlay.alpha_composite(Image.fromarray(a));draw=ImageDraw.Draw(overlay)
    for i,f in enumerate(r['frames'],1):
        l,t,rr,b=f['diagnostics']['coreBounds']
        row={'sourceFrame':i,'coreBounds':[l,t,rr,b],'sourceBounds':f['sourceBounds'],'anchorSource':f['anchorSource'],'translation':f['translation'],
             'faceWidthPx':None,'eyeLowerRimSeparationPx':None,'eyeLineToFootPx':None,
             'coreWidthPx':rr-l,'coreHeightPx':b-t}
        if i in EYES:
            boxes=EYES[i];points=[rim_point(p).tolist() for p in boxes];mid=[sum(p[k] for p in points)/2 for k in (0,1)]
            face=measure_face(a,boxes,None)
            row.update(eyeWhiteBounds=boxes,eyeLowerRimPoints=points,eyeLowerRimSeparationPx=math.dist(*points))
            if 'faceWidth' in face:row.update(faceWidthPx=face['faceWidth'],faceCaliperPoints=face['faceCaliperPoints'])
            else:row['faceWidthUnavailableReason']=face.get('unavailable')
            # Feet are bare and separately visible. Measure pink fill below the shorts,
            # not the lower-silhouette renderer anchor or umbrella height.
            fy=b-47;crop=a[fy:b,l:rr].astype(int);red,green,blue,aa=crop.transpose(2,0,1)
            _,parts=connected_components((red>160)&(green>75)&(blue>70)&(red-green>25)&(red-blue>20)&(abs(green-blue)<65)&(aa>=128))
            parts=[c for c in parts if c['pixelCount']>300]
            if len(parts)!=2:raise ValueError(f'frame{i}: reviewed two bare-foot fills not recovered')
            bounds=[[x+l,y+fy,x1+l,y1+fy] for c in parts for x,y,x1,y1 in [c['bounds']]]
            foot=sum(v[3]-1 for v in bounds)/2
            row.update(visibleFootPinkFillBounds=bounds,visibleFootBaselineY=foot,footSourcePoint=[mid[0],foot],eyeToFootPoints=[mid,[mid[0],foot]],eyeLineToFootPx=foot-mid[1])
            for box in boxes:draw.rectangle(box,outline='#ff726b',width=2)
            for key,color in [('eyeLowerRimPoints','#54c6ff'),('faceCaliperPoints','#a5f07f'),('eyeToFootPoints','#f9c55f')]:
                if key in row:draw.line([tuple(p) for p in row[key]],fill=color,width=2)
            for box in bounds:draw.rectangle(box,outline='#f9c55f',width=1)
        else:
            row.update(eyeUnavailableReason='第6來源格雙眼閉合；不捏造眼白尺規。',faceWidthUnavailableReason='閉眼沒有本方法的共同眼下緣截線。',footUnavailableReason='可見腳部，但缺眼下緣基準，眼足距保留null。')
        frames.append(row)
    edge=np.zeros(alpha.shape,bool);edge[[0,-1],:]=True;edge[:,[0,-1]]=True
    delta={key:{'first':frames[0][key],'last':frames[-1][key],'changePercent':(frames[-1][key]/frames[0][key]-1)*100} for key in ['faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx']}
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','frameIndexBasis':'one-based source reading order','artApproved':False,'artApproval':False,
            'status':'seated-alternative-animation-pending-review','source':r['source'],'sourceUnchanged':True,'regions':{'path':p.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(rb).hexdigest()},
            'canvas':r['canvas'],'coverage':coverage,'frames':frames,'reference':{'manualEyeBoundsBySourceFrame':EYES,'sourceSha256':SHA},
            'playback':{'frameIndices':PLAY,'originalFrames':8,'reorderingIsNotRedrawing':True},
            'summary':{'sourceFrames':8,'measuredFaceFrames':sum(f['faceWidthPx'] is not None for f in frames),'measuredEyeFrames':7,'measuredEyeActualFootFrames':7,
                       'transparentPixels':int((alpha==0).sum()),'alphaOnePixels':int((alpha==1).sum()),'sourceEdgeAlphaPixels':int(((alpha>0)&edge).sum()),'sourceEdgeStrongPixels':int(((alpha>=128)&edge).sum())},
            'newFirstLastFrame':delta,'scaleProposal':{'catalogScale':1.3040865384615383,'sourcePixelToStagePixel':1.55,'perFrameScale':False,
                'reason':'坐姿短柄傘另作選項；首格臉部呈現比主睡衣小約2.66%，整段固定倍率兼顧四版式時間區。不能用坐姿取代使用者偏好的站姿。'},
            'methods':['獨立核對7格眼白component座標；第6格閉眼留空。眼下緣距不是瞳孔距或頭圍。',
                       '粉色臉截線沿眼下緣方向；正面與抬眼表情可能改變尺規，不當臨床或骨架尺寸。',
                       '可見雙腳粉色填色下緣平均作真足底姿勢代理，與輪廓落位anchor分開。',
                       '所有非零alpha pixel原樣保留、一次歸屬；整段同560方畫布與同倍率，沒有逐格縮放或抹平姿勢。',
                       '約2來源pixel的填色邊緣誤差；雨傘、雨衣外框不當人物本體尺規。'],
            'visualFindings':[{'sourceFrames':[1,2,3,4,5,6,7,8],'kind':'sequence','message':'新坐姿原畫已按抬眼→抬手→攤手→閉眼→收手順序繪製；按原序播放，不補造幀。'},
                              {'sourceFrames':[4,5],'kind':'remaining','message':'舉高手臂降至攤手的幅度較大，中間動作仍缺。'},
                              {'sourceFrames':[5,6,7],'kind':'remaining','message':'笑→閉眼不滿→微笑轉換快；沒有完整連貫雨滴/雨傘事件因果。'},
                              {'sourceFrames':[1,8],'kind':'remaining','message':'首末臉截線、眼距與眼足距有原畫變化，不是無縫循環。'},
                              {'sourceFrames':[1,2,3,4,5,6,7,8],'kind':'source-noise','message':'來源PNG無任何alpha像素觸邊；極淡零碎噪點原样保留。傘面遮住一部分頭尖是原畫遮擋，不能推算完整頭高。'}],
            'normalSpeedReview':'see-separate-runtime-review'}
    return report,overlay

def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();report,overlay=make_report()
    payload=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8');out=OUT/'raincoat-v2-qc.json'
    if args.check:
        if out.read_bytes()!=payload:raise ValueError('QC report stale')
    else:
        OUT.mkdir(parents=True,exist_ok=True);out.write_bytes(payload)
        q=ROOT/'output/playwright/raincoat-20261012/v2';q.mkdir(parents=True,exist_ok=True);overlay.convert('RGB').save(q/'source-semantic-landmarks.png')
    print(json.dumps({'path':out.relative_to(ROOT).as_posix(),'summary':report['summary'],'firstLast':report['newFirstLastFrame']},ensure_ascii=False))
if __name__=='__main__':main()
