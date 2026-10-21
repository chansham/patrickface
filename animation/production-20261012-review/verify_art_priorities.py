"""Check review-list provenance and frame addresses without diagnosing unseen anatomy.

No changes to PNGs, candidates, user notes, or the author's review list.
The output is a technical data check, never an art approval.
"""
from pathlib import Path,PurePosixPath
import argparse,copy,hashlib,json,math,re,sys
from PIL import Image
ROOT=Path(__file__).resolve().parents[2]
SOURCE='animation/production-20261012-review/art-priorities.json'
OUTPUT='output/art-priorities-20261012/verification.json'
METRICS=('faceWidthPx','eyeLowerRimSeparationPx','eyeLineToFootPx')
ISSUE_TYPES={'size','crop','eyes','motion','outfit'}
def sha(raw):return hashlib.sha256(raw).hexdigest()
def safe_file(value):
    if not isinstance(value,str) or not value or '\\' in value or ':' in value:raise ValueError('expected relative project file path')
    posix=PurePosixPath(value)
    if posix.is_absolute() or '..' in posix.parts:raise ValueError('path escapes project')
    path=ROOT/posix
    if path.is_symlink() or not path.resolve().is_relative_to(ROOT.resolve()) or not path.is_file():raise ValueError(f'file missing or outside project: {value}')
    return path
def read_json(value):
    raw=safe_file(value).read_bytes();return json.loads(raw),sha(raw)
def require(condition,message):
    if not condition:raise ValueError(message)
def digest_shape(value):return isinstance(value,str) and re.fullmatch(r'[0-9a-f]{64}',value) is not None
def finite_positive(value):return type(value) in (int,float) and math.isfinite(value) and value>0
def validate(data):
    errors=[];clips=[];items=[];refs=[]
    def attempt(label,fn):
        try:return fn()
        except (ValueError,KeyError,TypeError,IndexError,OSError) as error:errors.append({'record':label,'message':str(error)});return None
    require(data.get('schemaVersion')==1,'unsupported review schema')
    require(data.get('artApproval') is False,'review list cannot approve art')
    require(data.get('status') in {'draft-source-visual-review','source-visual-review-complete-art-pending'},'unsupported source-review status')
    require('one-based' in data.get('sourceFrameNumbering',''),'source frame numbering must be explicitly one-based')
    require(isinstance(data.get('clips'),list) and data['clips'],'reviewed clips missing')
    require(isinstance(data.get('items'),list),'review items missing')
    catalog,catalog_sha=read_json('animation/candidates.json')
    catalog_by_id={c['id']:c for c in catalog['clips']}
    require(len(catalog_by_id)==len(catalog['clips']),'duplicate candidate IDs')
    qc_paths={}
    for batch in ('fitness','playful'):
        path=f'animation/production-20261012-{batch}/manifest.json';manifest,digest=read_json(path);refs.append({'path':path,'sha256':digest})
        for source in manifest['sources']:
            require(source['id'] not in qc_paths,'duplicate batch source')
            qc_paths[source['id']]=source['bodyQC']
    reviewed={};body={}
    for row in data['clips']:
        key=row.get('clipID','<missing>')
        def check_clip():
            require(isinstance(key,str) and key not in reviewed,'missing or duplicate reviewed clip ID')
            clip=catalog_by_id.get(key);require(clip is not None,'clip absent from candidates')
            require(row.get('artApproval') is False,'clip review must not approve art')
            require(row.get('visuallyReviewed') is True,'clip lacks author visual-review record')
            require(row.get('sourcePath')==clip['atlas'],'source path differs from candidate')
            require(digest_shape(row.get('sourceSha256')),'invalid source SHA')
            source_raw=safe_file(row['sourcePath']).read_bytes()
            require(sha(source_raw)==row['sourceSha256']==clip['sha256'],'PNG SHA drift')
            with Image.open(safe_file(row['sourcePath'])) as im:dimensions=list(im.size)
            require(dimensions==[clip['width'],clip['height']],'PNG geometry differs from candidate')
            require(row.get('columns')==clip['columns'] and row.get('rows')==clip['rows'],'source grid differs from candidate')
            regions,regions_sha=read_json(clip['frameRegions']['path'])
            require(regions_sha==clip['frameRegions']['sha256'],'regions SHA drift')
            source={'path':clip['atlas'],'sha256':clip['sha256'],'width':clip['width'],'height':clip['height']}
            require(regions['source']==source,'regions belong to a different PNG')
            count=len(regions['frames'])
            require(type(row.get('sourceFrameCount')) is int and row['sourceFrameCount']==count==row['columns']*row['rows'],'source count/grid mismatch')
            order=clip.get('frameIndices',list(range(clip['frameCount'])))
            require(len(order)==clip['frameCount'] and all(type(n) is int and 0<=n<count for n in order),'invalid playback mapping')
            qc_path=qc_paths[key];qc,qc_sha=read_json(qc_path)
            require(qc['artApproval'] is False,'body QC unexpectedly approved art')
            require(qc['source']==source,'body QC source identity mismatch')
            require(qc['regions']=={'path':clip['frameRegions']['path'],'sha256':regions_sha},'body QC region identity mismatch')
            require([f['sourceFrame'] for f in qc['frames']]==list(range(1,count+1)),'body QC does not cover every source frame exactly once')
            config,config_sha=read_json(qc['reviewConfiguration']['path'])
            require(config_sha==qc['reviewConfiguration']['sha256'],'body QC review configuration changed')
            require(config['clipID']==key and config['source']==source and config['regions']==qc['regions'],'body config identity mismatch')
            for frame in qc['frames']:
                require(all(frame[m] is None or finite_positive(frame[m]) for m in METRICS),'invalid body value; unknown must stay null')
            reviewed[key]=(row,clip,order);body[key]=qc
            return {'clipID':key,'sourcePath':source['path'],'sourceSha256':source['sha256'],'sourceFrameCount':count,
                    'regionsPath':clip['frameRegions']['path'],'regionsSha256':regions_sha,'bodyQC':{'path':qc_path,'sha256':qc_sha},
                    'bodyAvailableCounts':{m:sum(f[m] is not None for f in qc['frames']) for m in METRICS},'artApproval':False}
        checked=attempt(key,check_clip)
        if checked:clips.append(checked)
    require(len(data['clips'])==data['scope']['clipCount'],'scope clipCount mismatch')
    require(sum(c.get('sourceFrameCount',0) for c in data['clips'])==data['scope']['originalFrameCount'],'scope frame total mismatch')
    seen=set()
    for item in data['items']:
        key=item.get('id','<missing>')
        def check_item():
            require(isinstance(key,str) and key and key not in seen,'missing or duplicate item ID');seen.add(key)
            clip_id=item.get('clipID');require(clip_id in reviewed,'item has no verified reviewed source')
            row,clip,order=reviewed[clip_id];qc=body[clip_id]
            require(item.get('sourceSha256')==clip['sha256'],'item SHA differs from current source')
            require(item.get('issueType') in ISSUE_TYPES,'unsupported issueType')
            require(item.get('severity') in {'high','medium','low'},'unsupported severity')
            require(type(item.get('subjective')) is bool,'subjective must be explicit')
            require(item.get('status') in {'pending-source-art-repair','needs-visual-review','subjective-preference'},'unsupported issue status')
            require(all(isinstance(item.get(k),str) and item[k].strip() for k in ('title','detail')),'item lacks concrete explanation')
            frames=item.get('sourceFrames');require(isinstance(frames,list) and frames,'source frame list missing')
            require(all(type(n) is int and 1<=n<=len(qc['frames']) for n in frames),'source frames must be one-based integers inside source')
            require(len(set(frames))==len(frames),'duplicate source frame')
            require(item.get('evidencePath')==clip['atlas'],'primary evidence must be this source atlas')
            evidence=[{'path':item['evidencePath'],'sha256':sha(safe_file(item['evidencePath']).read_bytes())}]
            extra=item.get('evidencePaths',[]);require(isinstance(extra,list),'evidencePaths must be an array')
            for path in extra:
                require(not isinstance(path,str) or not path.endswith('.json') or path==qc_paths[clip_id],'JSON evidence belongs to a different body QC')
                evidence.append({'path':path,'sha256':sha(safe_file(path).read_bytes())})
            # Quantitative size claims need a separately designed, verified comparison.
            # The present list contains visual eyes/motion findings, not inferred anatomy.
            require(not any(k in item for k in ('measurements','measurementValues','proportionDeltaPercent')),'unvalidated numeric diagnosis field; do not infer measurements from unknown anatomy')
            if item['issueType']=='size' and not item['subjective']:
                raise ValueError('objective size diagnosis requires explicit independently verified comparison schema')
            availability=[]
            for n in frames:
                frame=qc['frames'][n-1]
                availability.append({'sourceFrame':n,'playbackFrames':[i+1 for i,v in enumerate(order) if v==n-1],
                  'bodyMetrics':{m:frame[m] for m in METRICS},
                  'unknownReasons':{k:frame[k] for k in ('eyeUnavailableReason','faceWidthUnavailableReason','footUnavailableReason') if frame.get(k)},
                  'unknownIsNotADiagnosedScaleDefect':True})
            require(all(f['playbackFrames'] for f in availability),'listed source frame is not reachable in current playback')
            return {'id':key,'clipID':clip_id,'sourceSha256':clip['sha256'],'issueType':item['issueType'],'sourceFrames':frames,
              'mappedFramesAndBodyAvailability':availability,'evidence':evidence,'technicalIdentityVerified':True,
              'artApproval':False,'visualClaimAutomaticallyApproved':False}
        checked=attempt(key,check_item)
        if checked:items.append(checked)
    for row in data.get('reviewedWithoutDefiniteNewIssue',[]):
        attempt('reviewed-without-issue:'+str(row.get('clipID')),lambda row=row:require(row.get('clipID') in reviewed and row.get('sourceSha256')==catalog_by_id[row['clipID']]['sha256'],'reviewed-without-issue identity mismatch'))
    actual_summary={'reviewedClips':len(data['clips']),'reviewedSourceFrames':sum(c['sourceFrameCount'] for c in data['clips']),
      'items':len(data['items']),'clipsWithItems':len({i.get('clipID') for i in data['items']}),
      'high':sum(i.get('severity')=='high' for i in data['items']),'medium':sum(i.get('severity')=='medium' for i in data['items']),
      'eyes':sum(i.get('issueType')=='eyes' for i in data['items']),'motion':sum(i.get('issueType')=='motion' for i in data['items']),
      'scaleDiagnoses':sum(i.get('issueType')=='size' and not i.get('subjective') for i in data['items']),
      'cropDiagnoses':sum(i.get('issueType')=='crop' and not i.get('subjective') for i in data['items']),'artApproved':0}
    if 'summary' in data:attempt('summary',lambda:require(data['summary']==actual_summary,'declared summary differs from actual source/items'))
    return {'schemaVersion':1,'checkedAt':'2026-10-12','artApproval':False,'passed':not errors,'errors':errors,
      'authorReviewStatus':data['status'],'verifiedSummary':actual_summary,
      'catalog':{'path':'animation/candidates.json','sha256':catalog_sha},'batchManifests':refs,
      'reviewedSourceCount':len(clips),'reviewedSourceFrames':sum(c['sourceFrameCount'] for c in clips),
      'issueCount':len(items),'clipsWithIssues':len({i['clipID'] for i in items}),
      'clips':clips,'items':items,
      'limits':['Validates identity, source frame numbering, declared types, paths and independent body-QC links only.',
        'Unknown anatomical measurements do not diagnose scale or crop faults; visible eye-color or pose-continuity findings may still be reviewed.',
        'This check neither proves a visual claim nor approves the artwork or animation. No user notes or source files are modified.']}
def fixtures(data):
    require(validate(data)['passed'],'baseline review data must pass before mutation checks')
    mutations=[('wrong-source-sha',lambda d:d['items'][0].update(sourceSha256='0'*64)),
      ('wrong-clip',lambda d:d['items'][0].update(clipID='missing-clip')),
      ('zero-based-frame',lambda d:d['items'][0].update(sourceFrames=[0])),
      ('boolean-frame',lambda d:d['items'][0].update(sourceFrames=[True])),
      ('frame-outside-source',lambda d:d['items'][0].update(sourceFrames=[999])),
      ('unsupported-type',lambda d:d['items'][0].update(issueType='automatic-art-approved')),
      ('wrong-evidence-source',lambda d:d['items'][0].update(evidencePath=d['clips'][0]['sourcePath'])),
      ('escaping-evidence-path',lambda d:d['items'][0].update(evidencePaths=['../outside.png'])),
      ('numeric-diagnosis-without-evidence',lambda d:d['items'][0].update(proportionDeltaPercent=0))]
    for label,mutate in mutations:
        value=copy.deepcopy(data);mutate(value);require(not validate(value)['passed'],f'mutation was not rejected: {label}')
    return {'passed':len(mutations),'total':len(mutations),'fixtureLabels':[x[0] for x in mutations],'writes':0}
def main():
    p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');p.add_argument('--test',action='store_true');args=p.parse_args()
    data,source_sha=read_json(SOURCE)
    if args.test:print(json.dumps(fixtures(data)));return
    report=validate(data);report['source']={'path':SOURCE,'sha256':source_sha}
    payload=json.dumps(report,ensure_ascii=False,indent=2)+'\n';target=ROOT/OUTPUT
    if args.check:
        require(target.is_file() and target.read_text(encoding='utf-8')==payload,'art-priority verification snapshot stale')
    else:target.parent.mkdir(parents=True,exist_ok=True);target.write_text(payload,encoding='utf-8')
    print(json.dumps({k:report[k] for k in ('passed','errors','reviewedSourceCount','reviewedSourceFrames','issueCount','clipsWithIssues')},ensure_ascii=False))
    if not report['passed']:sys.exit(1)
if __name__=='__main__':main()
