"""Re-measure the SHA-pinned transition revision; do not modify image pixels."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json

ROOT=Path(__file__).resolve().parents[2]
OUTPUT=ROOT/'animation/production-20261007-completion/focus-v7-qc.json'
spec=importlib.util.spec_from_file_location('reviewed_focus_measurement',ROOT/'animation/focus-v5/measure_review.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
base.SOURCE='animation/focus-v7/atlas-generated.png'
base.SOURCE_SHA='3a6a7cc2f463eb4537e0a36109505be7a6d7cbb5502a463dcb646aff2d89492e'
# Fresh white-component selections, independently checked in this PNG.
base.REFERENCE_EYES=[[242,121,276,155],[282,121,315,155]]

def make_report():
    report=base.make_report()
    previous_path=ROOT/'animation/production-20261006-followup/focus-v5-qc.json'
    previous_bytes=previous_path.read_bytes();previous=json.loads(previous_bytes)
    report.update(reviewedAt='2026-10-07',status='hand-transition-improved-body-proportion-unresolved',
                  catalogIntegrated=False,normalSpeedReview='pending-new-source-browser-review')
    report['previousV5']={'report':previous_path.relative_to(ROOT).as_posix(),
                          'sha256':hashlib.sha256(previous_bytes).hexdigest(),
                          'source':previous['source'],'summary':previous['summary']}
    report['methods']=[m for m in report['methods'] if 'Approximately3percent' not in m]
    report['methods'].append('Same reviewed measurement algorithm, fresh reference eye bounds and this source SHA. v5 results remain separate; no old numeric results transferred to new frames.')
    report['visualFindings']=[
        {'sourceFrames':[8,9,10],'kind':'improved','message':'An intermediate lowered hand now appears between cheek-level hand and notebook; real limb posture has changed.'},
        {'sourceFrames':[1,12],'kind':'remaining','message':'Neutral ending still has shorter visible eye-to-feet/head-to-feet proportions; face width stability does not establish body-height consistency.'},
        {'sourceFrames':[5,6,7,8],'kind':'measurement-unavailable','message':'Hand near face edge is conservatively excluded from semantic caliper tracking.'},
        {'sourceFrames':[10,11],'kind':'measurement-unavailable','message':'Thin eye-white rims/closed eyes are excluded; no invented eye coordinates.'},
        {'sourceFrames':list(range(1,13)),'kind':'preserve','message':'White sclera, pink closed lids, navy suit, glasses, notebook and both visible feet remain; all12 source frames are retained.'}]
    report['candidateValue']='Compare beside v5: explicit intermediate hand pose is useful, but ending body shortening and timing still need review. Not a completed main-catalog replacement.'
    return report

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    report=make_report();payload=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if OUTPUT.read_bytes()!=payload:raise ValueError('QC snapshot differs')
    else:OUTPUT.write_bytes(payload)
    print(json.dumps({'output':OUTPUT.relative_to(ROOT).as_posix(),'summary':report['summary'],'previousV5':report['previousV5']['summary']},ensure_ascii=False))
if __name__=='__main__':main()
