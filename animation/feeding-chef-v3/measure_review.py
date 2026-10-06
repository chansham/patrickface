"""Source-pinned comparison of the targeted v3 edit against v2."""
from pathlib import Path
import importlib.util
import json

from compare_drift import compare

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location("chef_v2_measure",ROOT/"animation/feeding-chef-v2/measure_review.py")
measure=importlib.util.module_from_spec(spec)
spec.loader.exec_module(measure)


def main():
    old=measure.analyze("feeding-chef-v2","cf5115d199e0d0cbc8bac8983cec04fed215dcb4bafc0734e8e6bad9dbbfa8a0",[[130,118,161,169],[161,118,196,170]],{6,8})
    new=measure.analyze("feeding-chef-v3","b2cd3055bba7d1c2097ad52eddb0bfc61041c2dd7fc2e06bc91a3f9218509b67",[[130,118,161,169],[161,118,196,170]],{6,8})
    prior=json.loads((ROOT/"animation/production-20261006-repair/feeding-chef-v2-qc.json").read_bytes())
    keys=["coreWidthPx","coreHeightPx","hatWhiteFillWidthPx","hatWhiteFillHeightPx","faceWidthPx","eyeLowerRimSeparationPx","eyeLineToActualFootPx"]
    drift=compare("feeding-chef-v2","feeding-chef-v3")
    report={"schemaVersion":1,"reviewedAt":"2026-10-06","frameIndexBasis":"one-based",
            "status":"targeted-cookie-revision-not-achieved","artApproved":False,"catalogIntegrated":False,
            "normalSpeedReview":"not-performed","source":new["source"],"sourceUnchanged":True,
            "regions":new["regions"],"canvas":new["canvas"],"coverage":new["coverage"],
            "old":old,"new":new,"methods":prior["methods"],
            "oldNewFirstFrame":{key:measure.delta(old["frames"][0][key],new["frames"][0][key]) for key in keys},
            "newFirstLastFrame":{key:measure.delta(new["frames"][0][key],new["frames"][-1][key]) for key in keys},
            "sourcePixelDrift":drift,
            "visualFindings":[
                {"sourceFrames":[12],"kind":"defect-persists","sourceInspectionRect":[1040,1080,1140,1180],
                 "message":"Correct-alpha5x nearest-neighbor inspection alongside v2 shows a whole oval cookie on the plate. The slightly uneven left edge is not the clear missing bite from frames6-11. Requested targeted repair was not achieved."},
                {"sourceFrames":list(range(1,12)),"kind":"unrequested-pixel-drift",
                 "message":"All11 non-target frames have changed RGBA pixels after integer anchor registration. Strong silhouettes remain close, with only0-2px width and-1..1px height changes. Do not claim exact preservation or assume all pixel changes are visually harmful."},
                {"sourceFrames":list(range(1,13)),"kind":"preserved-with-small-variation",
                 "message":"Mint costume, white eyes/pink eyelids, enlarged face, shorter hat, feet and story poses closely resemble v2. The existing5-to6 bite-release transition still needs live-speed review."}],
            "recommendation":"Retain both sources as evidence; prefer v2 over calling this a successful targeted edit. Cookie redraw remains necessary; no main integration approval."}
    destination=ROOT/"animation/production-20261006-repair/feeding-chef-v3-qc.json"
    destination.write_text(json.dumps(report,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
    print(json.dumps({"report":destination.relative_to(ROOT).as_posix(),"summary":new["summary"],"oldNewFirstFrame":report["oldNewFirstFrame"],"newFirstLastFrame":report["newFirstLastFrame"]},ensure_ascii=False))


if __name__=="__main__":main()
