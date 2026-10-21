"""Current catalog inventory; preserve the earlier motion-batch snapshot.

Source review membership is a scope label, never visual or user art approval.
"""
import csv
import importlib.util
import io
from pathlib import Path


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
SPEC = importlib.util.spec_from_file_location(
    'motion_inventory', ROOT / 'animation/production-20261012-motion/inventory_catalogs.py')
BASE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(BASE)
BASE.OUTPUT = ROOT / 'output/animation-inventory-20261012-inbetweens'
BASE_BUILD = BASE.build
BASE_CSV_TEXT = BASE.csv_text
MANIFEST_PATH = 'animation/production-20261012-inbetweens/manifest.json'
VISUAL_REVIEW_PATH = 'animation/production-20261012-inbetweens/visual-review-root.json'


def build():
    report = BASE_BUILD()
    manifest, manifest_sha = BASE.read_json(MANIFEST_PATH)
    visual_review, visual_sha = BASE.read_json(VISUAL_REVIEW_PATH)
    BASE.require(manifest.get('artApproval') is False, 'batch art approval must remain false')
    BASE.require(visual_review.get('artApproval') is False, 'visual record art approval must remain false')
    candidates = {r['clipID']: r for r in report['clips'] if r['catalog'] == 'candidates'}
    inspected = {r['id']: r for r in visual_review['clips']}
    review_sources = []
    identities = set()
    latest_ids = set()
    for source in manifest['sources']:
        cid = source['id']
        BASE.require(cid not in latest_ids, f'duplicate latest source: {cid}')
        latest_ids.add(cid)
        BASE.require(cid in candidates and cid in inspected, f'unmatched latest source: {cid}')
        row, review = candidates[cid], inspected[cid]
        BASE.require(row['sourcePath'] == source['source'] == review['source'], f'latest source path mismatch: {cid}')
        BASE.require(row['sourceSha256'] == source['sha256'] == review['sha256'], f'latest source SHA mismatch: {cid}')
        BASE.require(review.get('sourceViewed') is True and review.get('blackWhiteViewed') is True,
                     f'latest source inspection evidence missing: {cid}')
        BASE.require(row['sourceFramesOneBased'] == [i + 1 for i in source['frameIndices']],
                     f'latest source order mismatch: {cid}')
        source_frames = list(range(1, row['sourceRegionCount'] + 1))
        identities.update((row['sourceSha256'], i) for i in source_frames)
        review_sources.append({
            'clipID': cid, 'sourcePath': row['sourcePath'], 'sourceSha256': row['sourceSha256'],
            'sourceFrameCount': row['sourceRegionCount'], 'sourceFramesOneBased': source_frames,
            'sourceViewed': True, 'blackWhiteViewed': True,
            'runtimeReviewFromVisualRecord': review.get('runtimeReview', 'not-recorded'),
            'artApproval': False,
        })
    BASE.require(len(latest_ids) == 2 and len(identities) == 22,
                 'latest batch must describe exactly two sources / 22 source frame identities')
    for row in report['clips']:
        row['inLatestBatchVisualReviewScope'] = row['catalog'] == 'candidates' and row['clipID'] in latest_ids
    report['reviewedAt'] = '2026-10-13'
    report['sourceReferences'].extend([
        {'path': MANIFEST_PATH, 'sha256': manifest_sha},
        {'path': VISUAL_REVIEW_PATH, 'sha256': visual_sha},
    ])
    report['recentVisualReview']['scopeLabel'] = 'prior-ten-source-84-frame-visual-review'
    report['recentVisualReview']['note'] = (
        'Historical ten-source / 84-source-frame review only. Latest batch inspection is reported '
        'separately in latestBatchReview. Outside either scope does not imply never reviewed '
        'historically; source inspection does not establish animation quality or art approval.')
    report['latestBatchReview'] = {
        'batch': manifest['batch'], 'scopeLabel': 'latest-two-source-22-frame-source-inspection',
        'reviewedAtFromVisualRecord': visual_review['reviewedAt'],
        'manifest': {'path': MANIFEST_PATH, 'sha256': manifest_sha},
        'visualReviewRecord': {'path': VISUAL_REVIEW_PATH, 'sha256': visual_sha},
        'candidateClipCount': len(latest_ids),
        'uniqueSourcePNGCount': len({sha for sha, _ in identities}),
        'newlyReviewedSourceFrameCount': len(identities),
        'artApproval': False, 'sources': review_sources,
        'note': ('Two newly generated sources were visually inspected, including black/white '
                 'composites; unresolved transition and proportion findings remain in the cited '
                 'records. This is not approval of all candidates, not 22 distinct new motion '
                 'poses, and not proof that runtime/native playback has passed.'),
    }
    return report


def csv_text(report):
    previous = csv.DictReader(io.StringIO(BASE_CSV_TEXT(report), newline=''))
    stream = io.StringIO(newline='')
    writer = csv.DictWriter(stream, fieldnames=list(previous.fieldnames) + ['inLatestBatchVisualReviewScope'])
    writer.writeheader()
    scopes = {(r['catalog'], r['clipID']): r['inLatestBatchVisualReviewScope'] for r in report['clips']}
    for row in previous:
        row['inLatestBatchVisualReviewScope'] = scopes[(row['catalog'], row['clipID'])]
        writer.writerow(row)
    return stream.getvalue()


BASE.build = build
BASE.csv_text = csv_text


if __name__ == '__main__':
    BASE.main()
