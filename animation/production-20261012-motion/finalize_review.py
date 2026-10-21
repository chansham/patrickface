from batch_tools import batch,load,HERE
engine=load('finalize_review');engine.HERE=HERE;engine.OUTPUT_SLUG='motion-20261012'
# Count only selected successful sources. The engine still rejects an empty or unfinished batch.
engine.EXPECTED_CLIP_COUNT=len(batch.read(HERE/'manifest.json')['sources'])
base_report=engine.report
def report():
    data=base_report();manifest=batch.read(HERE/'manifest.json')
    if not all(s.get('variantKind')=='timing-only'for s in manifest['sources']):raise ValueError('motion report expects explicit timing-only variants')
    data.update(newOriginalFrames=0,reusedSourceFrames=data['sourceFrames'],playbackVariants=len(data['clips']),newOutfits=0)
    catalog=batch.read(batch.ROOT/'animation/candidates.json')['clips']
    data['catalogCounts']={'candidateClips':len(catalog),'playbackFrames':sum(c['frameCount']for c in catalog),
        'uniqueSourceDrawings':len({(c['sha256'],i)for c in catalog for i in c.get('frameIndices',range(c['frameCount']))}),
        'uniqueSourceAtlases':len({c['sha256']for c in catalog})}
    data['timingComparisons']=[]
    for spec in manifest['sources']:
        original=next(c for c in catalog if c['id']==spec['sourceCandidateID'])
        current=next(c for c in catalog if c['id']==spec['id'])
        same=['atlas','sha256','frameRegions','width','height','columns','rows','frameCount','frameIndices','scale','anchorNormalized','masterId']
        assert all(current[key]==original[key]for key in same)
        data['timingComparisons'].append({'id':current['id'],'originalID':original['id'],'unchangedFields':same,
            'originalDurationsMs':original['durationsMs'],'comparisonDurationsMs':current['durationsMs'],
            'originalTotalMs':sum(original['durationsMs']),'comparisonTotalMs':sum(current['durationsMs']),
            'missingDrawingsRepaired':False,'newOriginalFrames':0})
    return data
engine.report=report
if __name__=='__main__':engine.main()
