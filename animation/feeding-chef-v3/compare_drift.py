"""Read-only pixel comparison: integer registration, never scale or write PNGs."""
from pathlib import Path
import hashlib
import json

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


def load(name):
    directory=ROOT/"animation"/name
    raw=(directory/"atlas-generated.png").read_bytes()
    regions=json.loads((directory/"regions-v1.json").read_bytes())
    if hashlib.sha256(raw).hexdigest()!=regions["source"]["sha256"]:
        raise ValueError("source/regions SHA mismatch")
    return np.array(Image.open(directory/"atlas-generated.png").convert("RGBA")),regions


def registered_pixels(rgba,frame,bounds):
    left,top,right,bottom=bounds
    result=np.zeros((bottom-top,right-left,4),dtype=np.uint8)
    ax,ay=frame["anchorSource"]
    for row in frame["rows"]:
        y=row[0]
        for x0,x1 in zip(row[1::2],row[2::2]):
            result[y-ay-top,x0-ax-left:x1-ax-left]=rgba[y,x0:x1]
    return result


def compare(old_name,new_name):
    old_rgba,old=load(old_name);new_rgba,new=load(new_name)
    if len(old["frames"])!=len(new["frames"]):
        raise ValueError("frame counts differ")
    result=[]
    for index,(f,g) in enumerate(zip(old["frames"],new["frames"])):
        rects=[]
        for frame in (f,g):
            x,y,w,h=frame["sourceBounds"];ax,ay=frame["anchorSource"]
            rects.append([x-ax,y-ay,x+w-ax,y+h-ay])
        bounds=[min(r[0] for r in rects),min(r[1] for r in rects),
                max(r[2] for r in rects),max(r[3] for r in rects)]
        a,b=[registered_pixels(rgba,frame,bounds) for rgba,frame in ((old_rgba,f),(new_rgba,g))]
        nonzero=(a[:,:,3]>0)|(b[:,:,3]>0)
        strong=(a[:,:,3]>=128)|(b[:,:,3]>=128)
        intersection=(a[:,:,3]>=128)&(b[:,:,3]>=128)
        # Premultiplied colors plus alpha quantify visible change on black/white,
        # excluding hidden RGB at alpha0. This is not an aesthetic approval test.
        av=a.astype(float);bv=b.astype(float)
        ap=av[:,:,:3]*av[:,:,3:4]/255;bp=bv[:,:,:3]*bv[:,:,3:4]/255
        black_error=np.abs(ap-bp).max(2)
        white_error=np.abs(ap+255-av[:,:,3:4]-(bp+255-bv[:,:,3:4])).max(2)
        error=np.maximum(black_error,white_error)
        fb=f["diagnostics"]["coreBounds"];gb=g["diagnostics"]["coreBounds"]
        result.append({"sourceFrame":index+1,
                       "coreWidthChangePx":(gb[2]-gb[0])-(fb[2]-fb[0]),
                       "coreHeightChangePx":(gb[3]-gb[1])-(fb[3]-fb[1]),
                       "sourceAnchorChangePx":[g["anchorSource"][j]-f["anchorSource"][j] for j in range(2)],
                       "registeredStrongMaskIoU":float(intersection.sum()/strong.sum()),
                       "registeredNonzeroUnionPixels":int(nonzero.sum()),
                       "registeredExactRgbaMismatchPixels":int((np.any(a!=b,axis=2)&nonzero).sum()),
                       "registeredCompositeErrorMean8bit":float(error[strong].mean()),
                       "registeredCompositeErrorOver8PixelPercent":float(((error>8)&strong).sum()/strong.sum()*100),
                       "identicalRgbaAfterIntegerRegistration":bool(np.array_equal(a,b))})
    return {"previousSource":old["source"],"currentSource":new["source"],
            "registration":"1:1 source pixels, each frame integer translated by existing region anchor; no scaling or warping",
            "limitation":"Registration isolates residual artwork/pixel differences, not same raw atlas coordinates. RGB differences at alpha0 are ignored. A nonzero error is evidence of changed pixels, not proof every change is perceptually harmful.",
            "frames":result}


if __name__=="__main__":
    print(json.dumps(compare("feeding-chef-v2","feeding-chef-v3"),ensure_ascii=False,indent=2))
