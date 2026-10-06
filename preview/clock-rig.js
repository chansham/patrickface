import { clockAngles } from './experience-core.js?v=20261006-layouts1';

export function createClockRig(manifest, frames) {
  const finitePair = value => Array.isArray(value) && value.length === 2 && value.every(Number.isFinite);
  const body = manifest.body, layout = manifest.layout, hands = manifest.hands;
  if (!body || !layout || !finitePair(body.anchorPixels) || !finitePair(body.stageAnchor) || !Number.isFinite(body.pixelScale) || body.pixelScale <= 0
      || !finitePair(layout.pivot) || !Array.isArray(layout.coordinateSize) || layout.coordinateSize[0] !== 832 || layout.coordinateSize[1] !== 992
      || !Array.isArray(hands) || hands.length !== 2 || !hands.some(hand => hand.id === 'hour') || !hands.some(hand => hand.id === 'minute')) throw new Error('手臂時鐘定位資料不完整');
  for (const layer of [body, ...hands]) if (!Number.isInteger(layer.regionIndex) || !frames[layer.regionIndex]) throw new Error('手臂時鐘缺少分層畫稿');
  for (const hand of hands) if (!finitePair(hand.pivotPixels) || !Number.isFinite(hand.lengthPixels) || hand.lengthPixels <= 0
      || !Number.isFinite(hand.displayLength) || hand.displayLength <= 0) throw new Error('手臂時鐘的手臂長度無效');
  return {
    draw(contexts, date, transform = [1, 0, 0]) {
      const angles = clockAngles(date);
      for (const context of contexts) {
        context.save(); context.fillStyle = '#070609'; context.fillRect(0, 0, 832, 992);
        context.translate(transform[1], transform[2]); context.scale(transform[0], transform[0]);
        context.save();
        context.translate(body.stageAnchor[0], body.stageAnchor[1]); context.scale(body.pixelScale, body.pixelScale);
        context.drawImage(frames[body.regionIndex], -body.anchorPixels[0], -body.anchorPixels[1]); context.restore();
        for (const hand of hands) {
          context.save(); context.translate(layout.pivot[0], layout.pivot[1]);
          context.rotate(angles[hand.id] - Math.PI / 2 - (hand.sourceDirectionDegrees ?? layout.sourceDirectionDegrees ?? 0) * Math.PI / 180);
          const scale = hand.displayLength / hand.lengthPixels; context.scale(scale, scale);
          context.drawImage(frames[hand.regionIndex], -hand.pivotPixels[0], -hand.pivotPixels[1]); context.restore();
        }
        context.restore();
      }
      return angles;
    }
  };
}
