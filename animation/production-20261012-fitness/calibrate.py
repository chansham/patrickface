"""One fixed scale per source: target real primary landmarks, constrained by all poses/layouts."""
from pathlib import Path
import argparse,hashlib,json,math,shutil
import review_batch as batch
ROOT=batch.ROOT;HERE=batch.HERE

def derive(spec):
    qc=batch.inspect(spec,False);body=batch.read(ROOT/spec['bodyQC']);first=body['frames'][0]
    primary=batch.read(ROOT/'animation/production-20261006-scale/body-scale-audit.json')
    ref=next(c for c in primary['clips']if c['id']=='yawn');main=next(c for c in batch.read(ROOT/'animation/catalog.json')['clips']if c['id']=='yawn')
    if ref['sourceSha256']!=main['sha256'] or ref['regionsSha256']!=main['frameRegions']['sha256'] or ref['catalogScale']!=main['scale']:raise ValueError('primary landmark reference drift')
    metric='faceWidth' if first.get('faceWidthPx') is not None else 'eyeSeparation'
    key='faceWidthPx' if metric=='faceWidth' else 'eyeLowerRimSeparationPx'
    source=first.get(key)
    if not source:raise ValueError('first frame needs a visible face or eye proxy, otherwise manually choose a new reliable reference frame')
    target=ref['measurements']['reference']['stage'][metric];desired=target/source
    layouts=batch.read(ROOT/'experience/layouts.json')['layouts']
    # Measured browser text bounds, using the same current layout/font settings.
    tested=batch.read(ROOT/'output/playwright/fitness-20261012/fitness-boxing-first-20261012/browser/report.json')['cases'][0]['geometry']
    zones={l['id']:l['zones']for l in tested}
    text_margin=spec.get('textClearanceLogicalPixels',8)
    if not isinstance(text_margin,(int,float)) or isinstance(text_margin,bool) or not 4<=text_margin<=8:raise ValueError('reviewed text clearance must be 4..8 logical pixels')
    def safe(factor):
        for frame in qc['frames']:
            x0,y0,x1,y1=frame['coreBounds'];ax,ay=frame['anchorSource']
            x0=416+(x0-ax)*factor;x1=416+(x1-ax)*factor;y0=893.632+(y0-ay)*factor;y1=893.632+(y1-ay)*factor
            if x0<8 or x1>824 or y0<246.08 or y1>914.56:return False
            for layout in layouts:
                scale,tx,ty=layout['characterTransform'];left=x0*scale+tx;right=x1*scale+tx;top=y0*scale+ty;bottom=y1*scale+ty
                if min(left,top)<8 or right>824 or bottom>984:return False
                for zone in zones[layout['id']]:
                    zx,zy,zw,zh=zone['bounds'];margin=text_margin
                    if right>zx-margin and left<zx+zw+margin and bottom>zy-margin and top<zy+zh+margin:return False
        return True
    low,high=0.,desired
    for _ in range(60):
        mid=(low+high)/2
        if safe(mid):low=mid
        else:high=mid
    factor=math.floor(low*1e10)/1e10
    return {'metric':metric,'sourcePixels':source,'targetStagePixels':target,'desiredFactor':desired,'fixedFactor':factor,
            'actualStagePixels':source*factor,'shortfallPercent':max(0,(1-source*factor/target)*100),'sourceSha256':spec['sha256'],
            'canvas':qc['canvas']['width'],'catalogScale':factor*qc['canvas']['width']/665.6,'reference':'yawn:first actual source frame',
            'method':'single-factor-primary-landmark-target-with-all-source-poses-and-four-layout-safety',
            'safety':f'{text_margin:g} logical pixel clearance around measured browser text/info bounds; classic stage y>=246.08, y<=914.56; all layouts remain in stage',
            'perFrameScale':False,'faceWidthKnown':first.get('faceWidthPx') is not None}

def main():
    p=argparse.ArgumentParser();p.add_argument('--id',required=True);p.add_argument('--apply',action='store_true');args=p.parse_args()
    manifest=batch.read(HERE/'manifest.json');spec=next(s for s in manifest['sources']if s['id']==args.id);result=derive(spec)
    if args.apply:
        catalog=batch.read(ROOT/'animation/candidates.json');existing=next((c for c in catalog['clips']if c['id']==args.id),None)
        if existing and not math.isclose(existing['scale'],result['catalogScale'],abs_tol=1e-10):
            snap=HERE/f'{args.id}-calibration-before-v{existing["version"]}.json'
            if snap.exists():
                if batch.read(snap)['candidate']!=existing:raise ValueError('calibration snapshot already belongs to another state')
            else:batch.write_json(snap,{'schemaVersion':1,'reason':'本批依主睡衣的可見臉部尺規重校；保留舊版本與評價識別，不逐格縮放。','candidate':existing})
            spec['version']=existing['version']+1;spec['calibrationBefore']=snap.relative_to(ROOT).as_posix()
            for leaf in ['browser','contours']:
                src=ROOT/'output/playwright'/batch.OUTPUT_SLUG/args.id/leaf;dest=src.with_name(leaf+f'-v{existing["version"]}-calibration')
                if src.exists() and not dest.exists():shutil.copytree(src,dest)
        spec['fixedSourcePixelToStagePixel']=result['fixedFactor'];spec['scaleReason']=result['method'];spec['calibration']=result
        batch.write_json(HERE/'manifest.json',manifest)
    print(json.dumps(result,ensure_ascii=False))
if __name__=='__main__':main()
