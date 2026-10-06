#!/usr/bin/env python3
"""Measure visible anatomical proxies in source pixels, without changing art.

Whole alpha bounds are used ONLY for tracking search windows/overflow checks.
The measured facial caliper follows the visible eye lower-rim line and excludes
hats and held objects. Eye shape, lean, occlusion and hidden anatomy remain
explicit limitations. This tool does not fit or normalize individual frames.
"""
from __future__ import annotations

import argparse
import hashlib
import itertools
import json
import math
import re
from pathlib import Path

import numpy as np
from PIL import Image

from build_frame_regions import connected_components

ROOT = Path(__file__).resolve().parents[1]
DIRECTORY = ROOT/"animation/production-20261006-scale"
METRICS = {
    "faceWidth": "眼下緣線可見臉部橫截寬",
    "eyeSeparation": "兩眼下緣中點距離（非瞳孔距）",
    "eyeToFoot": "眼下緣中線至足底垂直距離（姿勢代理）",
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def checked_json(path: Path, expected_sha: str | None = None):
    payload = path.read_bytes()
    if expected_sha is not None and digest(payload) != expected_sha:
        raise ValueError(f"SHA drift: {path}")
    return json.loads(payload), digest(payload)


def verify_source_digest(payload: bytes, landmark_sha: str, catalog_sha: str):
    if digest(payload) != landmark_sha or landmark_sha != catalog_sha:
        raise ValueError("Source/landmark SHA drift")


def unique_source_clips(catalogs):
    sources={}
    for catalog in catalogs.values():
        for clip in catalog["clips"]:
            sources.setdefault(clip["atlas"],clip)
    return sources


def source_to_stage_factor(canvas_width: float, clip_scale: float,
                           stage_width: float = 832, sprite_fraction: float = .8) -> float:
    return stage_width * sprite_fraction * clip_scale / canvas_width


def variation(values: list[float], reference: float, tolerance: float = .08) -> dict:
    ratios = [value/reference for value in values]
    return {"min": min(values), "max": max(values), "mean":sum(values)/len(values),"reference": reference,
            "minimumReferenceRatio": min(ratios), "maximumReferenceRatio": max(ratios),
            "flagged": any(abs(ratio-1) > tolerance for ratio in ratios), "tolerance": tolerance}


def rim_point(bounds):
    left, top, right, bottom = bounds
    return np.array([(left+right-1)/2, bottom-1], dtype=float)


def track_eyes(rgba: np.ndarray, frame: dict, reference: dict, reference_frame: dict):
    """Find the two reference eye-white components; do not invent closed eyes."""
    l, t, r, b = frame["diagnostics"]["coreBounds"]
    rl, rt, rr, rb = reference_frame["diagnostics"]["coreBounds"]
    ratio = (b-t)/(rb-rt)  # search-window prediction only, not a measured size
    anchor = np.asarray(frame["anchorSource"])
    reference_anchor = np.asarray(reference_frame["anchorSource"])
    eye_bounds = reference["referenceEyeWhiteBounds"]
    predictions = []
    for bounds in eye_bounds:
        center = np.array([(bounds[0]+bounds[2])/2, (bounds[1]+bounds[3])/2])
        predictions.append(anchor + (center-reference_anchor)*ratio)
    crop = rgba[t:b, l:r]
    rgb = crop[:, :, :3].astype(int)
    owned = np.zeros(crop.shape[:2], dtype=bool)
    for row in frame["rows"]:
        if not t <= row[0] < b:
            continue
        for x0, x1 in zip(row[1::2], row[2::2]):
            owned[row[0]-t, max(l,x0)-l:min(r,x1)-l] = True
    mask = (rgb.min(2)>175) & ((rgb.max(2)-rgb.min(2))<45) & (crop[:,:,3]>=128) & owned
    # Restrict to the actual reference eye area. A hat or shirt is not an eye.
    yy, xx = np.indices(mask.shape)
    allowed = np.zeros(mask.shape, dtype=bool)
    for pred, ref in zip(predictions, eye_bounds):
        width = (ref[2]-ref[0])*ratio
        height = (ref[3]-ref[1])*ratio
        allowed |= (abs(xx+l-pred[0]) <= width*1.15) & (abs(yy+t-pred[1]) <= max(width*.9,height*.85))
    mask &= allowed
    _, components = connected_components(mask)
    boxes = [[c["bounds"][0]+l,c["bounds"][1]+t,c["bounds"][2]+l,c["bounds"][3]+t,c["pixelCount"]]
             for c in components if c["pixelCount"] >= 20]
    choices = []
    for first, second in itertools.permutations(boxes, 2):
        if first[0] >= second[0]:
            continue
        cost = 0
        valid = True
        for box, prediction, ref in zip((first,second), predictions, eye_bounds):
            width, height = box[2]-box[0], box[3]-box[1]
            rw, rh = (ref[2]-ref[0])*ratio, (ref[3]-ref[1])*ratio
            center = np.array([(box[0]+box[2])/2, (box[1]+box[3])/2])
            delta = (center-prediction)/rw
            if not (.45*rw <= width <= 1.65*rw and .15*rh <= height <= 2.1*rh
                    and abs(delta[0])<.75 and abs(delta[1])<.8):
                valid=False; break
            cost += float(np.dot(delta,delta)) + .12*abs(math.log(width/rw))
        if valid:
            choices.append((cost,[first[:4],second[:4]]))
    if not choices:
        return None, "closed-occluded-or-unreliable-eye-tracking"
    cost, selected = min(choices, key=lambda item: item[0])
    if cost > .8:
        return None, "ambiguous-eye-tracking"
    return selected, None


def measure_face(rgba: np.ndarray, bounds: list, foot_y: float | None) -> dict:
    left, right = [rim_point(value) for value in bounds]
    vector = right-left
    distance = float(np.linalg.norm(vector))
    unit = vector/distance
    midpoint = (left+right)/2
    positions = np.arange(-2.7*distance, 2.7*distance, .25)
    points = np.round(midpoint+positions[:,None]*unit).astype(int)
    valid = ((points[:,0]>=0)&(points[:,1]>=0)&(points[:,0]<rgba.shape[1])&(points[:,1]<rgba.shape[0]))
    points, positions = points[valid], positions[valid]
    rx0=max(0,int(points[:,0].min())-2);rx1=min(rgba.shape[1],int(points[:,0].max())+3)
    ry0=max(0,int(points[:,1].min()-distance));ry1=min(rgba.shape[0],int(points[:,1].max()+distance)+1)
    red, green, blue, alpha = rgba[ry0:ry1,rx0:rx1].astype(int).transpose(2,0,1)
    # These reviewed sources use coral-pink skin. Orange dumbbells, white hats,
    # purple eyelids, green clothes and transparent padding are excluded.
    skin_mask = ((red>160)&(green>75)&(blue>70)&(red-green>25)&(red-blue>20)
            &(abs(green-blue)<65)&(alpha>=128))
    labels, components=connected_components(skin_mask)
    components=[item for item in components if item["pixelCount"]>=12]
    if not components:return {"unavailable":"visible-pink-face-edges-not-found"}
    # Follow the face near the eye bridge, not a separate pink hand or prop.
    # A real contact/occlusion still needs the explicit manual exclusion list.
    def near_eye_bridge(component):
        y,x=np.where(labels==component["id"])
        return float(((x+rx0-midpoint[0])**2+(y+ry0-midpoint[1])**2).min())
    selected=min(components,key=near_eye_bridge)
    skin=labels[points[:,1]-ry0,points[:,0]-rx0]==selected["id"]
    if not np.any(skin & (positions<-.4*distance)) or not np.any(skin & (positions>.4*distance)):
        return {"unavailable": "visible-pink-face-edges-not-found"}
    start, end = np.flatnonzero(skin)[[0,-1]]
    return {"faceWidth": float(positions[end]-positions[start]), "eyeSeparation": distance,
            "eyeToFoot": None if foot_y is None else float(foot_y-midpoint[1]),
            "eyeLowerRimPoints": [left.tolist(),right.tolist()],
            "faceCaliperPoints": [points[start].tolist(),points[end].tolist()],
            "eyeMidpoint": midpoint.tolist(), "eyeLineAngleDegrees": math.degrees(math.atan2(vector[1],vector[0])),
            "eyeWhiteBounds": bounds, "edgeSamplingUncertaintySourcePixels": 2}


def stage_point(point, frame, factor, stage_anchor):
    # Equivalent to destinationRect: source offset from that pose's foot anchor.
    return [(point[axis]-frame["anchorSource"][axis])*factor+stage_anchor[axis] for axis in (0,1)]


def make_report() -> dict:
    pin = (DIRECTORY/"landmarks.sha256").read_text(encoding="ascii").split()[0]
    landmark_data, landmark_sha = checked_json(DIRECTORY/"landmarks.json",pin)
    landmarks = {item["sourcePath"]: item for item in landmark_data["sources"]}
    catalogs = {}
    for name in ("catalog","candidates"):
        catalogs[name], _ = checked_json(ROOT/f"animation/{name}.json")
    layouts, layout_sha = checked_json(ROOT/"experience/layouts.json")
    player_bytes=(ROOT/"preview/player-core.js").read_bytes()
    match=re.search(r"export const STAGE = Object.freeze\(\{([^}]+)\}\)",player_bytes.decode("utf-8-sig"))
    if not match:raise ValueError("Cannot verify player STAGE constants")
    stage={key.strip():float(value) for key,value in (part.split(":") for part in match.group(1).split(","))}
    before, _ = checked_json(DIRECTORY/"catalog-before.json")
    before_candidates, _ = checked_json(DIRECTORY/"candidates-before.json")
    before_by_id = {c["id"]:c for d in (before,before_candidates) for c in d["clips"]}
    source_clips = unique_source_clips(catalogs)
    report = {"schemaVersion":1,"generatedAt":"2026-10-06","artApproval":False,
              "landmarksPath":"animation/production-20261006-scale/landmarks.json","landmarksSha256":landmark_sha,
              "layoutsSha256":layout_sha,"playerCoreSha256":digest(player_bytes),"stageConstants":stage,
              "coordinateSize":[832,992],"frameIndexBasis":"zero-based",
              "method":"visible-face-eye-lower-rim-calipers-v1","sources":[],"clips":[],
              "limitations":["Facial caliper is an anatomical proxy, not whole-head or whole-body bounding height.",
                             "Lower-rim separation is not pupil distance; eye drawing/expressions can alter it.",
                             "Eye-to-foot is a pose-sensitive vertical-body proxy; bath has no visible feet.",
                             "Hidden torso outlines are not inferred through costumes or props.",
                             "Missing or occluded landmarks remain unmeasured and flagged; no all-frame aesthetic PASS.",
                             "Pixel colors, source sizes and per-frame scale are never changed."]}
    for path, clip in source_clips.items():
        reference = landmarks[path]
        checked_json_payload = (ROOT/path).read_bytes()
        verify_source_digest(checked_json_payload,reference["sourceSha256"],clip["sha256"])
        metadata, regions_sha = checked_json(ROOT/clip["frameRegions"]["path"],clip["frameRegions"]["sha256"])
        rgba = np.asarray(Image.open(ROOT/path).convert("RGBA"))
        ref_frame = metadata["frames"][reference["referenceFrame"]]
        frames=[]
        for index,frame in enumerate(metadata["frames"]):
            item={"sourceFrame":index,"flags":[],"source":None}
            if index in reference.get("excludedHeadFrames",[]):
                item["flags"].append({"code":"face-occluded","severity":"warning","message":reference["exclusionReason"]})
            else:
                if index==reference["referenceFrame"]:
                    boxes,error=reference["referenceEyeWhiteBounds"],None
                else:
                    boxes,error=track_eyes(rgba,frame,reference,ref_frame)
                if error:
                    item["flags"].append({"code":error,"severity":"warning","message":"眼部閉合／遮擋或追蹤不確定，未用人物總外框填補。"})
                else:
                    measured=measure_face(rgba,boxes,frame["anchorSource"][1] if reference["footBaselineVisible"] else None)
                    if "unavailable" in measured:
                        item["flags"].append({"code":measured["unavailable"],"severity":"warning","message":"沒有可確認的兩側可見臉部輪廓。"})
                    else:
                        item["source"]=measured
            frames.append(item)
        report["sources"].append({"sourcePath":path,"sourceSha256":clip["sha256"],"regionsSha256":regions_sha,
                                   "referenceFrame":reference["referenceFrame"],"poseFamily":reference["poseFamily"],
                                   "referenceVisualReview":reference.get("referenceVisualReview"),
                                   "footBaselineUnavailableReason":None if reference["footBaselineVisible"] else reference.get("footBaselineUnavailableReason","Anatomical feet are hidden by the tub."),
                                   "frameCount":len(frames),"measuredFrameCount":sum(f["source"] is not None for f in frames),
                                   "neutralTorsoWidth":None,"neutralTorsoWidthUnavailableReason":reference["torsoWidthUnavailableReason"],
                                   "frames":frames})
    by_path={source["sourcePath"]:source for source in report["sources"]}
    for catalog_name,catalog in catalogs.items():
        stage_anchor=[stage["x"]+stage["size"]*catalog["master"]["anchorNormalized"][0],
                      stage["y"]+stage["size"]*catalog["master"]["anchorNormalized"][1]]
        for clip in catalog["clips"]:
            source=by_path[clip["atlas"]]
            metadata,_=checked_json(ROOT/clip["frameRegions"]["path"],clip["frameRegions"]["sha256"])
            factor=source_to_stage_factor(metadata["canvas"]["width"],clip["scale"],stage["width"],stage["size"]/stage["width"])
            indices=clip.get("frameIndices",list(range(clip["frameCount"])))
            measured=[]
            for frame in source["frames"]:
                result={"sourceFrame":frame["sourceFrame"],"actualUsed":frame["sourceFrame"] in indices,
                        "source":frame["source"],"flags":frame["flags"],"stage":None,"layouts":{}}
                if frame["source"]:
                    values={key:None if frame["source"][key] is None else frame["source"][key]*factor for key in METRICS}
                    source_frame=metadata["frames"][frame["sourceFrame"]]
                    values["faceCaliperPoints"]=[stage_point(p,source_frame,factor,stage_anchor) for p in frame["source"]["faceCaliperPoints"]]
                    values["eyeLowerRimPoints"]=[stage_point(p,source_frame,factor,stage_anchor) for p in frame["source"]["eyeLowerRimPoints"]]
                    result["stage"]=values
                    for style in layouts["layouts"]:
                        scale,x,y=style["characterTransform"]
                        result["layouts"][style["id"]]={"logicalPixels":{key:None if values[key] is None else values[key]*scale for key in METRICS},
                            "cssPixelsAt200Width":{key:None if values[key] is None else values[key]*scale*200/832 for key in METRICS},
                            "faceCaliperPoints":[[p[0]*scale+x,p[1]*scale+y] for p in values["faceCaliperPoints"]]}
                measured.append(result)
            reference=measured[source["referenceFrame"]]
            flags=[{"code":"anatomy-proxy-not-aesthetic-pass","severity":"notice","message":"臉部尺規仍受眼形、側傾及遮擋影響；不可單指標自動拉伸。"}]
            variations={}
            for key,label in METRICS.items():
                reference_value=reference["source"][key]
                if reference_value is None:continue
                variation_report={}
                for scope,selected in (("sourceAll",measured),("actualUsed",[f for f in measured if f["actualUsed"]])):
                    usable=[f for f in selected if f["source"] and f["source"][key] is not None]
                    values=[f["source"][key] for f in usable]
                    v=variation(values,reference_value,.08 if key!="eyeToFoot" else .10)
                    v["stagePixels"]={stat:v[stat]*factor for stat in ("min","max","mean")}
                    v["layoutPixels"]={style["id"]:{stat:v[stat]*factor*style["characterTransform"][0] for stat in ("min","max","mean")} for style in layouts["layouts"]}
                    v["measuredFrameCount"]=len(usable);v["totalFrameCount"]=len(selected)
                    v["flaggedSourceFrames"]=[f["sourceFrame"] for f in usable if abs(f["source"][key]/reference_value-1)>v["tolerance"]]
                    variation_report[scope]=v
                variations[key]=variation_report
                if variation_report["sourceAll"]["flagged"]:
                    flags.append({"code":"within-source-body-size-variation","severity":"warning","metric":key,
                                  "message":label+"跨幀差異超門檻；需分辨原畫變形、演出與量測遮擋，不自動修正。",
                                  "frameIndices":variation_report["sourceAll"]["flaggedSourceFrames"]})
            missing=[f["sourceFrame"] for f in measured if not f["source"]]
            if missing:flags.append({"code":"unmeasured-frames","severity":"warning","message":"部分影格無可靠臉部尺規，不能宣稱全幀尺寸通過。","frameIndices":missing})
            previous=before_by_id[clip["id"]]["scale"]
            report["clips"].append({"id":clip["id"],"title":clip["title"],"catalog":catalog_name,"atlas":clip["atlas"],
                "sourceSha256":clip["sha256"],"regionsSha256":clip["frameRegions"]["sha256"],"referenceFrame":source["referenceFrame"],
                "catalogScale":clip["scale"],
                "layoutApplicability":"all four layouts are active" if catalog_name=="catalog" else "candidate review uses classic only; other layout values are hypothetical comparisons",
                "sourcePixelToStagePixel":factor,"sourceFrameCount":source["frameCount"],"playbackFrameCount":len(indices),
                "actualUsedSourceFrames":sorted(set(indices)),"frameIndices":indices,
                "calibration":{"previousScale":previous,"currentScale":clip["scale"],"multiplier":clip["scale"]/previous,
                               "beforeReferenceStage":{key:None if reference["stage"][key] is None else reference["stage"][key]*previous/clip["scale"] for key in METRICS},
                               "reason":"One whole-clip multiplier only; no per-frame fit.","residualWarnings":[]},
                "measurements":{"unit":"px","labels":METRICS,"reference":reference,"variation":variations,
                                "eyeToFootUnavailableReason":source["footBaselineUnavailableReason"],
                                "confidence":"Six reference source frames have independent visual ROI review; per-frame automatic proposals remain expression/occlusion-sensitive, not a full manual anatomical annotation.",
                                "neutralTorsoWidth":None,"neutralTorsoWidthReason":source["neutralTorsoWidthUnavailableReason"]},
                "frames":measured,"flags":flags,"artApproval":False})
    master_reference=next(c for c in report["clips"] if c["id"]=="yawn")["measurements"]["reference"]["stage"]
    for clip in report["clips"]:
        values=clip["measurements"]["reference"]["stage"]
        clip["measurements"]["ratioToReference"]={key:None if values[key] is None else values[key]/master_reference[key] for key in METRICS}
        clip["measurements"]["comparisonReference"]={"clipId":"yawn","sourceFrame":0,
            "reason":"Existing direction-accepted neutral pose; a reference, not a mandate to equalize different anatomy or sitting poses."}
        clip["calibration"]["deviationToReference"]={key:{
            "beforeRatio":clip["calibration"]["beforeReferenceStage"][key]/master_reference[key],
            "afterRatio":values[key]/master_reference[key],
            "absoluteRelativeDeviationImproved":abs(values[key]/master_reference[key]-1)<abs(clip["calibration"]["beforeReferenceStage"][key]/master_reference[key]-1)
        } for key in METRICS if values[key] is not None}
        for key,ratio in clip["measurements"]["ratioToReference"].items():
            if ratio is not None and not .85<=ratio<=1.15:
                clip["flags"].append({"code":"cross-outfit-proportion-review","severity":"warning","metric":key,
                    "message":METRICS[key]+"與參考差超15%；需分辨鏡頭尺度、眼形、坐姿和原畫比例，不自動fit。"})
        clip["calibration"]["residualWarnings"]=[flag["code"] for flag in clip["flags"] if flag["severity"]=="warning"]
    report["totals"]={"uniqueSources":len(source_clips),"sourceFrames":sum(s["frameCount"] for s in report["sources"]),
                      "measuredSourceFrames":sum(s["measuredFrameCount"] for s in report["sources"]),
                      "unmeasuredSourceFrames":sum(s["frameCount"]-s["measuredFrameCount"] for s in report["sources"]),
                      "measuredSourceFramesByMetric":{key:sum(f["source"] is not None and f["source"][key] is not None for s in report["sources"] for f in s["frames"]) for key in METRICS},
                      "visuallyReviewedReferenceFrames":sum(bool(s["referenceVisualReview"]) for s in report["sources"]),
                      "clipVariants":len(report["clips"])}
    return report


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output",type=Path,default=DIRECTORY/"body-scale-audit.json")
    args=parser.parse_args()
    destination=args.output.resolve()
    if not destination.is_relative_to(DIRECTORY.resolve()) or destination.suffix!=".json":
        raise ValueError("report must be JSON within production-20261006-scale")
    report=make_report()
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"path":str(destination),**report["totals"]},ensure_ascii=False))


if __name__=="__main__":main()
