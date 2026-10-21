"""Reuse contour QA with an isolated inbetweens baseline and explicit collections."""
from pathlib import Path
import importlib.util,sys
HERE=Path(__file__).resolve().parent
ENGINE=HERE.parent/'production-20261012-fitness'

def load(name):
    key='inbetweens_'+name
    spec=importlib.util.spec_from_file_location(key,ENGINE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);sys.modules[key]=module;spec.loader.exec_module(module)
    return module

batch=load('review_batch')
batch.HERE=HERE;batch.BATCH_ID='20261012-inbetweens';batch.OUTPUT_SLUG='inbetweens-20261012';batch.RENDERING_REVISION='inbetweens-20261012-v1'
base_candidate=batch.candidate

def candidate(spec,qc,catalog):
    tags=spec.get('collectionTags')
    if not isinstance(tags,list) or not tags or any(tag not in ('fitness','playful')for tag in tags) or len(set(tags))!=len(tags):
        raise ValueError('inbetweens source requires explicit unique collectionTags')
    item=base_candidate(spec,qc,catalog)
    item['collectionTags']=list(tags)
    return item

batch.candidate=candidate
sys.modules['review_batch']=batch
