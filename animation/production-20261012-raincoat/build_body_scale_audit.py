"""Adapt this batch's source-pinned measurements to the existing review-page contract."""
from pathlib import Path
import argparse,hashlib,importlib.util,json
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('completion_adapter',ROOT/'animation/production-20261007-completion/build_body_scale_audit.py')
base=importlib.util.module_from_spec(spec);spec.loader.exec_module(base)
base.DIRECTORY=HERE
base.SPECS=(('raincoat-first-20261012','animation/raincoat-v1/atlas-generated.png','755d73b3e23149a1c82498f9103be1b7a3f80b42214a70890b7d44d08181f42b','raincoat-v1-qc.json','raincoat'),
            ('raincoat-seated-20261012','animation/raincoat-v2/atlas-generated.png','dc4cb4f2d66bb7d6cc56291003214a911e51f8f75bccd83cbcc42d68ebc08410','raincoat-v2-qc.json','raincoat'))
def make_report():
    report=base.make_report();report.update(generatedAt='2026-10-12',method='source-pinned-raincoat-pose-QC-adapter-v1',outfitCount=1,poseVariants=2)
    report['limitations']=['同一套黃色雨衣／藍傘，站姿與坐姿各8格；兩個姿態選項，不當作兩套衣服。',
                          '使用者喜歡站姿造型，動畫幀／動作仍未批准。站姿為保持完整高傘，臉呈現比主睡衣小約26.6%；坐姿約小2.66%。',
                          '兩者第6來源格闭眼，臉截線、眼下緣距、眼足距全部null；不填猜測數。',
                          '真腳填色下緣是可見姿勢代理，不等於角色高度；傘面／雨衣外框／輪廓落位anchor不是人體尺規。',
                          '來源RGBA原樣保留；每個姿態整段共用一個倍率、畫布和落位基線，沒有逐幀fit。',
                          '頭尖部分被傘遮住，完整裸頭高／骨架尺寸未知；表情改變會影響臉截線與眼下緣尺規。']
    for clip in report['clips']:
        clip['flags']=[{'code':'animation-transitions-pending','severity':'warning','message':'抬手、收手與閉眼表情之間缺過渡，首末非完全無縫；新造型不等於動畫完成。','frameIndices':[3,4,5,6,7]}]
        if clip['id']=='raincoat-first-20261012':clip['flags'].append({'code':'smaller-visible-body','severity':'warning','message':'保留使用者偏好的站姿高傘；臉呈現較主睡衣小約26.6%，不是同人體倍率。'})
    return report
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();report=make_report();raw=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8');out=HERE/'body-scale-audit.json'
    if args.check:
        if out.read_bytes()!=raw:raise ValueError('raincoat body audit stale')
    else:out.write_bytes(raw)
    print(json.dumps({'path':out.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(raw).hexdigest(),'totals':report['totals']}))
if __name__=='__main__':main()
