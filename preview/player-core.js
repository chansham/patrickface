// Pure frame/timing rules. Extracted contours keep source pixel scale on one canvas.
export const STAGE = Object.freeze({ width: 832, height: 992, x: 83.2, y: 248, size: 665.6, safeTop: 238.08, safeBottom: 922.56 });
export const IDLE_MIN_MS = 10000;
export const IDLE_MAX_MS = 22000;
export const BEDTIME_COOLDOWN_MS = 10 * 60 * 1000;
const clamp = (n, lo, hi) => Math.max(lo, Math.min(hi, n));

export function normalizeClip(raw) {
  if (!raw || typeof raw.id !== 'string' || !raw.id) throw new Error('動作缺少識別碼');
  const clip = { ...raw, title: raw.title || raw.id, version: raw.version ?? 1,
    scenes: Array.isArray(raw.scenes) ? raw.scenes : [], triggerKinds: Array.isArray(raw.triggerKinds) ? raw.triggerKinds : [],
    frameLabels: Array.isArray(raw.frameLabels) ? raw.frameLabels : [] };
  if (!clip.atlas) return { ...clip, available: false, unavailableReason: raw.generationNote || raw.description || '這組動作畫稿待補。' };
  if ((!clip.frameRegions && ![clip.columns, clip.rows].every(n => Number.isInteger(n) && n > 0))
      || !Number.isInteger(clip.frameCount) || clip.frameCount <= 0
      || ![clip.width, clip.height].every(n => Number.isFinite(n) && n > 0)) throw new Error(`${clip.title}：分格資料不完整`);
  clip.frameIndices = raw.frameIndices ?? Array.from({ length: clip.frameCount }, (_, i) => i);
  if (!Array.isArray(clip.frameIndices) || clip.frameIndices.length !== clip.frameCount
      || !clip.frameIndices.every(i => Number.isInteger(i) && i >= 0 && (clip.frameRegions || i < clip.columns * clip.rows))) throw new Error(`${clip.title}：來源格序列無效`);
  if (!Array.isArray(clip.durationsMs) || clip.durationsMs.length !== clip.frameCount
      || !clip.durationsMs.every(n => Number.isFinite(n) && n > 0 && n <= 60000)) throw new Error(`${clip.title}：每格時間無效`);
  clip.ends = []; let sum = 0;
  for (const duration of clip.durationsMs) clip.ends.push(sum += duration);
  clip.totalMs = sum; clip.available = true;
  return clip;
}

export function sourceRect(clip, index) {
  if (clip.renderCanvas) return [0, 0, clip.renderCanvas.width, clip.renderCanvas.height];
  const cell = clip.frameIndices[clamp(index, 0, clip.frameCount - 1)];
  const width = clip.width / clip.columns, height = clip.height / clip.rows;
  return [(cell % clip.columns) * width, Math.floor(cell / clip.columns) * height, width, height];
}

export function destinationRect(clip, master = {}) {
  // One scale and rectangle for the ENTIRE clip. Source and master anchors
  // align across clips; no frame's painted bounds influence this transform.
  const aspect = clip.renderCanvas ? clip.renderCanvas.width / clip.renderCanvas.height
    : (clip.width / clip.columns) / (clip.height / clip.rows);
  const scale = Number.isFinite(clip.scale) && clip.scale > 0 ? clip.scale : 1;
  const width = STAGE.size * Math.min(1, aspect) * scale;
  const height = STAGE.size * Math.min(1, 1 / aspect) * scale;
  const validAnchor = value => Array.isArray(value) && value.length === 2 && value.every(n => Number.isFinite(n) && n >= 0 && n <= 1);
  const target = validAnchor(master.anchorNormalized) ? master.anchorNormalized : [0.5, 0.88];
  const anchor = validAnchor(clip.renderCanvas?.anchorNormalized) ? clip.renderCanvas.anchorNormalized
    : validAnchor(clip.anchorNormalized) ? clip.anchorNormalized : target;
  return [STAGE.x + STAGE.size * target[0] - width * anchor[0],
    STAGE.y + STAGE.size * target[1] - height * anchor[1], width, height];
}

export function validateFrameRegions(clip, metadata) {
  const fail = message => { throw new Error(`${clip.title}：輪廓資料${message}`); };
  const integers = (array, count) => Array.isArray(array) && array.length === count && array.every(Number.isInteger);
  if (metadata?.schemaVersion !== 1) fail('版本不支援');
  const source = metadata.source;
  if (!source || source.path !== clip.atlas || source.width !== clip.width || source.height !== clip.height
      || typeof source.sha256 !== 'string' || source.sha256.toLowerCase() !== clip.sha256.toLowerCase()) fail('與來源原圖不符');
  const canvas = metadata.canvas;
  if (!canvas || !Number.isInteger(canvas.width) || canvas.width < 1 || canvas.width > 4096
      || canvas.height !== canvas.width || !integers(canvas.anchorPixels, 2)
      || !Array.isArray(canvas.anchorNormalized) || canvas.anchorNormalized.length !== 2
      || canvas.anchorPixels.some((n, i) => n < 0 || n > (i ? canvas.height : canvas.width))
      || canvas.anchorNormalized.some((n, i) => !Number.isFinite(n) || Math.abs(n - canvas.anchorPixels[i] / canvas.width) > 1e-9)) fail('共同畫布或腳底錨點無效');
  if (!Array.isArray(metadata.frames) || !metadata.frames.length || metadata.frames.length > 256
      || clip.frameIndices.some(index => index >= metadata.frames.length)) fail('來源幀不足');
  metadata.frames.forEach((frame, index) => {
    if (!integers(frame.sourceBounds, 4) || !integers(frame.translation, 2) || !integers(frame.placement, 2)
        || !integers(frame.anchorSource, 2)) fail(`第 ${index + 1} 幀座標必須是整數`);
    const [left, top, width, height] = frame.sourceBounds, [dx, dy] = frame.translation;
    if (left < 0 || top < 0 || width <= 0 || height <= 0 || left + width > clip.width || top + height > clip.height) fail(`第 ${index + 1} 幀越過原圖`);
    if (frame.placement[0] !== left + dx || frame.placement[1] !== top + dy) fail(`第 ${index + 1} 幀放置座標不一致`);
    if (frame.anchorSource[0] + dx !== canvas.anchorPixels[0] || frame.anchorSource[1] + dy !== canvas.anchorPixels[1]) fail(`第 ${index + 1} 幀腳底未對齊`);
    if (!Array.isArray(frame.rows) || !frame.rows.length) fail(`第 ${index + 1} 幀沒有輪廓`);
    let previousY = -1, pixelCount = 0;
    for (const row of frame.rows) {
      if (!Array.isArray(row) || row.length < 3 || row.length % 2 !== 1 || !row.every(Number.isInteger)) fail(`第 ${index + 1} 幀遮罩格式無效`);
      const y = row[0];
      if (y <= previousY || y < top || y >= top + height || y + dy < 0 || y + dy >= canvas.height) fail(`第 ${index + 1} 幀遮罩列越界或重複`);
      previousY = y; let previousRight = -1;
      for (let i = 1; i < row.length; i += 2) {
        const x0 = row[i], x1 = row[i + 1];
        if (x0 < left || x1 > left + width || x0 >= x1 || x0 < previousRight
            || x0 + dx < 0 || x1 + dx > canvas.width) fail(`第 ${index + 1} 幀遮罩區段越界或重疊`);
        previousRight = x1; pixelCount += x1 - x0;
      }
    }
    if (!pixelCount) fail(`第 ${index + 1} 幀遮罩為空`);
  });
  return metadata;
}

export function frameAt(clip, elapsed) {
  const index = clip.ends.findIndex(end => elapsed < end);
  return index < 0 ? clip.frameCount - 1 : index;
}

export function isIdleClip(clip) {
  return Boolean(clip.idleVariant || clip.category === 'idle' || clip.triggerKinds.includes('idle'));
}

export class IdleScheduler {
  constructor(random = Math.random) { this.random = random; this.nextAt = null; this.lastId = null; }
  reset() { this.nextAt = null; }
  step(now, { eligible, playing, clips }) {
    if (!eligible || playing || !clips.length) { this.reset(); return null; }
    if (this.nextAt === null) {
      this.nextAt = now + IDLE_MIN_MS + clamp(this.random(), 0, 1) * (IDLE_MAX_MS - IDLE_MIN_MS);
      return null;
    }
    if (now < this.nextAt) return null;
    this.reset();
    // Even a catalog containing one idle never produces consecutive repeats.
    const choices = clips.filter(clip => clip.id !== this.lastId);
    if (!choices.length) return null;
    const clip = choices[Math.min(choices.length - 1, Math.floor(clamp(this.random(), 0, 1) * choices.length))];
    this.lastId = clip.id;
    return clip;
  }
}

export function restoreEvents(raw, now = Date.now()) {
  const safeTime = n => Number.isFinite(n) && n >= 0 ? Math.min(n, now) : null;
  return { version: 1, bedtimeLastAt: safeTime(raw?.bedtimeLastAt), timerHandledAt: safeTime(raw?.timerHandledAt) };
}

export function bedtimeRemaining(events, now = Date.now()) {
  if (events.bedtimeLastAt === null) return 0;
  return Math.max(0, BEDTIME_COOLDOWN_MS - Math.max(0, now - events.bedtimeLastAt));
}

export function automaticAllowed(context) {
  return Boolean(context.enabled && !context.hidden && !context.reduced && !context.wristDown
    && !context.lowPower && !context.reviewing);
}

export function reviewKey(clip) {
  return `patrick.animation-review.${clip.id}.v${clip.version}.${clip.sha256}`;
}

export function cleanReview(raw, clip) {
  const result = { asset: clip.id, version: clip.version, sha256: clip.sha256, sections: {
    action: { frames: {}, note: '' }, outfit: { frames: {}, note: '' } }, updatedAt: null };
  if (!raw || raw.sha256 !== clip.sha256 || raw.version !== clip.version) return result;
  // Preserve any explicitly recorded historical rendering provenance. Do not
  // replace it with the current extraction revision while restoring old notes.
  if (Object.hasOwn(raw, 'rendering')) result.rendering = raw.rendering;
  for (const scope of ['action', 'outfit']) {
    const input = raw.sections?.[scope] || (scope === 'action' ? raw : null);
    if (!input) continue;
    result.sections[scope].note = typeof input.note === 'string' ? input.note.slice(0, 8000) : '';
    for (let i = 0; i < clip.frameCount; i++) if (['liked', 'revise', 'rejected'].includes(input.frames?.[i])) result.sections[scope].frames[i] = input.frames[i];
  }
  result.updatedAt = typeof raw.updatedAt === 'string' ? raw.updatedAt : null;
  return result;
}
