"""Read-only source analysis; save independent QC and never change artwork."""
from pathlib import Path
import hashlib
import importlib.util
import json
import sys

import numpy as np
from PIL import Image

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/"tools"))
from build_frame_regions import validate_regions
from audit_body_scale import track_eyes,measure_face,rim_point
spec=importlib.util.spec_from_file_location("repair_drift",ROOT/"animation/feeding-chef-v3/compare_drift.py")
drift=importlib.util.module_from_spec(spec);spec.loader.exec_module(drift)


def main():
    p=ROOT/"animation/focus-v3/atlas-generated.png";payload=p.read_bytes()
    expected="fe7121a215d6fa547cf09564f74d67802999199766d976c750bc73bb64b5991f"
    if hashlib.sha256(payload).hexdigest()!=expected:raise ValueError("review source changed")
    rp=p.with_name("regions-v1.json");rb=rp.read_bytes();data=json.loads(rb)
    if data["source"]["sha256"]!=expected:raise ValueError("source/metadata SHA mismatch")
    a=np.array(Image.open(p).convert("RGBA"));alpha=a[:,:,3]
    coverage=validate_regions(data,alpha)
    reference={"referenceEyeWhiteBounds":[[179,104,210,136],[214,105,244,137]]}
    rows=[]
    for i,f in enumerate(data["frames"]):
        l,t,r,b=f["diagnostics"]["coreBounds"]
        edge=[]
        for run in f["rows"]:
            y=run[0]
            if y!=alpha.shape[0]-1:continue
            for x0,x1 in zip(run[1::2],run[2::2]):
                xs=np.flatnonzero(alpha[y,x0:x1]>=128)+x0
                if len(xs):edge.append({"xRange":[int(xs.min()),int(xs.max())+1],"strongPixels":len(xs),"maximumAlpha":int(alpha[y,xs].max())})
        row={"sourceFrame":i+1,"coreBounds":[l,t,r,b],"coreWidthPx":r-l,"coreHeightPx":b-t,
             "sourceBounds":f["sourceBounds"],"anchorSource":f["anchorSource"],
             "sourceBottomEdgeStrongRuns":edge,"sourceBottomEdgeStrongPixels":sum(x["strongPixels"] for x in edge),
             "faceWidthPx":None,"eyeLowerRimSeparationPx":None,"eyeLineToActualFootPx":None}
        if i+1 in (8,9,10,11):row["eyeUnavailableReason"]="hand overlaps face"
        elif i+1==15:row["eyeUnavailableReason"]="closed eyes"
        else:
            eyes,why=track_eyes(a,f,reference,data["frames"][0])
            if eyes is None:row["eyeUnavailableReason"]=why
            else:
                x,y=[rim_point(v) for v in eyes]
                row["eyeWhiteBounds"]=eyes;row["eyeLowerRimPoints"]=[x.tolist(),y.tolist()]
                row["eyeLowerRimSeparationPx"]=float(np.linalg.norm(y-x))
                foot=None if edge else b
                measured=measure_face(a,eyes,foot)
                row["eyeLineToActualFootPx"]=None if foot is None else float(foot-(x[1]+y[1])/2)
                if "faceWidth" in measured:
                    row["faceWidthPx"]=measured["faceWidth"];row["faceCaliperPoints"]=measured["faceCaliperPoints"]
                else:row["faceUnavailableReason"]=measured.get("unavailable","unreliable face edge")
        if edge:row["footUnavailableReason"]="Strong silhouette reaches original PNG bottom boundary; a complete anatomical foot baseline cannot be confirmed. Do not use the clipped canvas boundary as a measured foot."
        rows.append(row)
    old=json.loads((ROOT/"animation/production-20261006-repair/focus-v2-qc.json").read_bytes())
    heights=[f["coreHeightPx"] for f in rows]
    report={"schemaVersion":1,"reviewedAt":"2026-10-06","frameIndexBasis":"one-based",
            "status":"candidate-needs-revision-new-source-edge-risk","artApproved":False,"bodyScaleResolved":False,
            "catalogIntegrated":False,"normalSpeedReview":"not-performed","source":data["source"],"sourceUnchanged":True,
            "regions":{"path":rp.relative_to(ROOT).as_posix(),"sha256":hashlib.sha256(rb).hexdigest()},
            "canvas":data["canvas"],"coverage":coverage,"frames":rows,
            "reference":{"sourceFrame":1,**reference,"sourceSha256":expected},
            "summary":{"sourceFrames":16,"measuredFaceFrames":sum(f["faceWidthPx"] is not None for f in rows),
                       "measuredEyeActualFootFrames":sum(f["eyeLineToActualFootPx"] is not None for f in rows),
                       "coreHeightFirstLast":[heights[0],heights[-1]],"coreHeightFirstLastChangePercent":(heights[-1]/heights[0]-1)*100,
                       "firstRowMeanHeight":float(np.mean(heights[:4])),"lastRowMeanHeight":float(np.mean(heights[-4:])),
                       "rowMeanHeightChangePercent":(np.mean(heights[-4:])/np.mean(heights[:4])-1)*100,
                       "previousV2Summary":old["summary"],"sourceBottomEdgeStrongPixels":sum(f["sourceBottomEdgeStrongPixels"] for f in rows)},
            "sourcePixelDrift":drift.compare("focus-v2","focus-v3"),
            "methods":["Whole silhouette includes clothes, hands and notebook; it is not bare torso height.",
                       "White-eye reference boxes selected on current source. Hand-occluded8-11 and closed15 are unmeasured.",
                       "Foot proxies15/16 are unavailable because strong silhouette reaches original source edge; no comparison pretends this boundary is a complete foot.",
                       "All nonzero-alpha source pixels preserved. Translation-only metadata cannot recover pixels beyond original PNG.",
                       "No PNG, per-frame scale, catalog or existing size audit edited."],
            "visualFindings":[{"sourceFrames":[13,14,15,16],"kind":"defect-persists","message":"Last row remains vertically shorter; small size recovery does not restore consistent torso proportions."},
                              {"sourceFrames":[15,16],"kind":"new-source-edge-risk","message":"30 strong pixels per frame reach last PNG row1085, maximum alpha253/251. Complete outer foot contours cannot be confirmed."},
                              {"sourceFrames":list(range(1,13)),"kind":"unrequested-drift","message":"Non-target first12 silhouettes widened2-6px and grew2-4px. Not an exact last-row-only edit."},
                              {"sourceFrames":[11,12],"kind":"preserve","message":"Hand-lowering intermediate poses from v2 remain."}],
            "recommendation":"Keep v2 as the safer candidate while retaining v3 as failed/partial repair evidence; do not replace active artwork or claim consistency resolved."}
    if p.read_bytes()!=payload:raise ValueError("source changed")
    destination=ROOT/"animation/production-20261006-repair/focus-v3-qc.json"
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"report":destination.relative_to(ROOT).as_posix(),"summary":report["summary"]},ensure_ascii=False))


if __name__=="__main__":main()
