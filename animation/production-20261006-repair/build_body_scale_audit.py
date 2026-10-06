"""Adapt reviewed repair QC into the size-review schema; never infer anatomy.

Run with python -B. Only body-scale-audit.json beside this script is written.
--check compares the generated report without writing anything.
"""
from pathlib import Path
import argparse
import hashlib
import json
import math
import re

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = Path(__file__).resolve().parent
OUTPUT = DIRECTORY / "body-scale-audit.json"
METRICS = ("faceWidth", "eyeSeparation", "eyeToFoot")
SPECS = (
    ("focus-repair-20261006", "animation/focus-v2/atlas-generated.png",
     "7ee112183d2c9e5d911bf89cedc8b4afba705f6a72659838410daa934939322f", "focus-v2-qc.json", "focus"),
    ("chef-repair-20261006", "animation/feeding-chef-v2/atlas-generated.png",
     "cf5115d199e0d0cbc8bac8983cec04fed215dcb4bafc0734e8e6bad9dbbfa8a0", "feeding-chef-v2-qc.json", "chef"),
    ("exercise-repair-20261006", "animation/exercise-v3/atlas-generated.png",
     "0a3fdcd7fc489fb89457b76145ce3e249f2a401c3ffc0a1a566872cb7da1627f", None, "exercise"),
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    payload=path.read_bytes()
    return json.loads(payload.decode("utf-8-sig")),digest(payload)


def project_file(relative):
    path=ROOT/relative
    if not path.resolve().is_relative_to(ROOT.resolve()) or path.is_symlink():
        raise ValueError("resource escapes project or is a symbolic link")
    return path


def number(value):
    return isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value)


def convert_source(row,kind):
    result={key:None for key in METRICS}
    if kind=="exercise":
        result["unavailableReason"]="此新來源沒有已覆核的人體尺規；定位資料不能充當臉寬或人體高度。"
        return result
    mapping={"faceWidth":"faceWidthPx","eyeSeparation":"eyeLowerRimSeparationPx",
             "eyeToFoot":"eyeLineToFootPx" if kind=="focus" else "eyeLineToActualFootPx"}
    for target,source in mapping.items():
        value=row.get(source)
        if value is not None and (not number(value) or value<=0):
            raise ValueError(f"invalid reviewed metric {source}")
        result[target]=value
    for key in ("eyeWhiteBounds","eyeLowerRimPoints","faceCaliperPoints"):
        if row.get(key) is not None:result[key]=row[key]
    eyes=result.get("eyeLowerRimPoints")
    if result["eyeSeparation"] is not None:
        if not eyes or len(eyes)!=2 or abs(math.dist(*eyes)-result["eyeSeparation"])>1e-6:
            raise ValueError("eye metric and recorded source-coordinate points disagree")
    if result["faceWidth"] is not None and len(result.get("faceCaliperPoints",[]))!=2:
        raise ValueError("face metric has no source caliper")
    if eyes:
        midpoint=[sum(p[axis] for p in eyes)/2 for axis in (0,1)]
        result["eyeMidpoint"]=midpoint
        result["eyeLineAngleDegrees"]=math.degrees(math.atan2(eyes[1][1]-eyes[0][1],eyes[1][0]-eyes[0][0]))
    if kind=="chef":
        result["visibleFootPinkFillBounds"]=row.get("visibleFootPinkFillBounds",[])
        result["footBaselineY"]=row.get("visibleFootBaselineY")
        result["footBaselineMethod"]="已檢視的兩個粉色腳部填色下緣；不使用坐墊底。"
    if result["eyeToFoot"] is not None:
        if not eyes:raise ValueError("body proxy without recorded eye coordinates")
        # These are already reviewed source-QC baselines, not new bbox guesses.
        foot_y=row["visibleFootBaselineY"] if kind=="chef" else row["anchorSource"][1]
        if not number(foot_y) or abs(foot_y-midpoint[1]-result["eyeToFoot"])>1e-6:
            raise ValueError("eye-to-foot metric and true-foot source baseline disagree")
        result["footBaselineY"]=foot_y
        result["footSourcePoint"]=[midpoint[0],foot_y]
        result["eyeToFootPoints"]=[midpoint,result["footSourcePoint"]]
        result["footPointMeaning"]="眼中線投影至已覆核足底水平基線；不表示此x座標上一定有一隻腳。"
        if kind=="focus":result["footBaselineMethod"]="本來源QC已檢視的可見雙腳落地基線。"
    for key in ("unavailableReason","eyeUnavailableReason","faceWidthUnavailableReason","footUnavailableReason"):
        if row.get(key):result[key]=row[key]
    result["edgeSamplingUncertaintySourcePixels"]=2
    return result


def make_report():
    catalog,catalog_sha=read_json(ROOT/"animation/candidates.json")
    layouts,layouts_sha=read_json(ROOT/"experience/layouts.json")
    player=(ROOT/"preview/player-core.js").read_bytes()
    match=re.search(r"export const STAGE = Object\.freeze\(\{([^}]+)\}\)",player.decode("utf-8-sig"))
    if not match:raise ValueError("cannot read actual renderer stage constants")
    stage={key:float(value) for key,value in re.findall(r"(\w+)\s*:\s*([\d.]+)",match.group(1))}
    if not all(key in stage for key in ("width","height","x","y","size")):raise ValueError("incomplete stage")
    master=catalog["master"]["anchorNormalized"]
    target=[stage["x"]+stage["size"]*master[0],stage["y"]+stage["size"]*master[1]]
    clips=[];sources=[];provenance=[]
    for clip_id,path,expected_sha,qc_name,kind in SPECS:
        matching=[c for c in catalog["clips"] if c["id"]==clip_id]
        if len(matching)!=1:raise ValueError("candidate identity missing or duplicated")
        clip=matching[0]
        if clip["atlas"]!=path or clip["sha256"]!=expected_sha or digest(project_file(path).read_bytes())!=expected_sha:
            raise ValueError("reviewed source/candidate SHA drift")
        regions,regions_sha=read_json(project_file(clip["frameRegions"]["path"]))
        if regions_sha!=clip["frameRegions"]["sha256"] or regions["source"]!={"path":path,"sha256":expected_sha,"width":clip["width"],"height":clip["height"]}:
            raise ValueError("reviewed source/regions identity drift")
        n=regions["canvas"]["width"]
        if regions["canvas"]["height"]!=n or not number(clip["scale"]) or clip["scale"]<=0:
            raise ValueError("expected one square canvas and one positive clip scale")
        frame_ids=clip.get("frameIndices",list(range(clip["frameCount"])))
        if len(frame_ids)!=clip["frameCount"] or any(type(i)!=int or not 0<=i<len(regions["frames"]) for i in frame_ids):
            raise ValueError("invalid actual-used source frame order")
        qc_rows=None;qc_reference=None
        if qc_name:
            qc,qc_sha=read_json(DIRECTORY/qc_name)
            data=qc["new"] if kind=="chef" else qc
            if data["source"]!=regions["source"] or data["regions"]["sha256"]!=regions_sha:
                raise ValueError("independent QC source/regions SHA drift")
            qc_rows=data["frames"]
            if [r["sourceFrame"] for r in qc_rows]!=list(range(1,len(regions["frames"])+1)):
                raise ValueError("QC must contain complete, unique one-based source frame order")
            qc_reference={"path":(DIRECTORY/qc_name).relative_to(ROOT).as_posix(),"sha256":qc_sha}
            provenance.append(qc_reference)
        factor=stage["size"]*clip["scale"]/n
        frames=[]
        for i,region in enumerate(regions["frames"]):
            reviewed=qc_rows[i] if qc_rows else {}
            if reviewed and reviewed["anchorSource"]!=region["anchorSource"]:
                raise ValueError("QC frame anchor no longer matches source regions")
            source=convert_source(reviewed,kind)
            for key in ("eyeLowerRimPoints","faceCaliperPoints","eyeToFootPoints"):
                for point in source.get(key,[]):
                    if len(point)!=2 or not all(number(v) for v in point) or not(0<=point[0]<=clip["width"] and 0<=point[1]<=clip["height"]):
                        raise ValueError("semantic source coordinate out of source bounds")
            point=lambda p:[target[j]+(p[j]-region["anchorSource"][j])*factor for j in (0,1)]
            mapped={key:None if source[key] is None else source[key]*factor for key in METRICS}
            for key in ("eyeLowerRimPoints","faceCaliperPoints","eyeToFootPoints"):
                if key in source:mapped[key]=[point(p) for p in source[key]]
            if "footSourcePoint" in source:mapped["footSourcePoint"]=point(source["footSourcePoint"])
            by_layout={}
            for layout in layouts["layouts"]:
                scale,tx,ty=layout["characterTransform"]
                values={key:None if mapped[key] is None else mapped[key]*scale for key in METRICS}
                transformed={"logicalPixels":values,"cssPixelsAt200Width":{key:None if value is None else value*200/stage["width"] for key,value in values.items()}}
                for key in ("eyeLowerRimPoints","faceCaliperPoints","eyeToFootPoints"):
                    if key in mapped:transformed[key]=[[p[0]*scale+tx,p[1]*scale+ty] for p in mapped[key]]
                by_layout[layout["id"]]=transformed
            missing=[key for key in METRICS if source[key] is None]
            frames.append({"sourceFrame":i,"actualUsed":i in frame_ids,"source":source,"stage":mapped,"layouts":by_layout,
                           "flags":[] if not missing else [{"code":"unmeasured-metrics","metrics":missing,"message":"沒有可靠尺規的欄位維持空值，不以人物外框補猜。"}],
                           "alignmentEvidence":{"anchorSource":region["anchorSource"],"translation":region["translation"],"canvasAnchorPixels":regions["canvas"]["anchorPixels"],"notAnatomicalMeasurement":True}})
        flag={"focus":{"code":"body-proportion-not-resolved","severity":"warning","message":"最後一列軀幹仍較短；本體比例未修好。","frameIndices":[12,13,14,15]},
              "chef":{"code":"cookie-restored-whole","severity":"warning","message":"第12格餅乾仍恢復完整，故事缺陷未修。","frameIndices":[11]},
              "exercise":{"code":"anatomical-landmarks-unmeasured","severity":"warning","message":"新運動畫稿只有定位核查，尚無獨立人體尺規；三項人體數值全部留空。","frameIndices":list(range(len(frames)))}}[kind]
        labels={"faceWidth":"眼下緣線可見臉部橫截寬","eyeSeparation":"兩眼下緣中點距離（非瞳孔距）","eyeToFoot":"眼下緣中線至真足底垂直距離（姿勢代理）"}
        entry={"id":clip_id,"title":clip["title"],"catalog":"candidates","atlas":path,"sourceSha256":expected_sha,
               "regionsSha256":regions_sha,"referenceFrame":0,"catalogScale":clip["scale"],
               "sourcePixelToStagePixel":factor,"sourceFrameCount":len(frames),"playbackFrameCount":clip["frameCount"],
               "actualUsedSourceFrames":sorted(set(frame_ids)),"frameIndices":frame_ids,
               "calibration":{"currentScale":clip["scale"],"reason":"沿用目前目錄單一整段倍率；不作逐格fit或人體自動校準。"},
               "measurements":{"unit":"px","labels":labels,"reference":frames[0]},"frames":frames,"flags":[flag],
               "artApproval":False,"measurementProvenance":qc_reference,
               "alignmentEvidence":{"supportAnchorPolicy":regions.get("diagnostics",{}).get("supportAnchorPolicy"),"notAnatomicalMeasurement":True}}
        clips.append(entry);sources.append({"path":path,"sha256":expected_sha,"sourceFrames":len(frames),"qc":qc_reference})
    all_frames=[f for c in clips for f in c["frames"]]
    measured=sum(any(f["source"][key] is not None for key in METRICS) for f in all_frames)
    return {"schemaVersion":1,"generatedAt":"2026-10-06","artApproval":False,
            "method":"source-pinned-reviewed-QC-adapter-v1","frameIndexBasis":"zero-based","coordinateSize":[stage["width"],stage["height"]],
            "catalogPath":"animation/candidates.json","catalogSha256":catalog_sha,"layoutsSha256":layouts_sha,
            "playerCoreSha256":digest(player),"stageConstants":stage,"sourceReports":provenance,"sources":sources,"clips":clips,
            "limitations":["本報告獨立於既有172格報告，只提供本輪三個候選；美術仍未批准。",
                           "可見臉横截、眼下緣間距與眼足距是姿勢／表情代理，並非完整頭部或裸軀幹模型。",
                           "廚師真足底與坐墊落位分開；尺線必須使用eyeToFootPoints/footSourcePoint，不能接到region anchor。",
                           "遮擋、閉眼或不可靠欄位保持null；新運動素材只有定位證據，不借用舊圖人體landmarks。",
                           "每個clip固定一個scale；來源RGB/alpha、輪廓、播放格序与舊報告未修改。"],
            "totals":{"uniqueSources":3,"sourceFrames":len(all_frames),"clipVariants":3,"measuredSourceFrames":measured,
                      "unmeasuredSourceFrames":len(all_frames)-measured,
                      "measuredSourceFramesByMetric":{key:sum(f["source"][key] is not None for f in all_frames) for key in METRICS}}}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument("--check",action="store_true");args=parser.parse_args()
    report=make_report();payload=(json.dumps(report,ensure_ascii=False,indent=2)+"\n").encode("utf-8")
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes()!=payload:raise ValueError("repair audit is not current; regenerate explicitly")
    else:OUTPUT.write_bytes(payload)
    print(json.dumps({"output":OUTPUT.relative_to(ROOT).as_posix(),"sha256":digest(payload),"totals":report["totals"],"readOnlyCheck":args.check},ensure_ascii=False))


if __name__=="__main__":main()
