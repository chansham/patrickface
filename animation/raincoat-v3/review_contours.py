"""Source-pinned contour and pose review. Body measurement is a separate report."""
from pathlib import Path
import argparse,hashlib,json,sys
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import validate_regions
HERE=Path(__file__).resolve().parent;OUT=ROOT/'animation/production-20261012-wardrobe/raincoat-v3-qc.json'
SOURCE_SHA='e3fdb977617c6a73718a6bb12b31d27be1e1a737a5ccba4304c39417d2ff2e74'
ORDER=[0,1,3,4,2,5,6,7,8,9,10,11]
def make_report():
    image=HERE/'atlas-generated.png';rp=HERE/'regions-v1.json';raw=image.read_bytes();rb=rp.read_bytes();regions=json.loads(rb)
    if hashlib.sha256(raw).hexdigest()!=SOURCE_SHA or regions['source']['sha256']!=SOURCE_SHA:raise ValueError('source identity drift')
    rgba=np.array(Image.open(image).convert('RGBA'));alpha=rgba[:,:,3];coverage=validate_regions(regions,alpha)
    edge=np.zeros(alpha.shape,bool);edge[[0,-1],:]=True;edge[:,[0,-1]]=True
    frames=[]
    for i,f in enumerate(regions['frames']):
        l,t,r,b=f['diagnostics']['coreBounds'];anchor=f['anchorSource']
        frames.append({'sourceFrame':i+1,'playbackFrame':ORDER.index(i)+1,'sourceBounds':f['sourceBounds'],'coreBounds':[l,t,r,b],
                       'coreHeightPx':b-t,'coreWidthPx':r-l,'anchorSource':anchor,'translation':f['translation'],
                       'placement':f['placement'],'coreBottomOffsetFromAnchor':b-anchor[1],
                       'alignmentIsAnatomy':False})
    return {'schemaVersion':1,'reviewedAt':'2026-10-12','frameIndexBasis':'one-based source reading order','artApproval':False,
            'source':regions['source'],'sourceUnchanged':True,'regions':{'path':rp.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(rb).hexdigest()},
            'canvas':regions['canvas'],'coverage':coverage,'sourceFrames':12,'frameIndices':ORDER,'frames':frames,
            'sourceAlpha':{'transparentPixels':int((alpha==0).sum()),'alphaOnePixels':int((alpha==1).sum()),'edgeNonzeroPixels':int(((alpha>0)&edge).sum()),'edgeStrongPixels':int(((alpha>=128)&edge).sum()),'detachedComponents':regions['diagnostics']['detachedComponentCount']},
            'bodyMeasurementReport':'animation/production-20261012-wardrobe/raincoat-v3-body-qc.json',
            'alignmentReview':{'method':'unchanged-default-lower-15-percent-support-center','sameCanvasEveryFrame':True,'perFrameFit':False,
                               'notes':'12格均雙腳可見、沒有跳躍；下端core正好落在共用基線。anchor僅為輪廓落位，真足底與臉眼尺規由另一份逐格報告核對。'},
            'visualFindings':[{'kind':'improved','sourceFrames':[4,5,8,9,10],'message':'相較8格站姿，多出腰前、胸口及收手中間姿勢；原3→4會突然降手，候選改按0,1,3,4,2,5,6,7,8,9,10,11播放。'},
                              {'kind':'remaining','sourceFrames':[2,4,6],'message':'抬眼→看前方→再抬眼的視線切換仍跳，手臂高度連續不代表眼部表演連續。'},
                              {'kind':'remaining','sourceFrames':[6,7,8],'message':'嘴部由微笑突然張大再合回，仍缺表情過渡。'},
                              {'kind':'remaining','sourceFrames':[1,12],'message':'頭、雨衣、雨傘弧線細節有原畫變化；首末不是同一原畫，不能稱無縫循環。'},
                              {'kind':'preserved','sourceFrames':list(range(1,13)),'message':'站姿、黃色雨衣、藍傘、白眼白及粉色眼皮保留；原RGBA及所有微弱alpha零件未修改。'}],
            'normalSpeedReview':'see-separate-runtime-review','reorderingIsNotRedrawing':True,'approvedDirection':False}
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args();report=make_report();payload=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if OUT.read_bytes()!=payload:raise ValueError('contour QC snapshot differs')
    else:OUT.parent.mkdir(parents=True,exist_ok=True);OUT.write_bytes(payload)
    print(json.dumps({'path':OUT.relative_to(ROOT).as_posix(),'coverage':report['coverage'],'alpha':report['sourceAlpha'],'frameIndices':ORDER}))
if __name__=='__main__':main()
