"""Reuse the tested batch QA engine with isolated outputs and baseline."""
from pathlib import Path
import importlib.util,sys
HERE=Path(__file__).resolve().parent
ENGINE=HERE.parent/'production-20261012-fitness'
def load(name):
    key='playful_'+name
    spec=importlib.util.spec_from_file_location(key,ENGINE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);sys.modules[key]=module;spec.loader.exec_module(module)
    return module
batch=load('review_batch')
batch.HERE=HERE;batch.BATCH_ID='20261012-playful';batch.OUTPUT_SLUG='playful-20261012';batch.RENDERING_REVISION='playful-20261012-v1'
sys.modules['review_batch']=batch
