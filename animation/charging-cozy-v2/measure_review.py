"""Review new charging costume without changing its PNG or guessing hidden feet."""
from pathlib import Path
import argparse,hashlib,json,math,sys
import numpy as np
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
from build_frame_regions import validate_regions
from audit_body_scale import measure_face,rim_point
SOURCE='animation/charging-cozy-v2/atlas-generated.png'
SHA='993feacbb4e57dc9acd393be690e3f96321bf543921c2ccb5b971cd617fae194'
OUTPUT=ROOT/'animation/production-20261007-completion/charging-cozy-v2-qc.json'
# Only independently inspected neutral first/last frames. Closed/tilted action
# frames are deliberately not treated as anatomical-size measurements.
EYES={1:[[149,138,182,161],[184,145,217,168]],12:[[879,1196,912,1219],[914,1202,947,1225]]}
def make_report():
    p=ROOT/SOURCE;raw=p.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=SHA:raise ValueError('semantic selections source SHA mismatch')
    rp=p.with_name('regions-v1.json');rb=rp.read_bytes();meta=json.loads(rb)
    rgba=np.array(Image.open(p).convert('RGBA'));alpha=rgba[:,:,3]
    if meta['source']!={'path':SOURCE,'sha256':SHA,'width':rgba.shape[1],'height':rgba.shape[0]}:raise ValueError('region identity drift')
    coverage=validate_regions(meta,alpha);frames=[]
    for i,f in enumerate(meta['frames'],1):
        l,t,r,b=f['diagnostics']['coreBounds']
        row={'sourceFrame':i,'coreBounds':[l,t,r,b],'coreWidthPx':r-l,'coreHeightPx':b-t,
             'sourceBounds':f['sourceBounds'],'anchorSource':f['anchorSource'],'translation':f['translation'],
             'faceWidthPx':None,'eyeLowerRimSeparationPx':None,'eyeLineToFootPx':None,
             'footUnavailableReason':'Slippers cover the anatomical feet; lower support silhouette is not a true-foot body measurement.'}
        if i in EYES:
            points=[rim_point(p).tolist() for p in EYES[i]]
            row.update(eyeWhiteBounds=EYES[i],eyeLowerRimPoints=points,eyeLowerRimSeparationPx=math.dist(*points))
            face=measure_face(rgba,EYES[i],None)
            if 'faceWidth' in face:row.update(faceWidthPx=face['faceWidth'],faceCaliperPoints=face['faceCaliperPoints'])
            else:row['faceWidthUnavailableReason']=face.get('unavailable')
        else:row['eyeUnavailableReason']='Action-frame eye tracking not independently validated; pose/tilt/closed-eye changes excluded conservatively.'
        frames.append(row)
    def delta(key):
        a,b=frames[0][key],frames[-1][key]
        return {'first':a,'last':b,'changePercent':None if a is None or b is None else (b/a-1)*100}
    edge=np.zeros(alpha.shape,dtype=bool);edge[[0,-1],:]=True;edge[:,[0,-1]]=True
    return {'schemaVersion':1,'reviewedAt':'2026-10-08','frameIndexBasis':'one-based source reading order',
            'status':'tilt-transition-revision-selected-pending-review','artApproved':False,'source':meta['source'],'sourceUnchanged':True,
            'regions':{'path':rp.relative_to(ROOT).as_posix(),'sha256':hashlib.sha256(rb).hexdigest()},'canvas':meta['canvas'],
            'coverage':coverage,'frames':frames,'reference':{'sourceSha256':SHA,'manualEyeBoundsBySourceFrame':EYES},
            'summary':{'sourceFrames':12,'measuredFaceFrames':sum(f['faceWidthPx'] is not None for f in frames),
                       'measuredEyeFrames':2,'measuredEyeActualFootFrames':0,
                       'sourceEdgeAlphaPixels':int(((alpha>0)&edge).sum()),'sourceEdgeStrongPixels':int(((alpha>=128)&edge).sum()),
                       'minimumStrongCoreSourceMarginsLTRB':[min(f['coreBounds'][0] for f in frames),min(f['coreBounds'][1] for f in frames),min(rgba.shape[1]-f['coreBounds'][2] for f in frames),min(rgba.shape[0]-f['coreBounds'][3] for f in frames)]},
            'newFirstLastFrame':{key:delta(key) for key in ['faceWidthPx','eyeLowerRimSeparationPx','coreWidthPx','coreHeightPx']},
            'methods':['All source alpha pixels uniquely assigned. Same source pixels and one fixed canvas/scale, no per-frame fit.',
                       'Face caliper and eye-rim distance use only separately inspected first/last original-source white-eye bounds.',
                       'Hat/battery/slippers are excluded from semantic face proxies; whole core dimensions are only silhouette diagnostics.',
                       'No true foot baseline is visible through slippers; every eye-to-foot field remains null.',
                       'Approximately2 source pixels of edge-sampling uncertainty; successful extraction is not art approval.'],
            'visualFindings':[{'sourceFrames':[3,4,5,6],'kind':'new-action','message':'Both arms lift and squeeze the battery cushion; actual limb/prop changes, not whole-card motion.'},
                              {'sourceFrames':[7,8,9],'kind':'improved-but-pending','message':'Frame7 now leans between upright and frame8, and frame9 partly returns; transition improved in static comparison, real1x review still required.'},
                              {'sourceFrames':[1,12],'kind':'remaining','message':'Ending hat/head and silhouette height differ slightly from beginning; not an exact neutral loop.'},
                              {'sourceFrames':list(range(1,13)),'kind':'preserve','message':'Cream star-pattern pajamas, lilac slippers, white sclera and pink closed lids. All12 source frames retained.'}],
            'normalSpeedReview':'pending-new-source-browser-review'}
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--check',action='store_true');args=p.parse_args()
    report=make_report();raw=(json.dumps(report,ensure_ascii=False,indent=2)+'\n').encode('utf-8')
    if args.check:
        if OUTPUT.read_bytes()!=raw:raise ValueError('QC snapshot differs')
    else:OUTPUT.write_bytes(raw)
    print(json.dumps({'output':OUTPUT.relative_to(ROOT).as_posix(),'summary':report['summary'],'firstLast':report['newFirstLastFrame']},ensure_ascii=False))
if __name__=='__main__':main()
