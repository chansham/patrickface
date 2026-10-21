"""Inventory source identities and playback slots; never edits the catalogs.

One source frame is (PNG SHA-256, zero-based region index), not a play slot,
filename, grid capacity, timing variant, or a judgment that two poses look unique.
"""
from collections import Counter, defaultdict
from pathlib import Path, PurePosixPath
import argparse
import csv
import hashlib
import io
import json
import math
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / 'output/animation-inventory-20261012'
CATALOGS = {'main': 'animation/catalog.json', 'candidates': 'animation/candidates.json'}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def read_file(path):
    rel = PurePosixPath(path)
    if rel.is_absolute() or '..' in rel.parts or ':' in path or '\\' in path:
        raise ValueError(f'not a project-relative path: {path}')
    target = ROOT / rel
    if not target.resolve().is_relative_to(ROOT.resolve()) or not target.is_file():
        raise ValueError(f'missing project file: {path}')
    return target.read_bytes()


def read_json(path):
    raw = read_file(path)
    return json.loads(raw.decode('utf-8-sig')), digest(raw)


def require(condition, message):
    if not condition:
        raise ValueError(message)


def runtime_classification(kind, clip):
    if kind == 'candidates':
        return 'manual-review-one-shot-or-group-once'
    if clip.get('idleVariant') or clip.get('category') == 'idle' or 'idle' in clip.get('triggerKinds', []):
        return 'scheduled-idle-one-shot-10-to-22-seconds-when-eligible'
    if 'bedtime-entry' in clip.get('triggerKinds', []):
        return 'bedtime-entry-one-shot-with-cooldown-or-manual'
    return 'context-or-manual-one-shot'


def build():
    refs, rows, assets = [], [], {}
    for kind, path in CATALOGS.items():
        catalog, catalog_sha = read_json(path)
        refs.append({'path': path, 'sha256': catalog_sha})
        ids = set()
        for clip in catalog['clips']:
            cid = clip['id']
            require(cid not in ids, f'duplicate ID {kind}/{cid}')
            ids.add(cid)
            raw = read_file(clip['atlas'])
            source_sha = digest(raw)
            require(source_sha == clip['sha256'], f'PNG SHA mismatch: {cid}')
            with Image.open(io.BytesIO(raw)) as image:
                dimensions = list(image.size)
            require(dimensions == [clip['width'], clip['height']], f'PNG dimensions mismatch: {cid}')
            regions, regions_sha = read_json(clip['frameRegions']['path'])
            require(regions_sha == clip['frameRegions']['sha256'], f'regions SHA mismatch: {cid}')
            require(regions['source'] == {'path': clip['atlas'], 'sha256': source_sha,
                    'width': dimensions[0], 'height': dimensions[1]}, f'regions source mismatch: {cid}')
            frame_count = len(regions['frames'])
            require(frame_count == clip['columns'] * clip['rows'], f'region/grid count mismatch: {cid}')
            count = clip['frameCount']
            require(type(count) is int and count > 0, f'invalid frame count: {cid}')
            order = clip.get('frameIndices', list(range(count)))
            require(len(order) == count and all(type(i) is int and 0 <= i < frame_count for i in order),
                    f'invalid source index/order: {cid}')
            durations = clip['durationsMs']
            require(len(durations) == count and all(type(t) in (int, float) and math.isfinite(t)
                    and 0 < t <= 60000 for t in durations), f'invalid durations: {cid}')
            counts = Counter(order)
            row = {
                'catalog': kind, 'clipID': cid, 'title': clip['title'], 'version': clip.get('version'),
                'sourcePath': clip['atlas'], 'sourceSha256': source_sha,
                'regionsPath': clip['frameRegions']['path'], 'regionsSha256': regions_sha,
                'sourceRegionCount': frame_count, 'playbackFrameCount': count,
                'referencedSourceFrameCount': len(counts),
                'repeatedPlaybackSlotsWithinClip': count - len(counts),
                'sourceFramesOneBased': [i + 1 for i in order],
                'omittedSourceFramesOneBased': [i + 1 for i in range(frame_count) if i not in counts],
                'repeatedSourceFrames': [{'sourceFrame': i + 1, 'playbackOccurrences': n}
                                         for i, n in sorted(counts.items()) if n > 1],
                'durationsMs': durations, 'durationMs': sum(durations),
                'durationSeconds': sum(durations) / 1000,
                'runtimeClassification': runtime_classification(kind, clip),
                'continuousLoop': False, 'artLoopSeamApproval': 'not-assessed-by-inventory',
                'triggerKinds': clip.get('triggerKinds', []), 'scenes': clip.get('scenes', []),
                'statusFromCatalog': clip.get('status'), 'artApproval': False,
                'variantKind': clip.get('variantKind'),
                'sourceCandidateID': clip.get('sourceCandidateID'),
            }
            rows.append(row)
            if source_sha in assets:
                require(assets[source_sha]['sourceRegionCount'] == frame_count, f'same PNG has incompatible regions: {cid}')
            else:
                assets[source_sha] = {'sourceSha256': source_sha, 'sourcePaths': [],
                                     'sourceRegionCount': frame_count, 'references': []}
            if clip['atlas'] not in assets[source_sha]['sourcePaths']:
                assets[source_sha]['sourcePaths'].append(clip['atlas'])
            assets[source_sha]['references'].append({'catalog': kind, 'clipID': cid})

    def keys(subset):
        return {(r['sourceSha256'], i) for r in subset for i in r['sourceFramesOneBased']}

    def stats(subset):
        used = keys(subset)
        shas = {r['sourceSha256'] for r in subset}
        play_count = sum(r['playbackFrameCount'] for r in subset)
        return {
            'clipCount': len(subset), 'playbackFrameCount': play_count,
            'uniqueReferencedSourceFrameCount': len(used),
            'reusedPlaybackSlotsAcrossClips': play_count - len(used),
            'uniqueSourcePNGCount': len(shas),
            'allRegionSlotsInReferencedPNGs': sum(assets[s]['sourceRegionCount'] for s in shas),
            'durationMsIfEachClipPlayedOnceWithoutGaps': sum(r['durationMs'] for r in subset),
            'durationSecondsIfEachClipPlayedOnceWithoutGaps': sum(r['durationMs'] for r in subset) / 1000,
            'continuousLoopCount': 0,
            'runtimeClassificationCounts': dict(sorted(Counter(r['runtimeClassification'] for r in subset).items())),
        }

    by_catalog = {kind: [r for r in rows if r['catalog'] == kind] for kind in CATALOGS}
    main_keys, candidate_keys = keys(by_catalog['main']), keys(by_catalog['candidates'])
    summaries = {kind: stats(subset) for kind, subset in by_catalog.items()}
    summaries['combined'] = stats(rows)
    summaries['candidatesExcludingTimingOnlyVariants'] = stats([r for r in by_catalog['candidates'] if r['variantKind'] != 'timing-only'])
    summaries['overlap'] = {
        'sharedReferencedSourceFrameCount': len(main_keys & candidate_keys),
        'mainOnlyReferencedSourceFrameCount': len(main_keys - candidate_keys),
        'candidateOnlyReferencedSourceFrameCount': len(candidate_keys - main_keys),
        'sharedSourcePNGCount': len({s for s, _ in main_keys} & {s for s, _ in candidate_keys}),
    }
    same_order = defaultdict(list)
    for row in rows:
        same_order[(row['sourceSha256'], tuple(row['sourceFramesOneBased']))].append(row)
    timing_groups = []
    for (source_sha, order), group in same_order.items():
        if len(group) > 1:
            timing_groups.append({'sourceSha256': source_sha, 'sourceFramesOneBased': list(order),
                'hasTimingVariation': len({tuple(r['durationsMs']) for r in group}) > 1,
                'references': [{'catalog': r['catalog'], 'clipID': r['clipID'], 'durationMs': r['durationMs']}
                               for r in group]})
    review, review_sha = read_json('animation/production-20261012-review/art-priorities.json')
    refs.append({'path': 'animation/production-20261012-review/art-priorities.json', 'sha256': review_sha})
    reviewed_keys = {(r['sourceSha256'], i) for r in review['clips'] for i in range(1, r['sourceFrameCount'] + 1)}
    reviewed_ids = {r['clipID'] for r in review['clips']}
    reviewed_source_variants = []
    for r in rows:
        r['inRecentTenSourceVisualReviewScope'] = (r['catalog'] == 'candidates' and r['clipID'] in reviewed_ids)
        r['usesOnlySourceFramesInRecentVisualReview'] = keys([r]).issubset(reviewed_keys)
        if r['catalog'] == 'candidates' and r['clipID'] not in reviewed_ids and r['usesOnlySourceFramesInRecentVisualReview']:
            reviewed_source_variants.append(r['clipID'])
    runtime_refs = []
    for path in ('preview/app.js', 'preview/player-core.js'):
        runtime_refs.append({'path': path, 'sha256': digest(read_file(path))})
    return {
        'schemaVersion': 1, 'reviewedAt': '2026-10-12', 'artApproval': False,
        'scope': 'Current main and candidate catalogs only; excludes unreferenced drafts, blocked requests, renders, thumbnails, old packages, and native runtime.',
        'identityRule': '(PNG SHA-256, source frame index). JSON frame lists use one-based numbers; catalog frameIndices are zero-based.',
        'identityLimit': 'Source frame identity counts do not establish visually distinct poses, smooth transitions, outfit count, anatomical consistency, or art approval.',
        'sourceReferences': refs, 'runtimeReferences': runtime_refs, 'summary': summaries,
        'recentVisualReview': {
            'candidateClipCount': len(reviewed_ids), 'uniqueSourceFrameCount': len(reviewed_keys),
            'remainingCandidateClipsNotCoveredByThisRecentReview': len(by_catalog['candidates']) - len(reviewed_ids),
            'additionalVariantsReusingOnlyAlreadyReviewedSourceFrames': reviewed_source_variants,
            'candidateClipsUsingSourcesOutsideThisRecentReview': sum(not r['usesOnlySourceFramesInRecentVisualReview'] for r in by_catalog['candidates']),
            'remainingCandidateSourceFramesNotCoveredByThisRecentReview': len(candidate_keys - reviewed_keys),
            'artApproval': False, 'note': 'Not in this recent review does not imply never reviewed historically; no new visual approval is inferred.',
        },
        'runtimeNotes': [
            'Browser player stops on its last frame. There is no continuous modulo loop.',
            'Idle clips are individually scheduled after 10–22 seconds when eligible; avoid consecutive repeats of the same clip ID. Same source may still underlie different IDs.',
            'Bedtime yawn is one-shot on eligible entry, with 10 minute cooldown; other actions play as context/manual one-shots.',
            'Candidate group review plays matching loaded clips once each at 1x with 350 ms between clips, then stops. Summed durations exclude these pauses.',
            'These classifications describe current browser code, not Apple Watch native execution or a smooth artwork loop.',
        ],
        'sources': list(assets.values()), 'clips': rows,
        'sharedPNGGroups': [a for a in assets.values() if len(a['references']) > 1],
        'sameSourceOrderGroups': timing_groups,
        'withinClipReuse': [r for r in rows if r['repeatedPlaybackSlotsWithinClip']],
        'omittedSourceFrameClips': [r for r in rows if r['omittedSourceFramesOneBased']],
        'thirteenPlaybackTwelveSourceExamples': [r for r in rows if r['playbackFrameCount'] == 13 and r['referencedSourceFrameCount'] == 12],
        'notes': [
            'Per-clip unique source counts cannot simply be summed across clips: timing variants can reference the same source PNG and source indices.',
            'No 13-playback/12-source example was assumed from old reports: see the computed examples list.',
            'The normal blink description still says not added to automatic idle; current runtime schedules eligible idle clips. Metadata prose can lag implementation.',
        ],
    }


def csv_text(report):
    stream = io.StringIO(newline='')
    fields = ['catalog', 'clipID', 'title', 'playbackFrameCount', 'referencedSourceFrameCount',
              'sourceRegionCount', 'repeatedPlaybackSlotsWithinClip', 'durationSeconds',
              'runtimeClassification', 'continuousLoop', 'inRecentTenSourceVisualReviewScope',
              'sourceFramesOneBased', 'omittedSourceFramesOneBased', 'durationsMs', 'sourcePath', 'sourceSha256']
    writer = csv.DictWriter(stream, fieldnames=fields, extrasaction='ignore')
    writer.writeheader()
    for row in report['clips']:
        flat = dict(row)
        for key in ('sourceFramesOneBased', 'omittedSourceFramesOneBased', 'durationsMs'):
            flat[key] = ' '.join(map(str, flat[key]))
        writer.writerow(flat)
    return stream.getvalue()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    report = build()
    outputs = {'inventory.json': json.dumps(report, ensure_ascii=False, indent=2) + '\n',
               'clips.csv': csv_text(report)}
    for name, text in outputs.items():
        path = OUTPUT / name
        if args.check:
            require(path.read_bytes() == text.encode('utf-8-sig' if name.endswith('.csv') else 'utf-8'),
                    f'inventory snapshot changed: {name}')
        else:
            OUTPUT.mkdir(parents=True, exist_ok=True)
            path.write_bytes(text.encode('utf-8-sig' if name.endswith('.csv') else 'utf-8'))
    print(json.dumps({'status': 'PASS', 'summary': report['summary'], 'recentVisualReview': report['recentVisualReview'],
                      'output': str(OUTPUT)}, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
