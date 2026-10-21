"""Map timing-only clip IDs to exact existing evidence, without new measurements.

All source, contour, registration, scale and frame-order properties must equal
the original clip. Existing unknowns and art issues are preserved. No fallback
across changed PNG/regions identities; no prior report or source is rewritten.
"""
from pathlib import Path
import argparse
import copy
import hashlib
import importlib.util
import json

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
ORIGINAL_AUDIT = 'animation/production-20261012-fitness/body-scale-audit.json'
ORIGINAL_MANIFEST = 'animation/production-20261012-fitness/manifest.json'
spec = importlib.util.spec_from_file_location('motion_projection_adapter', ROOT / 'animation/production-20261007-completion/build_body_scale_audit.py')
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
SAME_FIELDS = ('atlas', 'sha256', 'width', 'height', 'columns', 'rows', 'frameCount',
               'frameRegions', 'scale', 'anchorNormalized', 'masterId')


def read_json(relative):
    path = base.project_file(relative)
    raw = path.read_bytes()
    return json.loads(raw.decode('utf-8-sig')), {'path': relative, 'sha256': hashlib.sha256(raw).hexdigest()}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sequence(clip):
    return clip.get('frameIndices', list(range(clip['frameCount'])))


def identical_source_rendering(original, variant):
    for field in SAME_FIELDS:
        require(field in original and field in variant and original[field] == variant[field],
                f'timing-only reference changed {field}: {variant.get("id")}')
    require(sequence(original) == sequence(variant), 'timing-only reference changed frameIndices')
    require(original['durationsMs'] != variant['durationsMs'], 'timing variant has no timing change')
    require(len(variant['durationsMs']) == variant['frameCount'] and
            all(base.number(t) and 0 < t <= 60000 for t in variant['durationsMs']), 'invalid variant durations')


def make_report():
    catalog, _ = read_json('animation/candidates.json')
    catalog_by_id = {c['id']: c for c in catalog['clips']}
    require(len(catalog_by_id) == len(catalog['clips']), 'duplicate candidate IDs')
    manifest, manifest_ref = read_json((HERE / 'manifest.json').relative_to(ROOT).as_posix())
    original_manifest, original_manifest_ref = read_json(ORIGINAL_MANIFEST)
    original_audit, original_audit_ref = read_json(ORIGINAL_AUDIT)
    original_manifest_by_id = {r['id']: r for r in original_manifest['sources']}
    original_entries = {r['id']: r for r in original_audit['clips']}
    pairs = []
    for entry in manifest['sources']:
        require(entry.get('variantKind') == 'timing-only' and entry.get('newOriginalFrames') == 0 and entry.get('newOutfit') is False,
                'this adapter accepts existing-source timing variants only')
        variant = catalog_by_id[entry['id']]
        original_id = entry['sourceCandidateID']
        require(original_id == entry['comparisonClipId'] and original_id != variant['id'], 'missing exact comparison identity')
        original = catalog_by_id[original_id]
        identical_source_rendering(original, variant)
        source_entry = original_manifest_by_id[original_id]
        require(entry['source'] == original['atlas'] and entry['sha256'] == original['sha256'] and
                entry['bodyQC'] == source_entry['bodyQC'], 'manifest source or evidence changed')
        require(entry['frameIndices'] == sequence(variant) and entry['durationsMs'] == variant['durationsMs'],
                'manifest playback mapping differs from catalog')
        qc, qc_ref = read_json(entry['bodyQC'])
        config, config_ref = read_json(qc['reviewConfiguration']['path'])
        require(qc['reviewConfiguration'] == config_ref, 'measurement configuration SHA changed')
        require(config['clipID'] == original_id and config['source'] == qc['source'] and config['regions'] == qc['regions'],
                'original measurement configuration/source mismatch')
        prior = original_entries[original_id]
        require(prior['measurementProvenance'] == qc_ref and prior['sourceSha256'] == original['sha256'] and
                prior['regionsSha256'] == original['frameRegions']['sha256'] and prior['catalogScale'] == original['scale'] and
                prior['frameIndices'] == sequence(original), 'original audit provenance or rendering is stale')
        pairs.append((entry, original, variant, qc, qc_ref, config_ref, prior))
    require(pairs, 'no exact existing-source variants; do not create empty audit')
    base.DIRECTORY = ROOT
    base.SPECS = tuple((variant['id'], variant['atlas'], variant['sha256'], entry['bodyQC'], 'timing-only')
                      for entry, original, variant, qc, qc_ref, config_ref, prior in pairs)
    report = base.make_report()
    for clip, (entry, original, variant, qc, qc_ref, config_ref, prior) in zip(report['clips'], pairs):
        require(clip['sourcePixelToStagePixel'] == prior['sourcePixelToStagePixel'], 'source projection changed')
        require([r['source'] for r in clip['frames']] == [r['source'] for r in prior['frames']],
                'reused source measurements differ from original audit')
        clip['flags'] = copy.deepcopy(prior['flags'])
        clip['flags'].append({'code': 'timing-only-existing-evidence', 'severity': 'info',
            'message': '只更改每格停留時間；沿用完全相同 PNG、輪廓、整段倍率與格序的既有量尺。沒有新增原畫或重新量測，原動作缺中間畫與美術問題仍保留。'})
        for key in ('firstLast', 'wholeClipSpread', 'renderCalibration'):
            if key in prior:
                clip[key] = copy.deepcopy(prior[key])
        clip['sourceEvidenceReusedFrom'] = {
            'clipID': original['id'], 'catalog': 'candidates',
            'audit': original_audit_ref, 'bodyQC': qc_ref, 'measurementConfiguration': config_ref,
            'sourceSha256': original['sha256'], 'regionsSha256': original['frameRegions']['sha256'],
            'reason': 'timing-only; exact source, contour, scale, anchor and source-frame order match',
            'verifiedEqualFields': [*SAME_FIELDS, 'effectiveFrameIndices'],
            'renderingRevisionLabels': {'original': original.get('renderingRevision'),
                                        'variant': variant.get('renderingRevision'),
                                        'meaning': 'Batch labels differ; actual contour version and all source/render geometry match.'},
            'newMeasurement': False, 'newOriginalFrames': 0,
            'originalDurationsMs': original['durationsMs'], 'variantDurationsMs': variant['durationsMs'],
        }
        report['sourceReports'].append(config_ref)
    report['sourceReports'].extend([manifest_ref, original_manifest_ref, original_audit_ref])
    report['sourceReports'] = list({r['path']: r for r in report['sourceReports']}.values())
    report.update(generatedAt='2026-10-12', method='exact-source-timing-only-existing-evidence-adapter-v1',
                  newOriginalFrames=0, newSourceFrames=0, newMeasurements=0, outfitCount=0,
                  reusedSourceFrames=report['totals']['sourceFrames'], newPlaybackVariants=len(pairs),
                  limitations=[
                      '本報告只是兩個新播放 ID 對既有尺線的精確引用，沒有新增原畫、服裝或人體量測。',
                      '只允許 PNG、regions、整段倍率、落位基準、source 格序與原候選完全一致；任一改變即拒絕。',
                      '原人體不可見或閉眼格維持明示未知；原 QC、量測設定及原報告均以 SHA 綁定。',
                      '較短停留不會生成缺少的中間姿勢，沒有批准流暢度或美術；沒有改寫舊來源或報告。',
                  ])
    report['totals'].update(newOriginalFrames=0, newlyMeasuredSourceFrames=0,
                            reusedSourceFrames=report['totals']['sourceFrames'])
    return report


def fixtures():
    catalog, _ = read_json('animation/candidates.json')
    clips = {c['id']: c for c in catalog['clips']}
    original = clips['fitness-boxing-first-20261012']
    variant = clips['boxing-timing-20261012']
    identical_source_rendering(original, variant)
    fields = ('sha256', 'frameRegions', 'scale', 'anchorNormalized', 'frameIndices')
    for field in fields:
        changed = copy.deepcopy(variant)
        if field == 'frameIndices':
            changed[field] = list(reversed(sequence(changed)))
        elif field == 'scale':
            changed[field] *= 1.01
        elif field == 'anchorNormalized':
            changed[field][0] += .01
        elif field == 'frameRegions':
            changed[field]['sha256'] = '0' * 64
        else:
            changed[field] = '0' * 64
        try:
            identical_source_rendering(original, changed)
        except ValueError:
            continue
        raise AssertionError(f'changed {field} was incorrectly accepted')
    print(json.dumps({'pass': True, 'identityMutationGuards': len(fields), 'newMeasurements': 0}))


def main():
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--check', action='store_true')
    group.add_argument('--test', action='store_true')
    args = parser.parse_args()
    if args.test:
        fixtures()
        return
    report = make_report()
    payload = (json.dumps(report, ensure_ascii=False, indent=2) + '\n').encode('utf-8')
    output = HERE / 'body-scale-audit.json'
    if args.check:
        require(output.read_bytes() == payload, 'timing evidence audit stale')
    else:
        output.write_bytes(payload)
    print(json.dumps({'output': output.relative_to(ROOT).as_posix(), 'totals': report['totals'],
                      'newOriginalFrames': 0, 'newMeasurements': 0}, ensure_ascii=False))


if __name__ == '__main__':
    main()
