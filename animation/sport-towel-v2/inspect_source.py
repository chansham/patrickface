"""Read-only artwork inspection; writes only QA composites under output/."""
from pathlib import Path
import hashlib,json
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[2]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'output/playwright/wardrobe-20261012/sport-towel-v2'
OUT.mkdir(parents=True,exist_ok=True)
im=Image.open(HERE/'atlas-generated.png').convert('RGBA'); a=np.array(im)
r=json.loads((HERE/'regions-v1.json').read_bytes()); n=r['canvas']['width']
for color,name in [('black','source-black'),('white','source-white')]:
    bg=Image.new('RGBA',im.size,color);bg.alpha_composite(im);bg.convert('RGB').save(OUT/(name+'.png'))
frames=[]
for i,f in enumerate(r['frames']):
    out=np.zeros((n,n,4),dtype=np.uint8);dx,dy=f['translation']
    for row in f['rows']:
        y=row[0]
        for x0,x1 in zip(row[1::2],row[2::2]):out[y+dy,x0+dx:x1+dx]=a[y,x0:x1]
    frames.append(Image.fromarray(out))
    frame=Image.new('RGBA',(n,n),'#17131e');frame.alpha_composite(frames[-1]);frame.convert('RGB').save(OUT/f'frame-{i+1:02}.png')
sheet=Image.new('RGB',(4*n,2*(n+35)),'#17131e');d=ImageDraw.Draw(sheet)
for p,i in enumerate([0,1,2,3,4,5,6,7]):
    x,y=(p%4)*n,(p//4)*(n+35);sheet.paste(frames[i],(x,y),frames[i]);d.text((x+12,y+n+5),f'play {p+1} / source {i+1}',fill='white')
sheet.save(OUT/'contour-play-order.png')
print(json.dumps({'sourceSHA':hashlib.sha256((HERE/'atlas-generated.png').read_bytes()).hexdigest(),'regionsSHA':hashlib.sha256((HERE/'regions-v1.json').read_bytes()).hexdigest(),'alpha0':int((a[:,:,3]==0).sum()),'alpha1':int((a[:,:,3]==1).sum()),'frames':[{'sourceFrame':i+1,'coreBounds':f['diagnostics']['coreBounds'],'anchorSource':f['anchorSource'],'sourceBounds':f['sourceBounds']}for i,f in enumerate(r['frames'])]},indent=2))
