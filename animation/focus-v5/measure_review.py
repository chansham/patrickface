"""Read-only image QA; writes only the independent focus-v5 QC JSON.

Run with python -B. No PNG, generic extraction tool, catalog or scale is edited.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import sys

import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from build_frame_regions import connected_components,validate_regions
from audit_body_scale import track_eyes,measure_face,rim_point

SOURCE="animation/focus-v5/atlas-generated.png"
SOURCE_SHA="d1376033bd5efe8c3de53b6c0763a8308ef9c820cad41c9799d15a70052d8847"
OLD_SOURCE="animation/focus-v2/atlas-generated.png"
OLD_SHA="7ee112183d2c9e5d911bf89cedc8b4afba705f6a72659838410daa934939322f"
REFERENCE_EYES=[[243,121,276,155],[281,121,314,155]]
OUTPUT=ROOT/"animation/production-20261006-followup/focus-v5-qc.json"


def sha(payload):return hashlib.sha256(payload).hexdigest()


def load(relative,expected):
    path=ROOT/relative;payload=path.read_bytes()
    if sha(payload)!=expected:raise ValueError("reviewed source SHA changed")
    rp=path.with_name("regions-v1.json");rb=rp.read_bytes();regions=json.loads(rb)
    rgba=np.array(Image.open(path).convert("RGBA"))
    if regions["source"]!={"path":relative,"sha256":expected,"width":rgba.shape[1],"height":rgba.shape[0]}:
        raise ValueError("source and metadata identity disagree")
    return rgba,regions,{"path":rp.relative_to(ROOT).as_posix(),"sha256":sha(rb)},payload


def semantic_support(rgba,frame):
    l,t,r,b=frame["diagnostics"]["coreBounds"];crop=rgba[t:b,l:r]
    red,green,blue,alpha=crop.astype(int).transpose(2,0,1)
    owned=np.zeros(crop.shape[:2],dtype=bool)
    for run in frame["rows"]:
        if not t<=run[0]<b:continue
        for x0,x1 in zip(run[1::2],run[2::2]):
            owned[run[0]-t,max(l,x0)-l:min(r,x1)-l]=True
    skin=(red>160)&(green>75)&(blue>70)&(red-green>25)&(red-blue>20)&(abs(green-blue)<65)&(alpha>=128)&owned
    _,components=connected_components(skin)
    to_source=lambda p:[p[0]+l,p[1]+t,p[2]+l,p[3]+t]
    feet=sorted(to_source(c["bounds"]) for c in components if c["pixelCount"]>500 and c["bounds"][1]>.75*(b-t))
    heads=[c for c in components if c["pixelCount"]>3000 and c["bounds"][1]<.35*(b-t)]
    head=min(heads,key=lambda c:c["bounds"][1]) if heads else None
    foot=max(p[3] for p in feet) if len(feet)==2 else None
    head_top=head["bounds"][1]+t if head else None
    return {"visibleFootPinkFillBounds":feet,"visibleFootBaselineY":foot,
            "visibleHeadPinkBounds":to_source(head["bounds"]) if head else None,
            "visibleHeadTopY":head_top,
            "visibleHeadTopToFootPx":None if head_top is None or foot is None else foot-head_top,
            "strongPixelArea":int((owned&(alpha>=128)).sum())}


def delta(first,last):
    return {"first":first,"last":last,"changePercent":None if first is None or last is None else (last/first-1)*100}


def make_report():
    rgba,data,regions_reference,payload=load(SOURCE,SOURCE_SHA)
    alpha=rgba[:,:,3];coverage=validate_regions(data,alpha)
    if len(data["frames"])!=12:raise ValueError("expected3x4 reading-order12frames")
    rows=[]
    exclusions={5:"hand near face edge; conservative occlusion exclusion",6:"hand overlaps face edge",
                7:"hand overlaps face edge",8:"hand overlaps face edge",
                10:"very thin partial eye-white components; ambiguous lower-rim tracking",
                11:"eyes fully closed"}
    for i,frame in enumerate(data["frames"]):
        l,t,r,b=frame["diagnostics"]["coreBounds"]
        row={"sourceFrame":i+1,"sourceBounds":frame["sourceBounds"],"coreBounds":[l,t,r,b],
             "coreWidthPx":r-l,"coreHeightPx":b-t,"anchorSource":frame["anchorSource"],
             "translation":frame["translation"],**semantic_support(rgba,frame),
             "faceWidthPx":None,"eyeLowerRimSeparationPx":None,"eyeLineToFootPx":None}
        row["sourceEdgeStrongPixels"]=0
        for run in frame["rows"]:
            y=run[0]
            for x0,x1 in zip(run[1::2],run[2::2]):
                if y in (0,alpha.shape[0]-1):row["sourceEdgeStrongPixels"]+=int((alpha[y,x0:x1]>=128).sum())
                else:
                    if x0==0:row["sourceEdgeStrongPixels"]+=int(alpha[y,0]>=128)
                    if x1==alpha.shape[1]:row["sourceEdgeStrongPixels"]+=int(alpha[y,-1]>=128)
        if i+1 in exclusions:row["unavailableReason"]=exclusions[i+1]
        else:
            eyes,reason=track_eyes(rgba,frame,{"referenceEyeWhiteBounds":REFERENCE_EYES},data["frames"][0])
            if eyes is None:row["unavailableReason"]=reason
            else:
                points=[rim_point(p) for p in eyes];midpoint=np.mean(points,axis=0)
                row["eyeWhiteBounds"]=eyes;row["eyeLowerRimPoints"]=[p.tolist() for p in points]
                row["eyeMidpoint"]=midpoint.tolist()
                row["eyeLowerRimSeparationPx"]=float(np.linalg.norm(points[1]-points[0]))
                foot=row["visibleFootBaselineY"]
                if foot is not None and row["sourceEdgeStrongPixels"]==0:
                    row["eyeLineToFootPx"]=float(foot-midpoint[1])
                    row["footSourcePoint"]=[float(midpoint[0]),foot]
                    row["eyeToFootPoints"]=[midpoint.tolist(),row["footSourcePoint"]]
                measured=measure_face(rgba,eyes,foot)
                if "faceWidth" in measured:
                    row["faceWidthPx"]=measured["faceWidth"];row["faceCaliperPoints"]=measured["faceCaliperPoints"]
                else:row["faceWidthUnavailableReason"]=measured.get("unavailable","unreliable visible face")
        rows.append(row)
    old_rgba,old_regions,old_region_ref,old_payload=load(OLD_SOURCE,OLD_SHA)
    old_qc_path=ROOT/"animation/production-20261006-repair/focus-v2-qc.json"
    old_qc_bytes=old_qc_path.read_bytes();old_qc=json.loads(old_qc_bytes)
    if old_qc["source"]["sha256"]!=OLD_SHA or old_qc["regions"]!=old_region_ref:
        raise ValueError("previous evidence source identity changed")
    old_neutral=[]
    for index in (0,15):
        support=semantic_support(old_rgba,old_regions["frames"][index]);reviewed=old_qc["frames"][index]
        midpoint=np.mean(reviewed["eyeLowerRimPoints"],axis=0)
        old_neutral.append({"sourceFrame":index+1,**support,"eyeLowerRimPoints":reviewed["eyeLowerRimPoints"],
                            "eyeLineToActualFootPx":float(support["visibleFootBaselineY"]-midpoint[1])})
    first,last=rows[0],rows[-1]
    summary={"sourceFrames":12,"measuredFaceFrames":sum(r["faceWidthPx"] is not None for r in rows),
             "measuredEyeActualFootFrames":sum(r["eyeLineToFootPx"] is not None for r in rows),
             "visibleHeadFootFrames":sum(r["visibleHeadTopToFootPx"] is not None for r in rows),
             "coreHeightFirstLast":delta(first["coreHeightPx"],last["coreHeightPx"]),
             "coreWidthFirstLast":delta(first["coreWidthPx"],last["coreWidthPx"]),
             "faceWidthFirstLast":delta(first["faceWidthPx"],last["faceWidthPx"]),
             "eyeSeparationFirstLast":delta(first["eyeLowerRimSeparationPx"],last["eyeLowerRimSeparationPx"]),
             "eyeToActualFootFirstLast":delta(first["eyeLineToFootPx"],last["eyeLineToFootPx"]),
             "visibleHeadTopToActualFootFirstLast":delta(first["visibleHeadTopToFootPx"],last["visibleHeadTopToFootPx"]),
             "coreFirstLastRowMeans":delta(float(np.mean([r["coreHeightPx"] for r in rows[:3]])),float(np.mean([r["coreHeightPx"] for r in rows[-3:]]))),
             "sourceEdgeStrongPixels":sum(r["sourceEdgeStrongPixels"] for r in rows),
             "minimumStrongCoreSourceMarginsLTRB":[min(r["coreBounds"][0] for r in rows),min(r["coreBounds"][1] for r in rows),
                 min(rgba.shape[1]-r["coreBounds"][2] for r in rows),min(rgba.shape[0]-r["coreBounds"][3] for r in rows)]}
    report={"schemaVersion":1,"reviewedAt":"2026-10-06","frameIndexBasis":"one-based source reading order",
            "status":"improved-candidate-body-proportion-and-transition-review-required","artApproved":False,
            "bodyScaleResolved":False,"catalogIntegrated":False,"normalSpeedReview":"not-yet-performed-for-v5",
            "source":data["source"],"sourceUnchanged":True,"regions":regions_reference,"canvas":data["canvas"],"coverage":coverage,
            "grid":{"columns":3,"rows":4,"frames":12},
            "reference":{"sourceFrame":1,"referenceEyeWhiteBounds":REFERENCE_EYES,"sourceSha256":SOURCE_SHA,
                         "selection":"Fresh eye-white and visible-head/feet inspection on this source; no old-source coordinate transfer.",
                         "visualReview":"Full atlas seen, correctly alpha-composited light background inspected; neutral first/last head and both feet checked."},
            "frames":rows,"summary":summary,
            "sameMethodPreviousV2":{"source":old_regions["source"],"regions":old_region_ref,
                "eyeEvidence":{"path":old_qc_path.relative_to(ROOT).as_posix(),"sha256":sha(old_qc_bytes)},
                "frames":old_neutral,
                "eyeToActualFootFirstLast":delta(old_neutral[0]["eyeLineToActualFootPx"],old_neutral[-1]["eyeLineToActualFootPx"]),
                "visibleHeadTopToActualFootFirstLast":delta(old_neutral[0]["visibleHeadTopToFootPx"],old_neutral[-1]["visibleHeadTopToFootPx"]),
                "note":"Re-read v2's actual foot/head pink fill using the same method. The earlier8.42percent figure used the strong silhouette support edge; do not mix baselines. Only within-version relative change is compared because atlas geometry/pixel character size differs."},
            "methods":["Every source pixel stays unchanged. Full-alpha contour assignment and integer translation only; no per-frame scaling.",
                       "Strong whole silhouette includes clothing, arms and notebook; it is not an anatomical body measurement.",
                       "This source has no hat: top of the reviewed largest upper coral-pink component identifies visible head top. Two separate lower-quarter pink components identify actual feet.",
                       "Pink-fill head/foot contours exclude black outlines; approximately2source-pixel boundary uncertainty. Eye-to-foot is a pose proxy, not hidden torso anatomy.",
                       "Eye rims/face calipers are source-specific. Hands5-8, ambiguous partial eye10 and closed11 remain unmeasured; no bbox fallback.",
                       "Approximately3percent was a proposed review trigger, not an automatic approval rule. Current independent body proxies still flag shortening.",
                       "No phase-by-phase index matching is assumed between new12frames and old16frames."],
            "visualFindings":[
                {"sourceFrames":[1,12],"kind":"improved-but-unresolved","message":"Similar neutral forward poses have stable face/eye widths but shorter head-to-feet and eye-to-feet distance at the end. Body shortening is reduced, not removed."},
                {"sourceFrames":[5,6,7,8,9],"kind":"real-limb-action-preserved","message":"Hand rises to glasses, touches them, then returns toward notebook. Actual pose changes exist; not whole-card sway."},
                {"sourceFrames":[8,9],"kind":"transition-review-required","message":"Cheek-level hand returns directly to notebook in the next frame; the explicit chest-level intermediate pose of v2 is absent. Review at actual1x before accepting continuity."},
                {"sourceFrames":[4,5,6],"kind":"timing-review-required","message":"Eyes switch open/half-lidded/open while the hand rises. May read as a blink or a pop depending on timing; not approved from the static sheet."},
                {"sourceFrames":[10,11,12],"kind":"preserve","message":"Pink closed eyelids, white open sclera, glasses and notebook retained; no source-bottom collision as in rejected v3."}],
            "candidateValue":"Worth an independent side-by-side candidate because proportional shortening is reduced and source margins are safe. Keep body/transition warnings and retain all12frames; not a finished replacement."}
    if (ROOT/SOURCE).read_bytes()!=payload or (ROOT/OLD_SOURCE).read_bytes()!=old_payload:raise ValueError("source changed during measurement")
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--check",action="store_true");args=parser.parse_args()
    report=make_report();payload=(json.dumps(report,ensure_ascii=False,indent=2)+"\n").encode("utf-8")
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes()!=payload:raise ValueError("QC snapshot is stale")
    else:OUTPUT.write_bytes(payload)
    print(json.dumps({"report":OUTPUT.relative_to(ROOT).as_posix(),"sha256":sha(payload),"summary":report["summary"],
                      "previousEquivalentBody":report["sameMethodPreviousV2"]["eyeToActualFootFirstLast"],"readOnlyCheck":args.check},ensure_ascii=False))


if __name__=="__main__":main()
