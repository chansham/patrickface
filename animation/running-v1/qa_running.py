"""Source-pinned running artwork QA. Changes metadata/QA artifacts, never PNG pixels.

The shared builder supplies ownership masks. The separately reviewed registration
uses a fixed column origin for x and the visible lower supporting foot for y.
No head fit, per-frame scale, or seated exercise support-band policy is used.
"""
from copy import deepcopy
import hashlib
import json
import math
from pathlib import Path
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from audit_body_scale import measure_face
from build_frame_regions import validate_regions, apply_reviewed_support_policy, REVIEWED_SUPPORT_POLICIES

HERE = Path(__file__).resolve().parent
SOURCE_SHA = "f00e4c9d0cce8bcd9a5cdac5f7f9f91228086ce6d835e928cf4b36c7b6f1a1e4"
SUPPORT_Y = [301,297,300,305,608,608,609,612,914,914,909,911,1222,1222,1222,1222]
EYES = {0:[[141,104,163,124],[165,106,191,127]],
        15:[[1083,1023,1106,1042],[1107,1024,1133,1044]]}
NOTES = [
    "中性半睜站姿；雙臂雙腳完整。", "屈膝握拳預備；眉形較嚴肅。",
    "抬膝、另一腳支撐；雙臂交換。", "前伸腳、後抬腳；面向畫面右側。",
    "抬膝、另一腳支撐；面向畫面左側。", "前伸腳、後抬腳；仍偏左。",
    "再次抬膝；面向畫面右側。", "再次前伸腳；仍偏右。",
    "抬膝、面向畫面左側。", "前伸腳、突然轉回右側。",
    "屈膝收步，手臂回落。", "半睜眼、收手站穩。",
    "閉眼吐氣；氣團不是第三隻手，眼部尺規不可量。",
    "恢復半睜中性表情。", "突然睜大雙眼；結尾額外表情跳變待修。",
    "恢復半睜；接近首格但並非完全相同原畫。",
]

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def relative(path): return path.relative_to(ROOT).as_posix()
def save_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
def range_stats(values):
    return {"values":values,"range":max(values)-min(values),
            "maximumAdjacentChange":max(abs(b-a) for a,b in zip(values,values[1:])),
            "firstToLast":values[-1]-values[0]}

def render(frame, rgba, n):
    output=np.zeros((n,n,4),dtype=np.uint8)
    dx,dy=frame["translation"]
    for row in frame["rows"]:
        y=row[0]
        for x0,x1 in zip(row[1::2],row[2::2]):
            output[y+dy,x0+dx:x1+dx]=rgba[y,x0:x1]
    return output

def bounds_at_threshold(rendered, threshold):
    y,x=np.where(rendered[:,:,3]>=threshold)
    return [int(x.min()),int(y.min()),int(x.max())+1,int(y.max())+1]

def core_head_midline(frame, rgba):
    _,top,_,_=frame["diagnostics"]["coreBounds"]
    midlines=[]
    for row in frame["rows"]:
        y=row[0]
        if not top<=y<top+60: continue
        xx=[]
        for x0,x1 in zip(row[1::2],row[2::2]):
            xx.extend((np.flatnonzero(rgba[y,x0:x1,3]>=128)+x0).tolist())
        if xx: midlines.append((min(xx)+max(xx)+1)/2)
    return float(np.median(midlines))

def run():
    source=HERE/"atlas-generated.png"
    assert sha(source)==SOURCE_SHA, "unreviewed source; no registration inferred"
    rgba=np.asarray(Image.open(source).convert("RGBA"))
    assert rgba.shape==(1254,1254,4)
    default_path=HERE/"regions-default-lower15.json"
    metadata_path=HERE/"regions-v1.json"
    if not default_path.exists():
        raw=json.loads(metadata_path.read_text(encoding="utf-8-sig"))
        assert not raw["diagnostics"].get("supportAnchorPolicy"), "default backup unavailable"
        default_path.write_bytes(metadata_path.read_bytes())
    old=json.loads(default_path.read_text(encoding="utf-8-sig"))
    assert old["source"]["sha256"]==SOURCE_SHA
    data=deepcopy(old)
    n=data["canvas"]["width"]
    target=data["canvas"]["anchorPixels"]
    policy=REVIEWED_SUPPORT_POLICIES[("animation/running-v1/atlas-generated.png",SOURCE_SHA)]
    apply_reviewed_support_policy(data,rgba[:,:,3],policy)
    mask_result=validate_regions(data,rgba[:,:,3])
    metadata_path.write_text(json.dumps(data,ensure_ascii=False,separators=(",",":"))+"\n",encoding="utf-8")

    frames=[]; renders=[]; old_head=[]; new_head=[]
    for index,frame in enumerate(data["frames"]):
        rendered=render(frame,rgba,n); renders.append(rendered)
        # Each owned source run round-trips exactly in unscaled RGBA.
        dx,dy=frame["translation"]
        for row in frame["rows"]:
            for x0,x1 in zip(row[1::2],row[2::2]):
                assert np.array_equal(rendered[row[0]+dy,x0+dx:x1+dx],rgba[row[0],x0:x1])
        metric=measure_face(rgba,EYES[index],None) if index in EYES else None
        if metric: assert "unavailable" not in metric
        head=core_head_midline(frame,rgba)
        old_head.append(head-old["frames"][index]["anchorSource"][0]);new_head.append(head-frame["anchorSource"][0])
        frames.append({"sourceFrame":index+1,"sourceBounds":frame["sourceBounds"],
            "coreBounds":frame["diagnostics"]["coreBounds"],
            "renderedAlpha128Bounds":bounds_at_threshold(rendered,128),
            "renderedAlpha16Bounds":bounds_at_threshold(rendered,16),
            "anchorSource":frame["anchorSource"],"translation":frame["translation"],
            "visualNote":NOTES[index],"visibleArms":2,"visibleLegs":2,
            "faceWidthPx":metric["faceWidth"] if metric else None,
            "eyeLowerRimSeparationPx":metric["eyeSeparation"] if metric else None,
            "eyeLowerRimPoints":metric["eyeLowerRimPoints"] if metric else None,
            "faceCaliperPoints":metric["faceCaliperPoints"] if metric else None,
            "eyeWhiteBounds":metric["eyeWhiteBounds"] if metric else None,
            "eyeLineToFootPx":None,
            "metricNote":"Manually identified neutral half-open eyes; approximately 2 source px edge uncertainty." if metric else "Not used as a comparable neutral-body measurement: changed pose/expression or closed eyes. No inferred anatomy.",
            "coreSourceEdgeTouches":frame["diagnostics"]["coreSourceEdgeTouches"]})

    catalog=json.loads((ROOT/"animation/catalog.json").read_text(encoding="utf-8-sig"))
    exercise=next(c for c in catalog["clips"] if c["id"]=="exercise")
    exercise_meta=json.loads((ROOT/exercise["frameRegions"]["path"]).read_text())
    old_audit=json.loads((ROOT/"animation/production-20261006-scale/body-scale-audit.json").read_text())
    exercise_audit=next(s for s in old_audit["sources"] if s["sourcePath"]==exercise["atlas"])
    assert sha(ROOT/exercise["atlas"])==exercise_audit["sourceSha256"]
    old_face=exercise_audit["frames"][0]["source"]["faceWidth"]
    old_factor=332.8*exercise["scale"]/exercise_meta["canvas"]["width"]
    equal_scale=old_face*old_factor/frames[0]["faceWidthPx"]*n/332.8
    recommended_scale=2.0
    layouts_path=ROOT/"experience/layouts.json"
    layouts=json.loads(layouts_path.read_text())["layouts"]
    dom_path=ROOT/"output/playwright/20261006-scale-layouts/report.json"
    dom=json.loads(dom_path.read_text())
    zones=dom["cases"][0]["typography"]
    layout_tests=[]
    for label,scale in [("same-face-width-as-seated-exercise",equal_scale),("recommended-fixed-whole-clip",recommended_scale)]:
        factor=665.6*scale/n
        entries=[]
        for layout in layouts:
            k,tx,ty=layout["characterTransform"]
            protected=next(z["zones"] for z in zones if z["layout"]==layout["id"] and z["timeFormat"]=="24")
            for index,frame in enumerate(data["frames"]):
                b=frames[index]["renderedAlpha128Bounds"]
                rect=[(416+(b[0]-target[0])*factor)*k+tx,(893.632+(b[1]-target[1])*factor)*k+ty,
                      (416+(b[2]-target[0])*factor)*k+tx,(893.632+(b[3]-target[1])*factor)*k+ty]
                collisions=[z["kind"] for z in protected if not(rect[2]<=z["bounds"][0] or rect[0]>=z["bounds"][2] or rect[3]<=z["bounds"][1] or rect[1]>=z["bounds"][3])]
                outside=not(0<=rect[0]<rect[2]<=832 and 0<=rect[1]<rect[3]<=992)
                entries.append({"sourceFrame":index+1,"layout":layout["id"],"alpha128StageBounds":rect,"collisions":collisions,"outsideStage":outside})
        layout_tests.append({"label":label,"scale":scale,"tested":len(entries),
            "collisionCount":sum(bool(e["collisions"]) for e in entries),
            "outsideCount":sum(e["outsideStage"] for e in entries),"entries":entries})
    recommended=layout_tests[-1]
    assert recommended["collisionCount"]==recommended["outsideCount"]==0

    # Diagnostic sheets use the exact shared canvas and one scale, never a per-frame fit.
    sheet=Image.new("RGB",(1280,1408),"#101826");draw=ImageDraw.Draw(sheet)
    for index,rendered in enumerate(renders):
        im=Image.fromarray(rendered);bg=Image.new("RGBA",im.size,"#101826");bg.alpha_composite(im)
        thumb=bg.convert("RGB").resize((320,320),Image.Resampling.LANCZOS)
        x=(index%4)*320;y=(index//4)*352
        sheet.paste(thumb,(x,y+28));draw.text((x+10,y+8),f"{index+1:02d} / fixed canvas {n}px",fill="white")
        baseline=y+28+target[1]*320/n
        draw.line((x,baseline,x+319,baseline),fill="#34897e")
    sheet.save(HERE/"qc-registered-16.png")
    landmarks=Image.new("RGB",(720,400),"#101826"); ld=ImageDraw.Draw(landmarks)
    for cell,index in enumerate([0,15]):
        frame=data["frames"][index];rendered=renders[index]
        im=Image.fromarray(rendered);bg=Image.new("RGBA",im.size,"#101826");bg.alpha_composite(im)
        landmarks.paste(bg.convert("RGB").resize((360,360),Image.Resampling.LANCZOS),(cell*360,20))
        m=frames[index];dx,dy=frame["translation"]
        pts=[((p[0]+dx)*360/n+cell*360,(p[1]+dy)*360/n+20) for p in m["faceCaliperPoints"]]
        ld.line(pts,fill="#ffd25f",width=2)
        for box in m["eyeWhiteBounds"]:
            ld.rectangle(((box[0]+dx)*360/n+cell*360,(box[1]+dy)*360/n+20,(box[2]+dx)*360/n+cell*360,(box[3]+dy)*360/n+20),outline="#61d9ff",width=1)
        ld.text((cell*360+12,5),f"Frame {index+1}: face {m['faceWidthPx']:.2f}px",fill="white")
    landmarks.save(HERE/"qc-neutral-face-calipers.png")
    report={"schemaVersion":1,"id":"running-first-20261006","reviewedAt":"2026-10-06",
        "status":"metadata-valid-animation-quality-review-needed","artApproved":False,
        "source":{"path":relative(source),"sha256":sha(source),"width":1254,"height":1254},
        "regions":{"path":relative(metadata_path),"sha256":sha(metadata_path)},
        "defaultComparison":{"path":relative(default_path),"sha256":sha(default_path)},
        "maskValidation":{**mask_result,"roundTripRGBAMismatchChannels":0,"sourcePNGUnchanged":sha(source)==SOURCE_SHA,"totalOriginalDrawings":16},
        "registration":{"policy":data["diagnostics"]["supportAnchorPolicy"],"canvas":data["canvas"],"scalePerFrame":1,
            "defaultHeadTop60MidlineX":range_stats(old_head),"hybridHeadTop60MidlineX":range_stats(new_head),
            "bodyFitPerformed":False,"warning":"This outline midpoint is a motion proxy, not anatomical head center. Side turns and source drawing-position differences remain, rather than being normalized away."},
        "scaleRecommendation":{"scale":recommended_scale,"canvas":n,"sameFaceScale":equal_scale,
            "seatedReferenceSource":exercise["atlas"],"seatedReferenceSha256":exercise["sha256"],
            "seatedReferenceNeutralFaceWidthSource":old_face,"seatedReferenceFaceWidthAt416":old_face*old_factor,
            "runningNeutralFaceWidthAt416":frames[0]["faceWidthPx"]*332.8*recommended_scale/n,
            "runningMaximumVisibleCoreHeightAt416":max(f["coreBounds"][3]-f["coreBounds"][1] for f in frames)*332.8*recommended_scale/n,
            "sourcePixelFactorAt416":332.8*recommended_scale/n,"sourcePixelFactorAt200":160*recommended_scale/n,
            "reason":"Standing running naturally has longer visible head-to-ground extent than seated dumbbell poses. Matching the old face exactly collides with classic date/time; use one lower fixed scale for all frames, with this explicit face-size compromise."},
        "layoutSafety":{"method":"Numerical RGBA alpha>=128 bounds against previously measured DOM typography rectangles; not a new browser or Apple-device playback test.",
            "layoutsPath":relative(layouts_path),"layoutsSha256":sha(layouts_path),"domEvidencePath":relative(dom_path),"domEvidenceSha256":sha(dom_path),
            "domEvidenceFinishedAt":dom["finishedAt"],"coordinateSize":[832,992],"tests":layout_tests,
            "limits":"Faint alpha<128 source noise is preserved and is not used as anatomical core. Native usable viewport is smaller than the physical screen; 416px figures are full-stage comparisons, not a claim about measured Watch display size."},
        "frames":frames,
        "remainingIssues":["Frames 3-10 change face/body direction left and right too far for a settled front-facing running cycle.","Frame 15 unexpectedly opens both eyes after relaxed frame 14; review/repaint before seamless return.","First/last face calipers 89.5/89.0px are close but source contours and expressions are not identical; no seamless-loop claim.","Registration y assumes the reviewed lower foot is support; the PNG contains no ground line or genuine airborne keyframe.","Normal-speed browser playback, user approval and native integration are not established by this extraction QA."],
        "proofImages":[relative(HERE/"qc-ground-contacts.png"),relative(HERE/"qc-registered-16.png"),relative(HERE/"qc-neutral-face-calipers.png")]}
    output=ROOT/"animation/production-20261006-followup/running-v1-qc.json"
    save_json(output,report)
    print(json.dumps({"report":relative(output),"regionsSha256":sha(metadata_path),"face":frames[0]["faceWidthPx"],"scale":report["scaleRecommendation"],"layoutResults":[{k:v for k,v in t.items() if k!="entries"} for t in layout_tests],"headDefault":range_stats(old_head),"headHybrid":range_stats(new_head)},ensure_ascii=False,indent=2))

if __name__=="__main__":run()
