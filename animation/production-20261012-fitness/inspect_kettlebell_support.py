"""Select visible bare-foot support pixels, excluding the lower central kettlebell."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw,ImageFont
from measure_source import parts_at,ROOT,HERE
PATH='animation/fitness-kettlebell-v2/atlas-generated.png'
SHA='b5469c61ae4968a102c7d64b140890956ffe9a5c478109522d815cb94d204711'
ROIS=[[110,370,395,438],[530,370,810,438],[965,355,1250,438],[1407,350,1697,438],
      [110,775,395,850],[530,775,810,850],[965,775,1250,850],[1407,771,1697,850]]
raw=(ROOT/PATH).read_bytes()
if hashlib.sha256(raw).hexdigest()!=SHA:raise ValueError('source changed')
im=Image.open(ROOT/PATH).convert('RGBA');a=np.array(im);rows=[]
sheet=Image.new('RGB',(1600,600),'#202127');d=ImageDraw.Draw(sheet);font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',16)
for i,roi in enumerate(ROIS):
    feet=parts_at(a,roi,'foot',100)
    if len(feet)!=2:raise ValueError('bare foot pair ambiguous')
    record={'sourceFrame':i+1,'footROI':roi,'feet':[],'anchorNotAnatomicalCaliper':True}
    box=roi;crop=Image.new('RGBA',(box[2]-box[0],box[3]-box[1]),'#292933');crop.alpha_composite(im.crop(box));crop=crop.convert('RGB')
    scale=380/crop.width;crop=crop.resize((380,round(crop.height*scale)),Image.Resampling.NEAREST);cd=ImageDraw.Draw(crop)
    for bounds in feet:
        x0,y0,x1,y1=bounds;mask=a[y0-8:y1+8,x0-8:x1+8,3]>=128;yy,xx=np.where(mask);bottom=int(yy.max()+y0-8)
        xs=np.where(a[bottom,x0-8:x1+8,3]>=128)[0]+x0-8;point=[int(xs[len(xs)//2]),bottom+1]
        if a[point[1]-1,point[0],3]<128:raise ValueError('support lacks visible source alpha')
        record['feet'].append({'pinkFillBounds':bounds,'supportPointBottomExclusive':point,'supportPixelAlpha':int(a[point[1]-1,point[0],3]),'thresholdAlpha':128})
        cd.rectangle([(x0-box[0])*scale,(y0-box[1])*scale,(x1-box[0])*scale,(y1-box[1])*scale],outline='#8fe5a1',width=2)
        px,py=(point[0]-box[0])*scale,(bottom-box[1])*scale;cd.line([(px-15,py),(px+15,py)],fill='#54c6ff',width=2);cd.ellipse((px-3,py-3,px+3,py+3),fill='#54c6ff')
    points=[f['supportPointBottomExclusive'] for f in record['feet']]
    record['suggestedSupportAnchor']=[sum(p[0] for p in points)/2,max(p[1] for p in points)]
    rows.append(record);x,y=i%4*400,i//4*300;sheet.paste(crop,(x+10,y+42));d.text((x+12,y+12),f'#{i+1:02d} bare foot support',font=font,fill='white')
report={'schemaVersion':1,'source':{'path':PATH,'sha256':SHA,'width':1774,'height':887},'frameIndexBasis':'one-based source order',
  'method':'visible bare pink feet selected separately; choose median x of strong-alpha bottom row per foot; Y exclusive',
  'limits':'支撐點用於整數平移落位，不等於人体尺規；人体眼足距另用粉色填色下緣。第1/8壺鈴更低，不使用壺鈴底。',
  'artApproval':False,'frames':rows}
(HERE/'kettlebell-foot-support-reviewed.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sheet.save(ROOT/'output/body-landmarks-20261012-fitness/kettlebell-v2-foot-support-proof.png')
print(json.dumps([{'frame':r['sourceFrame'],'feet':[f['supportPointBottomExclusive'] for f in r['feet']],'anchor':r['suggestedSupportAnchor']} for r in rows]))
