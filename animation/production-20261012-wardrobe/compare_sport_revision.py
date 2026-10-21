"""Inspect source-pinned v1/v2 pixels and independent calipers; do not edit art."""
from pathlib import Path
import argparse,hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
SOURCES=[('animation/sport-towel-v1/atlas-generated.png','ddb99d07d571841537f107fd1aa35c35515ef73c1d3c7c3323de214fc7fab2ae'),
         ('animation/sport-towel-v2/atlas-generated.png','01e212bf5c64471fec5f6c836e88e54406803562da0f8e2a0eea4a2e9d1abead')]
ROIS=[(1,[145,105,235,177],[[169,126,178,135],[201,126,210,135]]),
      (5,[148,600,242,680],[[173,631,182,640],[205,631,214,640]])]
def digest(x):return hashlib.sha256(x).hexdigest()
def build():
    images=[];arrays=[]
    for p,sha in SOURCES:
        if digest((ROOT/p).read_bytes())!=sha:raise ValueError('sport comparison source changed')
        im=Image.open(ROOT/p).convert('RGBA');images.append(im);arrays.append(np.array(im))
    a,b=arrays
    if a.shape!=b.shape:raise ValueError('source geometry changed; cannot pixel-compare')
    changed=np.any(a!=b,axis=2);visible=(a[:,:,3]>0)|(b[:,:,3]>0);roi_mask=np.zeros(changed.shape,dtype=bool)
    crops=[]
    for source_frame,box,patches in ROIS:
        x0,y0,x1,y1=box;roi_mask[y0:y1,x0:x1]=True
        crops.append({'sourceFrame':source_frame,'sourceROI':box,'changedRGBApixelCount':int(changed[y0:y1,x0:x1].sum()),
          'reviewedEyelidInteriorSamples':[{'sourceBounds':p,'v1MedianRGB':np.median(a[p[1]:p[3],p[0]:p[2],:3],axis=(0,1)).tolist(),
            'v2MedianRGB':np.median(b[p[1]:p[3],p[0]:p[2],:3],axis=(0,1)).tolist()} for p in patches]})
    qc=[];refs=[]
    for v in (1,2):
        path=HERE/f'sport-towel-v{v}-body-qc.json';raw=path.read_bytes();qc.append(json.loads(raw));refs.append({'path':path.relative_to(ROOT).as_posix(),'sha256':digest(raw)})
    rows=[]
    for before,after in zip(qc[0]['frames'],qc[1]['frames']):
        metrics={}
        for k in ('faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx'):
            x,y=before[k],after[k];metrics[k]={'v1':x,'v2':y,'differenceSourcePixels':None if x is None or y is None else y-x}
        rows.append({'sourceFrame':after['sourceFrame'],'metrics':metrics})
    report={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'sourceReports':refs,
      'sources':[{'path':p,'sha256':s} for p,s in SOURCES],
      'pixelComparison':{'width':a.shape[1],'height':a.shape[0],'changedRGBApixelCount':int(changed.sum()),
        'changedPixelsWithinEitherVisibleSource':int((changed&visible).sum()),
        'changedVisiblePixelsOutsideReviewedEyeROIs':int((changed&visible&~roi_mask).sum()),
        'meaning':'逐像素對比不是圖像配準；生成修訂會改動其它部位，不能宣稱只改了眼皮或借用舊量測。'},
      'eyelidEvidence':crops,'independentlyRemeasuredFrames':rows,
      'findings':['第1和5格已逐格放大覆核，眼皮由紫色改為粉色；眼白沒有塗成皮膚色。',
        '第5格完全閉眼仍沒有三項尺規；第3/4/6格毛巾遮擋左臉截線仍不量臉寬。',
        '保留瘦長體形、擦臉至收手缺過渡及首末表情不同的待修事項，眼皮修正不等於整段通過。']}
    return report,images
def evidence(images):
    out=ROOT/'output/body-landmarks-20261012';out.mkdir(parents=True,exist_ok=True)
    sheet=Image.new('RGB',(1000,680),'#202127');draw=ImageDraw.Draw(sheet);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
    for row,(source_frame,box,patches) in enumerate(ROIS):
        for col,im in enumerate(images):
            crop=Image.new('RGBA',(box[2]-box[0],box[3]-box[1]),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB').resize(((box[2]-box[0])*4,(box[3]-box[1])*4),Image.Resampling.NEAREST)
            cd=ImageDraw.Draw(crop)
            for p in patches:cd.rectangle([(p[0]-box[0])*4,(p[1]-box[1])*4,(p[2]-box[0])*4,(p[3]-box[1])*4],outline='#70dcff',width=2)
            x,y=col*500+20,row*340+28;sheet.paste(crop,(x,y));draw.text((x,y-23),f'source #{source_frame} / v{col+1} / eyelid sample',font=font,fill='white')
    sheet.save(out/'sport-towel-v1-v2-eyelid-proof.png')
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();report,images=build()
    payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';out=HERE/'sport-towel-v1-v2-comparison.json'
    if args.check:
        if out.read_text(encoding='utf-8')!=payload:raise ValueError('sport revision evidence stale')
    else:out.write_text(payload,encoding='utf-8');evidence(images)
    print(json.dumps(report['pixelComparison'],ensure_ascii=False))
if __name__=='__main__':main()
