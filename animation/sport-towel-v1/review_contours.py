"""Preserve the sport source and record visible defects; technical QA is not art approval."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import validate_regions
HERE=Path(__file__).resolve().parent;OUT=ROOT/'animation/production-20261012-wardrobe/sport-towel-v1-qc.json'
SHA='ddb99d07d571841537f107fd1aa35c35515ef73c1d3c7c3323de214fc7fab2ae'
def make_report():
    p=HERE/'atlas-generated.png';rp=HERE/'regions-v1.json';r=json.loads(rp.read_bytes())
    if hashlib.sha256(p.read_bytes()).hexdigest()!=SHA or r['source']['sha256']!=SHA:raise ValueError('source changed')
    a=np.array(Image.open(p).convert('RGBA'));alpha=a[:,:,3];edge=np.zeros(alpha.shape,bool);edge[[0,-1],:]=True;edge[:,[0,-1]]=True
    return {'schemaVersion':1,'reviewedAt':'2026-10-12','artApproval':False,'source':r['source'],'sourceUnchanged':True,
            'regions':{'path':rp.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(rp.read_bytes()).hexdigest()},'canvas':r['canvas'],
            'coverage':validate_regions(r,alpha),'sourceFrames':8,'frameIndices':list(range(8)),
            'frames':[{'sourceFrame':i+1,'sourceBounds':f['sourceBounds'],'coreBounds':f['diagnostics']['coreBounds'],'anchorSource':f['anchorSource'],'translation':f['translation'],'placement':f['placement'],'alignmentIsAnatomy':False}for i,f in enumerate(r['frames'])],
            'sourceAlpha':{'transparentPixels':int((alpha==0).sum()),'alphaOnePixels':int((alpha==1).sum()),'edgeNonzeroPixels':int(((alpha>0)&edge).sum()),'maximumEdgeAlpha':int(alpha[edge].max()),'edgeStrongPixels':int(((alpha>=128)&edge).sum()),'detachedComponents':r['diagnostics']['detachedComponentCount']},
            'bodyMeasurementReport':'animation/production-20261012-wardrobe/sport-towel-v1-body-qc.json',
            'alignmentReview':{'method':'unchanged-default-lower-15-percent-support-center','sameCanvasEveryFrame':True,'perFrameFit':False,'notes':'8格雙裸腳均可見；用原輪廓下端落位，未藉毛巾／全身外框推定人體尺度。'},
            'visualFindings':[{'kind':'new-costume','sourceFrames':list(range(1,9)),'message':'青綠運動背心、橙色髮帶、花紋短褲、白毛巾；8张原畫，一套新衣服。'},
                              {'kind':'revision-required','sourceFrames':[1,5],'message':'第1格半睜與第5格閉眼的眼皮為紫色，違反粉色眼皮方向；精修沒有成功，不可表示已修復。'},
                              {'kind':'revision-required','sourceFrames':[3,4],'message':'兩格幾乎同姿，沒有補足手拿毛巾抬到臉的中間姿勢。'},
                              {'kind':'revision-required','sourceFrames':[6,7],'message':'毛巾從臉旁降到胸口跳躍大，尚缺收手過渡。'},
                              {'kind':'revision-required','sourceFrames':[1,8],'message':'首格疲累吐舌、末格微笑；不構成無縫循環，不能把頭身變化說成只換衣。'}],
            'normalSpeedReview':'see-separate-runtime-review','status':'quality-revision-required'}
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();r=make_report();raw=(json.dumps(r,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if OUT.read_bytes()!=raw:raise ValueError('source QC stale')
    else:OUT.write_bytes(raw)
    print(json.dumps({'path':OUT.relative_to(ROOT).as_posix(),'coverage':r['coverage'],'alpha':r['sourceAlpha']}))
if __name__=='__main__':main()
