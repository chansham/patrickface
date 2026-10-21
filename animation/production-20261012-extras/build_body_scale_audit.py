"""Reuse source identity gates and descriptive shape comparison in a separate batch."""
from pathlib import Path
import argparse,importlib.util,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('extras_review_adapter',ROOT/'animation/production-20261012-playful/build_body_scale_audit.py')
core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)
core.HERE=HERE
def make_report():
    report=core.make_report()
    report['method']='source-pinned-extras-body-QC-adapter-v1'
    report['limitations'].insert(0,'眼鏡框、鏡片、球拍與冰淇淋不是人體尺規；白眼受鏡框、書或道具遮擋時留未知，不量道具外輪廓。')
    return report
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--check',action='store_true');args=parser.parse_args()
    report=make_report();payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';target=HERE/'body-scale-audit.json'
    if args.check:
        if target.read_text(encoding='utf-8')!=payload:raise ValueError('extras body audit stale')
    else:target.write_text(payload,encoding='utf-8')
    print(json.dumps({'totals':report['totals'],'shapeProxies':report['anatomicalProxySummary']},ensure_ascii=False))
