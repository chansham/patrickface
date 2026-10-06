"""Compare reviewed old/new chef source pixels; never write image pixels."""
from pathlib import Path
import hashlib
import json
import sys

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from build_frame_regions import connected_components, validate_regions
from audit_body_scale import measure_face, rim_point, track_eyes

SOURCES = (
    ("feeding-chef-v1", "00aa77c176132f6abe19edcdcff6a4235769195b818b0abd6f789a99f4eb6e66",
     [[141,120,168,171],[169,119,199,171]], {6,9}),
    ("feeding-chef-v2", "cf5115d199e0d0cbc8bac8983cec04fed215dcb4bafc0734e8e6bad9dbbfa8a0",
     [[130,118,161,169],[161,118,196,170]], {6,8}),
)
DESTINATION = ROOT / "animation/production-20261006-repair/feeding-chef-v2-qc.json"


def sha(payload):
    return hashlib.sha256(payload).hexdigest()


def delta(first, last):
    return {"first":first,"last":last,"changePercent":(last/first-1)*100}


def analyze(name, expected_sha, eye_reference, closed):
    source_path = ROOT / "animation" / name / "atlas-generated.png"
    payload = source_path.read_bytes()
    if sha(payload) != expected_sha:
        raise ValueError("Source changed; current semantic selections cannot be reused")
    regions_path = source_path.with_name("regions-v1.json")
    regions_payload = regions_path.read_bytes()
    data = json.loads(regions_payload)
    if data["source"]["sha256"] != expected_sha:
        raise ValueError("Regions source SHA drift")
    rgba = np.array(Image.open(source_path).convert("RGBA"))
    alpha = rgba[:,:,3]
    coverage = validate_regions(data,alpha)
    rows = []
    for index,frame in enumerate(data["frames"]):
        left,top,right,bottom = frame["diagnostics"]["coreBounds"]
        crop = rgba[top:bottom,left:right]
        r,g,b,a = crop.astype(int).transpose(2,0,1)
        owned = np.zeros(crop.shape[:2],dtype=bool)
        for run in frame["rows"]:
            if not top <= run[0] < bottom:
                continue
            for x0,x1 in zip(run[1::2],run[2::2]):
                owned[run[0]-top,max(x0,left)-left:min(x1,right)-left] = True
        skin = (r>160)&(g>75)&(b>70)&(r-g>25)&(r-b>20)&(abs(g-b)<65)&(a>=128)&owned
        _,components = connected_components(skin)
        feet = [c for c in components if c["pixelCount"]>500 and c["bounds"][1]>.7*(bottom-top)]
        to_source = lambda bounds: [bounds[0]+left,bounds[1]+top,bounds[2]+left,bounds[3]+top]
        foot_boxes = sorted([to_source(c["bounds"]) for c in feet])
        foot_y = max(box[3] for box in foot_boxes) if len(foot_boxes)==2 else None
        rgb=crop[:,:,:3].astype(int)
        white=(rgb.min(2)>175)&((rgb.max(2)-rgb.min(2))<45)&(a>=128)&owned
        _,components=connected_components(white)
        hats=[c for c in components if c["pixelCount"]>500 and c["bounds"][1]<.2*(bottom-top)]
        hat_box=to_source(min(hats,key=lambda c:c["bounds"][1])["bounds"]) if hats else None
        strong=owned&(a>=128)
        edge_count=0
        if top==0:edge_count+=int(strong[0].sum())
        if bottom==alpha.shape[0]:edge_count+=int(strong[-1].sum())
        if left==0:edge_count+=int(strong[:,0].sum())
        if right==alpha.shape[1]:edge_count+=int(strong[:,-1].sum())
        row={"sourceFrame":index+1,"coreBounds":[left,top,right,bottom],
             "coreWidthPx":right-left,"coreHeightPx":bottom-top,"strongPixelArea":int(strong.sum()),
             "sourceBounds":frame["sourceBounds"],"anchorSource":frame["anchorSource"],
             "sourceEdgeStrongPixels":edge_count,"visibleFootPinkFillBounds":foot_boxes,
             "visibleFootBaselineY":foot_y,"cushionCoreBottomY":bottom,
             "cushionBelowFeetPx":None if foot_y is None else bottom-foot_y,
             "hatWhiteFillBounds":hat_box,"hatWhiteFillWidthPx":None if hat_box is None else hat_box[2]-hat_box[0],
             "hatWhiteFillHeightPx":None if hat_box is None else hat_box[3]-hat_box[1],
             "faceWidthPx":None,"eyeLowerRimSeparationPx":None,"eyeLineToActualFootPx":None}
        if len(foot_boxes)!=2:
            row["footUnavailableReason"]="Did not find exactly two reviewed lower-band pink foot components"
        if index+1 in closed:
            row["eyeUnavailableReason"]="closed eyes; lower eye-white rims unavailable"
        else:
            eyes,reason=track_eyes(rgba,frame,{"referenceEyeWhiteBounds":eye_reference},data["frames"][0])
            if eyes is None:
                row["eyeUnavailableReason"]=reason
            else:
                l,r=[rim_point(box) for box in eyes]
                row["eyeWhiteBounds"]=eyes
                row["eyeLowerRimPoints"]=[l.tolist(),r.tolist()]
                row["eyeLowerRimSeparationPx"]=float(np.linalg.norm(r-l))
                row["eyeLineToActualFootPx"]=None if foot_y is None else float(foot_y-(l[1]+r[1])/2)
                measured=measure_face(rgba,eyes,foot_y)
                if "faceWidth" in measured:
                    row["faceWidthPx"]=measured["faceWidth"]
                    row["faceCaliperPoints"]=measured["faceCaliperPoints"]
                else:
                    row["faceWidthUnavailableReason"]=measured.get("unavailable","unreliable face edge")
        rows.append(row)
    if source_path.read_bytes()!=payload:
        raise ValueError("Source changed during measurement")
    return {"source":data["source"],"sourceUnchanged":True,
            "regions":{"path":regions_path.relative_to(ROOT).as_posix(),"sha256":sha(regions_payload)},
            "canvas":data["canvas"],"coverage":coverage,
            "reference":{"sourceFrame":1,"referenceEyeWhiteBounds":eye_reference,
                         "sourceSha256":expected_sha,"closedEyeFrames":sorted(closed)},"frames":rows,
            "summary":{"measuredFaceFrames":sum(f["faceWidthPx"] is not None for f in rows),
                       "measuredEyeActualFootFrames":sum(f["eyeLineToActualFootPx"] is not None for f in rows),
                       "measuredVisibleFeetFrames":sum(f["visibleFootBaselineY"] is not None for f in rows),
                       "sourceEdgeStrongPixels":sum(f["sourceEdgeStrongPixels"] for f in rows)}}


def main():
    old,new=[analyze(*source) for source in SOURCES]
    names=["coreWidthPx","coreHeightPx","hatWhiteFillWidthPx","hatWhiteFillHeightPx",
           "faceWidthPx","eyeLowerRimSeparationPx","eyeLineToActualFootPx"]
    report={"schemaVersion":1,"reviewedAt":"2026-10-06","frameIndexBasis":"one-based source reading order",
            "status":"candidate-needs-cookie-revision-and-playback-review","artApproved":False,
            "catalogIntegrated":False,"normalSpeedReview":"not-yet-performed-for-v2",
            "source":new["source"],"sourceUnchanged":True,"regions":new["regions"],"canvas":new["canvas"],
            "coverage":new["coverage"],"old":old,"new":new,
            "methods":[
                "Original pixel units, both sources1254x1254. No PNG, anchor, scale, catalog or old report edited.",
                "Source SHA pins bind all reference semantic selections. Eye tracking is expression-sensitive; closed or unreliable face sections remain null.",
                "Hat height is the white fill component height, excluding black outline; this is a repeatable hat proxy with approximately2px edge uncertainty.",
                "Visible feet are two disconnected coral-pink components in the lowest30percent body band, each area>500px. Original source frames were visually checked to distinguish feet from hands/badge/cushion.",
                "Foot baseline is the lower of those actual foot-fill component bounds, not the opaque cushion or region anchor. Pink fill excludes outline; approximately2px edge uncertainty.",
                "Eye-line-to-foot is a pose proxy, not inferred hidden torso anatomy. Face width is visible pink face cross-section at the lower eye rims; eye separation is not pupil distance.",
                "This independent new review does not retroactively replace the old whole-library report's conservative unmeasured foot entries.",
                "Uniform common canvas only ensures extraction. No per-frame scaling or geometric smoothing is used."
            ],
            "oldNewFirstFrame":{key:delta(old["frames"][0][key],new["frames"][0][key]) for key in names},
            "newFirstLastFrame":{key:delta(new["frames"][0][key],new["frames"][-1][key]) for key in names},
            "visualFindings":[
                {"sourceFrames":[1,12],"kind":"improved","message":"Face/eyes are larger relative to the hat and seated body. Actual foot baseline remains stable; this is not canvas-only scaling."},
                {"sourceFrames":[12],"kind":"defect","message":"Bitten cookie becomes whole again on the plate. Do not call the original12-frame storyline repaired; requires drawing revision."},
                {"sourceFrames":[5,6],"kind":"pending-normal-speed-review","message":"Cookie leaves mouth and hand drops a substantial distance in one step; contact/release can still look abrupt."},
                {"sourceFrames":[10,11],"kind":"improved","message":"Two successive lowering-hand positions exist before the final plate pose, preserving the bitten cookie through frame11."},
                {"sourceFrames":list(range(1,13)),"kind":"preserve","message":"Mint apron, shell motif, white hat, white sclera, pink eyelids, bare feet and eating-once narrative. Black cushion is separate from anatomical foot baseline."},
                {"sourceFrames":list(range(1,13)),"kind":"pending-review","message":"Hat brim, cheek expression and gripping shape still vary; only live1x review can assess the transitions. Artwork remains unapproved."}
            ]}
    DESTINATION.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"report":DESTINATION.relative_to(ROOT).as_posix(),"summary":new["summary"],
                      "oldNewFirstFrame":report["oldNewFirstFrame"],"newFirstLastFrame":report["newFirstLastFrame"]},ensure_ascii=False))


if __name__=="__main__":main()
