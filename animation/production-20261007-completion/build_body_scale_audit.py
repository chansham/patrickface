"""Adapt independently reviewed 2026-10-07 completion QC; never infer unmeasured anatomy.

Run with python -B. Writes only the adjacent body-scale-audit.json.
--check reproduces the snapshot without writing; --test runs adapter fixtures.
Missing catalog entries or unpublished QC fail before any output is written.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import json
import math
import re

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = Path(__file__).resolve().parent
OUTPUT = DIRECTORY / "body-scale-audit.json"
METRICS = ("faceWidth", "eyeSeparation", "eyeToFoot")
SPECS = (
    ("chef-cookie-repair-20261007", "animation/feeding-chef-v6/atlas-generated.png",
     "cd432cf83e782c99eed61f496cc8ab1cdd50559f95401f1b1c576ec1037cdc80", "feeding-chef-v6-qc.json", "chef"),
    ("focus-transition-repair-20261007", "animation/focus-v7/atlas-generated.png",
     "3a6a7cc2f463eb4537e0a36109505be7a6d7cbb5502a463dcb646aff2d89492e", "focus-v7-qc.json", "focus"),
    ("charging-cozy-20261007", "animation/charging-cozy-v2/atlas-generated.png",
     "993feacbb4e57dc9acd393be690e3f96321bf543921c2ccb5b971cd617fae194", "charging-cozy-v2-qc.json", "cozy"),
)


def digest(data):
    return hashlib.sha256(data).hexdigest()


def read_json(path):
    payload = path.read_bytes()
    return json.loads(payload.decode("utf-8-sig")), digest(payload)


def project_file(relative):
    path = ROOT / relative
    if path.is_symlink() or not path.resolve().is_relative_to(ROOT.resolve()):
        raise ValueError("resource escapes project or is a symbolic link")
    return path


def number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def validate_identity(clip, path, expected_sha, actual_sha, regions, regions_sha, qc):
    if clip["atlas"] != path or clip["sha256"] != expected_sha or actual_sha != expected_sha:
        raise ValueError("reviewed source/candidate SHA drift")
    source = {"path": path, "sha256": expected_sha, "width": clip["width"], "height": clip["height"]}
    if regions_sha != clip["frameRegions"]["sha256"] or regions["source"] != source:
        raise ValueError("reviewed source/regions identity drift")
    if qc["source"] != source or qc["regions"]["sha256"] != regions_sha or qc["regions"]["path"] != clip["frameRegions"]["path"]:
        raise ValueError("independent QC source/regions SHA drift")
    if [r["sourceFrame"] for r in qc["frames"]] != list(range(1, len(regions["frames"]) + 1)):
        raise ValueError("QC requires complete, unique one-based source frame order")


def convert_source(row, kind):
    mapping = {"faceWidth": "faceWidthPx", "eyeSeparation": "eyeLowerRimSeparationPx", "eyeToFoot": "eyeLineToFootPx"}
    result = {key: row.get(name) for key, name in mapping.items()}
    for value in result.values():
        if value is not None and (not number(value) or value <= 0):
            raise ValueError("invalid reviewed metric")
    if kind == "running" and result["eyeToFoot"] is not None:
        raise ValueError("running has no independently verified anatomical foot baseline")
    for key in ("eyeWhiteBounds", "eyeLowerRimPoints", "faceCaliperPoints"):
        if row.get(key) is not None:
            result[key] = row[key]
    eyes = result.get("eyeLowerRimPoints")
    if result["eyeSeparation"] is not None:
        if not eyes or len(eyes) != 2 or abs(math.dist(*eyes) - result["eyeSeparation"]) > 1e-6:
            raise ValueError("eye metric and source-coordinate points disagree")
    if result["faceWidth"] is not None and len(result.get("faceCaliperPoints", [])) != 2:
        raise ValueError("face metric has no source caliper")
    if eyes:
        midpoint = [sum(p[axis] for p in eyes) / 2 for axis in (0, 1)]
        result["eyeMidpoint"] = midpoint
        result["eyeLineAngleDegrees"] = math.degrees(math.atan2(eyes[1][1] - eyes[0][1], eyes[1][0] - eyes[0][0]))
    if result["eyeToFoot"] is not None:
        if not eyes:
            raise ValueError("body proxy without recorded eye coordinates")
        # Actual reviewed feet, never the renderer's lower silhouette/support anchor.
        foot_y = row.get("visibleFootBaselineY")
        if not number(foot_y) or abs(foot_y - midpoint[1] - result["eyeToFoot"]) > 1e-6:
            raise ValueError("eye-to-foot metric and true-foot source baseline disagree")
        endpoint = [midpoint[0], foot_y]
        if row.get("footSourcePoint") != endpoint or row.get("eyeToFootPoints") != [midpoint, endpoint]:
            raise ValueError("reviewed eye-to-foot endpoints are absent or inconsistent")
        result.update(footBaselineY=foot_y, footSourcePoint=endpoint, eyeToFootPoints=[midpoint, endpoint],
                      visibleFootPinkFillBounds=row.get("visibleFootPinkFillBounds", []),
                      footBaselineMethod="本來源逐格覆核的兩個粉色腳部填色下緣，與輪廓落位基線分開。",
                      footPointMeaning="眼中線投影至已覆核足底水平基線；不表示此x座標上一定有一隻腳。")
    for key in ("unavailableReason", "eyeUnavailableReason", "faceWidthUnavailableReason", "footUnavailableReason"):
        if row.get(key):
            result[key] = row[key]
    if kind == "running":
        result["footUnavailableReason"] = "跑步支撐腳與抬腳姿勢變化；沒有可可靠比較的人體足底基準，全部眼足距留空。"
    result["edgeSamplingUncertaintySourcePixels"] = 2
    return result


def make_report():
    catalog, catalog_sha = read_json(ROOT / "animation/candidates.json")
    layouts, layouts_sha = read_json(ROOT / "experience/layouts.json")
    player = (ROOT / "preview/player-core.js").read_bytes()
    match = re.search(r"export const STAGE = Object\.freeze\(\{([^}]+)\}\)", player.decode("utf-8-sig"))
    if not match:
        raise ValueError("cannot read actual renderer stage constants")
    stage = {key: float(value) for key, value in re.findall(r"(\w+)\s*:\s*([\d.]+)", match.group(1))}
    if not all(key in stage for key in ("width", "height", "x", "y", "size")):
        raise ValueError("incomplete renderer stage")
    target = [stage["x"] + stage["size"] * catalog["master"]["anchorNormalized"][0],
              stage["y"] + stage["size"] * catalog["master"]["anchorNormalized"][1]]
    clips = []; sources = []; provenance = []
    for clip_id, path, expected_sha, qc_name, kind in SPECS:
        matches = [c for c in catalog["clips"] if c["id"] == clip_id]
        if len(matches) != 1:
            raise ValueError(f"candidate not integrated or duplicated: {clip_id}; no output written")
        clip = matches[0]
        regions, regions_sha = read_json(project_file(clip["frameRegions"]["path"]))
        qc, qc_sha = read_json(DIRECTORY / qc_name)
        validate_identity(clip, path, expected_sha, digest(project_file(path).read_bytes()), regions, regions_sha, qc)
        n = regions["canvas"]["width"]
        if regions["canvas"]["height"] != n or not number(clip["scale"]) or clip["scale"] <= 0:
            raise ValueError("expected one square canvas and one positive clip scale")
        frame_ids = clip.get("frameIndices", list(range(clip["frameCount"])))
        if len(frame_ids) != clip["frameCount"] or any(type(i) != int or not 0 <= i < len(regions["frames"]) for i in frame_ids):
            raise ValueError("invalid source frame order")
        qc_ref = {"path": (DIRECTORY / qc_name).relative_to(ROOT).as_posix(), "sha256": qc_sha}
        provenance.append(qc_ref)
        factor = stage["size"] * clip["scale"] / n
        frames = []
        for i, region in enumerate(regions["frames"]):
            row = qc["frames"][i]
            if row.get("anchorSource") != region["anchorSource"]:
                raise ValueError("QC alignment is stale")
            source = convert_source(row, kind)
            for key in ("eyeLowerRimPoints", "faceCaliperPoints", "eyeToFootPoints"):
                for p in source.get(key, []):
                    if len(p) != 2 or not all(number(v) for v in p) or not (0 <= p[0] <= clip["width"] and 0 <= p[1] <= clip["height"]):
                        raise ValueError("semantic point outside source")
            mapped = {key: None if source[key] is None else source[key] * factor for key in METRICS}
            for key in ("eyeLowerRimPoints", "faceCaliperPoints", "eyeToFootPoints"):
                if key in source:
                    mapped[key] = [[target[j] + (p[j] - region["anchorSource"][j]) * factor for j in (0, 1)] for p in source[key]]
            if "footSourcePoint" in source:
                mapped["footSourcePoint"] = mapped["eyeToFootPoints"][1]
            by_layout = {}
            for layout in layouts["layouts"]:
                scale, tx, ty = layout["characterTransform"]
                values = {key: None if mapped[key] is None else mapped[key] * scale for key in METRICS}
                transformed = {"logicalPixels": values, "cssPixelsAt200Width": {key: None if value is None else value * 200 / stage["width"] for key, value in values.items()}}
                for key in ("eyeLowerRimPoints", "faceCaliperPoints", "eyeToFootPoints"):
                    if key in mapped:
                        transformed[key] = [[p[0] * scale + tx, p[1] * scale + ty] for p in mapped[key]]
                by_layout[layout["id"]] = transformed
            missing = [key for key in METRICS if source[key] is None]
            frames.append({"sourceFrame": i, "actualUsed": i in frame_ids, "source": source, "stage": mapped, "layouts": by_layout,
                           "flags": [] if not missing else [{"code": "unmeasured-metrics", "metrics": missing, "message": "沒有可靠尺規的欄位維持空值，不以人物外框補猜。"}],
                           "alignmentEvidence": {"anchorSource": region["anchorSource"], "translation": region["translation"], "canvasAnchorPixels": regions["canvas"]["anchorPixels"], "notAnatomicalMeasurement": True}})
        flags = [{"code": "body-proportion-not-resolved", "severity": "warning", "message": "正裝收手多一格過渡；首末眼線至真足底仍短約5.19%，不算身形修妥。", "frameIndices": [9, 10, 11]}] if kind == "focus" else (
            [{"code": "cookie-continuity-improved", "severity": "info", "message": "最後餅乾保留咬痕；5→6出嘴收手仍需正常速度審閱。", "frameIndices": [4, 5, 11]},
             {"code": "minor-face-drift", "severity": "warning", "message": "首末臉部横截約+3.26%；小幅原畫變化仍待審，不逐格縮放補償。"}] if kind == "chef" else
            [{"code": "tilt-transition-review", "severity": "warning", "message": "v2補第7、9格傾頭中間姿勢，仍需審閱；拖鞋遮住真腳底，全部眼足距留空。", "frameIndices": [6, 7]}])
        labels = {"faceWidth": "眼下緣線可見臉部橫截寬", "eyeSeparation": "兩眼下緣中點距離（非瞳孔距）", "eyeToFoot": "眼下緣中線至真足底垂直距離（姿勢代理）"}
        clips.append({"id": clip_id, "title": clip["title"], "catalog": "candidates", "atlas": path,
                      "sourceSha256": expected_sha, "regionsSha256": regions_sha, "referenceFrame": 0, "catalogScale": clip["scale"],
                      "sourcePixelToStagePixel": factor, "sourceFrameCount": len(frames), "playbackFrameCount": clip["frameCount"],
                      "actualUsedSourceFrames": sorted(set(frame_ids)), "frameIndices": frame_ids,
                      "calibration": {"currentScale": clip["scale"], "reason": "讀取目錄目前單一整段倍率；不作逐格fit或自動人体校準。"},
                      "measurements": {"unit": "px", "labels": labels, "reference": frames[0]}, "frames": frames, "flags": flags,
                      "artApproval": False, "measurementProvenance": qc_ref,
                      "alignmentEvidence": {"supportAnchorPolicy": regions.get("diagnostics", {}).get("supportAnchorPolicy"), "notAnatomicalMeasurement": True}})
        sources.append({"path": path, "sha256": expected_sha, "sourceFrames": len(frames), "qc": qc_ref})
    all_frames = [f for c in clips for f in c["frames"]]
    measured = sum(any(f["source"][key] is not None for key in METRICS) for f in all_frames)
    return {"schemaVersion": 1, "generatedAt": "2026-10-08", "artApproval": False,
            "method": "source-pinned-reviewed-completion-QC-adapter-v1", "frameIndexBasis": "zero-based", "coordinateSize": [stage["width"], stage["height"]],
            "catalogPath": "animation/candidates.json", "catalogSha256": catalog_sha, "layoutsSha256": layouts_sha,
            "playerCoreSha256": digest(player), "stageConstants": stage, "sourceReports": provenance, "sources": sources, "clips": clips,
            "limitations": ["本報告僅涵蓋10/7廚師、正裝與睡衣充電三份新來源，共36格；舊報告不改，美術均未批准。",
                            "三項數字是姿勢／表情代理，不是完整頭部、裸軀幹或骨架模型。",
                            "廚師與正裝真腳填色基線與輪廓落位基線分開，必須使用eyeToFootPoints；新睡衣被拖鞋遮住真腳，全部眼足距留空。",
                            "遮擋、閉眼、側身或不可靠追蹤保持null，不借用舊圖座標或全人物外框。",
                            "只讀原PNG；每段沿用一個目錄scale。量測不會自動改倍率或批准美術。"],
            "totals": {"uniqueSources": len(clips), "sourceFrames": len(all_frames), "clipVariants": len(clips), "measuredSourceFrames": measured,
                       "unmeasuredSourceFrames": len(all_frames) - measured,
                       "measuredSourceFramesByMetric": {key: sum(f["source"][key] is not None for f in all_frames) for key in METRICS}}}


def fixtures():
    def rejects(fn):
        try:
            fn()
        except ValueError:
            return
        raise AssertionError("expected rejection")
    row = {"faceWidthPx": 20, "faceCaliperPoints": [[5, 20], [25, 20]], "eyeLowerRimSeparationPx": 10,
           "eyeLowerRimPoints": [[10, 20], [20, 20]], "eyeLineToFootPx": 30, "visibleFootBaselineY": 50,
           "footSourcePoint": [15, 50], "eyeToFootPoints": [[15, 20], [15, 50]], "anchorSource": [15, 55]}
    got = convert_source(row, "focus")
    assert got["footSourcePoint"] == [15, 50] and got["footSourcePoint"][1] != row["anchorSource"][1]
    assert all(convert_source({}, "focus")[key] is None for key in METRICS)
    rejects(lambda: convert_source({**row, "visibleFootBaselineY": 55}, "focus"))
    rejects(lambda: convert_source({**row, "eyeLowerRimSeparationPx": 12}, "focus"))
    rejects(lambda: convert_source(row, "running"))
    source = {"path": "x.png", "sha256": "abc", "width": 50, "height": 50}
    clip = {"atlas": "x.png", "sha256": "abc", "width": 50, "height": 50, "frameRegions": {"path": "r.json", "sha256": "reg"}}
    regions = {"source": source, "frames": [{}]}
    qc = {"source": source, "regions": {"path": "r.json", "sha256": "reg"}, "frames": [{"sourceFrame": 1}]}
    validate_identity(clip, "x.png", "abc", "abc", regions, "reg", qc)
    rejects(lambda: validate_identity(clip, "x.png", "abc", "drift", regions, "reg", qc))
    bad = copy.deepcopy(qc); bad["regions"]["sha256"] = "drift"
    rejects(lambda: validate_identity(clip, "x.png", "abc", "abc", regions, "reg", bad))
    bad = copy.deepcopy(qc); bad["frames"][0]["sourceFrame"] = 0
    rejects(lambda: validate_identity(clip, "x.png", "abc", "abc", regions, "reg", bad))
    print(json.dumps({"fixtures": 8, "passed": 8, "writes": 0}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(); group.add_argument("--check", action="store_true"); group.add_argument("--test", action="store_true")
    args = parser.parse_args()
    if args.test:
        fixtures(); return
    report = make_report(); payload = (json.dumps(report, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    if args.check:
        if not OUTPUT.exists() or OUTPUT.read_bytes() != payload:
            raise ValueError("completion audit is not current; regenerate explicitly")
    else:
        OUTPUT.write_bytes(payload)
    print(json.dumps({"output": OUTPUT.relative_to(ROOT).as_posix(), "sha256": digest(payload), "totals": report["totals"], "readOnlyCheck": args.check}, ensure_ascii=False))


if __name__ == "__main__":
    main()
