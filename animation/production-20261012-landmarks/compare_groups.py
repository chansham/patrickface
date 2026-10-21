"""Summarize inspected pose groups separately; never re-scale an animation."""
import json
import hashlib
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]
data=json.loads((HERE/'landmarks-reviewed.json').read_text(encoding='utf-8'))
groups={
 'exercise-repair-20261006':{'name':'坐姿、放鬆半睜眼','frames':[0,5,6,7,8,10,11,13,14,15]},
 'running-first-20261006':{'name':'回到接近正面、放鬆半睜眼','frames':[0,11,13,15]},
 'charging-cozy-20261007':{'name':'接近相同傾角，排除傾頭及被電池遮臉','frames':[0,1,2,3,4,5,9,10,11]},
}
out={'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,
 'landmarksPath':'animation/production-20261012-landmarks/landmarks-reviewed.json','landmarksSha256':hashlib.sha256((HERE/'landmarks-reviewed.json').read_bytes()).hexdigest(),
 'limits':'相近姿勢分組不是骨架重建；眼白下緣仍受表情與注視影響，不能把全段極差直接稱為縮放錯誤。邊緣取點不確定度約2 source px；小於此級別的首末差異不作精確改善宣稱。', 'clips':[]}
for source in data['sources']:
 group=groups[source['id']];frames=source['frames'];item={'id':source['id'],'sourceSha256':source['sourceSha256'],'regionsSha256':source['regionsSha256'],
 'group':group['name'],'sourceFramesOneBased':[i+1 for i in group['frames']],'metrics':{}}
 for key in ['faceWidth','eyeSeparation','eyeToFoot']:
  records=[{'sourceFrameOneBased':i+1,'value':frames[i]['source'][key]} for i in group['frames'] if frames[i]['source'][key] is not None]
  first,last=frames[0]['source'][key],frames[-1]['source'][key]
  item['metrics'][key]={'first':first,'last':last,'endpointDeltaPercent':(last/first-1)*100 if first is not None and last is not None else None,
   'groupSourceValues':records,'groupSpreadPercent':(max(r['value'] for r in records)/min(r['value'] for r in records)-1)*100 if len(records)>1 else None}
 out['clips'].append(item)
(HERE/'pose-group-comparison.json').write_text(json.dumps(out,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
exercise=data['sources'][0]
source=Image.open(ROOT/exercise['sourcePath']).convert('RGB')
sheet=Image.new('RGB',(1536,650),(24,25,30));d=ImageDraw.Draw(sheet)
font=ImageFont.truetype('C:/Windows/Fonts/arial.ttf',18)
for col,index in enumerate([0,5,11]):
 ox,oy=(index%4)*384,(index//4)*256
 # Fixed crop, fixed 2x size, fixed cell top. Do not normalize the eyes or the feet.
 crop=source.crop((ox+70,oy,ox+310,oy+256)).resize((480,512),Image.Resampling.NEAREST);draw=ImageDraw.Draw(crop)
 s=exercise['frames'][index]['source'];eye=s['eyeMidpoint'][1]-oy;foot=s['footBaselineY']-oy
 draw.line([(0,eye*2),(479,eye*2)],fill='#44dbff',width=2)
 draw.line([(0,foot*2),(479,foot*2)],fill='#72ff93',width=2)
 sheet.paste(crop,(col*512+16,85))
 d.text((col*512+16,10),f'Frame {index+1} | same source scale',font=font,fill='white')
 d.text((col*512+16,34),f'Eye line y={eye:g}; true foot y={foot:g}',font=font,fill='#44dbff')
 d.text((col*512+16,58),f'Eye-to-foot {s["eyeToFoot"]:g}px; face {s["faceWidth"]:.2f}px',font=font,fill='#ff8fc8')
evidence=ROOT/'output/body-landmarks-20261012/exercise-body-comparison.png';sheet.save(evidence)
print(json.dumps({c['id']:{k:{'endpoint':v['endpointDeltaPercent'],'groupSpread':v['groupSpreadPercent']} for k,v in c['metrics'].items()} for c in out['clips']},ensure_ascii=False))
