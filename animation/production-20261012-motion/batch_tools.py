"""Reuse contour QA with an isolated motion baseline and explicit collections."""
from pathlib import Path
import importlib.util,sys
HERE=Path(__file__).resolve().parent
ENGINE=HERE.parent/'production-20261012-fitness'

def load(name):
    key='motion_'+name
    spec=importlib.util.spec_from_file_location(key,ENGINE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);sys.modules[key]=module;spec.loader.exec_module(module)
    return module

batch=load('review_batch')
batch.HERE=HERE;batch.BATCH_ID='20261012-motion';batch.OUTPUT_SLUG='motion-20261012';batch.RENDERING_REVISION='motion-20261012-v1'
base_candidate=batch.candidate

def candidate(spec,qc,catalog):
    tags=spec.get('collectionTags')
    if not isinstance(tags,list) or not tags or any(tag not in ('fitness','playful')for tag in tags) or len(set(tags))!=len(tags):
        raise ValueError('motion source requires explicit unique collectionTags')
    item=base_candidate(spec,qc,catalog)
    item['collectionTags']=list(tags)
    if spec.get('variantKind')=='timing-only':
        original=next((clip for clip in catalog['clips']if clip['id']==spec.get('sourceCandidateID')),None)
        if not original or spec['newOutfit'] or item['comparisonClipId']!=original['id']:
            raise ValueError('timing comparison must identify its unchanged original candidate')
        for key in ['atlas','sha256','frameRegions','width','height','columns','rows','frameCount','frameIndices','scale','anchorNormalized','masterId']:
            if item[key]!=original[key]:raise ValueError('timing-only variant changed artwork geometry: '+key)
        if item['durationsMs']==original['durationsMs']:raise ValueError('timing variant needs a real timing difference')
        item.update(variantKind='timing-only',sourceCandidateID=original['id'],newOriginalFrames=0)
    return item

batch.candidate=candidate
sys.modules['review_batch']=batch
