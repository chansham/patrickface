// Frame reviews are separate from legacy whole-clip notes and from art approval.
export const FRAME_REVIEW_KEY = 'patrick.frame-review.v1';
export const ISSUE_TYPES = Object.freeze({ size: '大小／比例', crop: '裁剪／遮擋', eyes: '眼睛／配色', motion: '動作／接續', outfit: '服裝／道具' });
export function feedbackTarget(clip, playbackFrame, layout, masterAnchor, viewportWidth) {
  const sourceFrame = clip.frameIndices[playbackFrame];
  if (!Number.isInteger(sourceFrame) || sourceFrame < 0 || !Number.isInteger(playbackFrame) || !layout?.id) throw new Error('尚未選定可核對的畫格');
  return { schemaVersion: 1, clipID: clip.id, clipTitle: clip.title, clipVersion: clip.version, catalog: clip.catalogKind || 'catalog',
    sourceSha256: clip.sha256, regionsSha256: clip.frameRegions.sha256, atlas: clip.atlas,
    playbackFrame, sourceFrame, frameNumbering: 'zero-based', playbackFrameNumber: playbackFrame + 1, sourceFrameNumber: sourceFrame + 1, layoutID: layout.id,
    rendering: { scale: clip.scale, masterAnchor: [...masterAnchor], layout: structuredClone(layout), stage: [832, 992] },
    viewportWidth: Math.round(viewportWidth), artApproval: false };
}
export function feedbackKey(target) {
  return JSON.stringify([target.catalog, target.clipID, target.clipVersion, target.sourceSha256, target.regionsSha256,
    target.playbackFrame, target.sourceFrame, target.layoutID, target.rendering, target.viewportWidth]);
}
export function feedbackRecord(target, issues, text, previous, at = new Date().toISOString()) {
  const issueTypes = [...new Set(issues)].filter(value => Object.hasOwn(ISSUE_TYPES, value));
  return { ...structuredClone(target), issueTypes, text: String(text).slice(0, 4000), createdAt: previous?.createdAt || at, updatedAt: at, artApproval: false };
}
export function sameFeedbackSource(note, clip) {
  return !!clip && note.catalog === (clip.catalogKind || 'catalog') && note.clipID === clip.id && note.clipVersion === clip.version
    && note.sourceSha256 === clip.sha256 && note.regionsSha256 === clip.frameRegions?.sha256;
}
