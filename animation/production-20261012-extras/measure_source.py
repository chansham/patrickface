"""Measure reviewed windows for extras sources without borrowing source coordinates."""
from pathlib import Path
import argparse,importlib.util
ROOT=Path(__file__).resolve().parents[2];HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location('extras_source_measurement',ROOT/'animation/production-20261012-fitness/measure_source.py')
core=importlib.util.module_from_spec(spec);spec.loader.exec_module(core)
core.HERE=HERE
core.EVIDENCE_DIR=ROOT/'output/body-landmarks-20261012-extras'
if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('config');parser.add_argument('--check',action='store_true');args=parser.parse_args()
    path=(ROOT/args.config).resolve()
    if not path.is_relative_to((HERE/'measurements').resolve()):raise ValueError('extras source config must belong to this batch')
    core.run(path,args.check)
