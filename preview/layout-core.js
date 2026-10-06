// All coordinates are in the shared 832 × 992 stage. No per-frame fitting.
export const DEFAULT_LAYOUT = Object.freeze({ id: 'classic', title: '經典陪伴', description: '上方看時間，中央看角色。',
  characterTransform: [1, 0, 0], timeCenter: [416, 109], timeFontSize: 108,
  dateCenter: [416, 205], dateFontSize: 28, informationRect: null });
export const LAYOUT_IDS = Object.freeze(['classic', 'bold', 'theater', 'activity']);
export function layoutID(value) { return LAYOUT_IDS.includes(value) ? value : 'classic'; }
export function validateLayouts(raw) {
  if (raw?.schemaVersion !== 1 || JSON.stringify(raw.coordinateSize) !== '[832,992]' || !Array.isArray(raw.layouts)) throw new Error('版式資料不完整');
  const finite = (value, length) => Array.isArray(value) && value.length === length && value.every(Number.isFinite);
  for (const value of raw.layouts) {
    if (!LAYOUT_IDS.includes(value.id) || !finite(value.characterTransform, 3) || value.characterTransform[0] <= 0 || value.characterTransform[0] > 1
      || !finite(value.timeCenter, 2) || !finite(value.dateCenter, 2) || !Number.isFinite(value.timeFontSize) || value.timeFontSize < 80 || value.timeFontSize > 180
      || !Number.isFinite(value.dateFontSize) || value.dateFontSize < 20 || value.dateFontSize > 40
      || (value.informationRect !== null && !finite(value.informationRect, 4))) throw new Error('版式位置無效');
  }
  if (raw.layouts.length !== LAYOUT_IDS.length || new Set(raw.layouts.map(value => value.id)).size !== LAYOUT_IDS.length) throw new Error('版式資料缺少項目');
  return raw.layouts;
}
export function transformRect(rect, layout = DEFAULT_LAYOUT) {
  const [scale, x, y] = layout.characterTransform;
  return [rect[0] * scale + x, rect[1] * scale + y, rect[2] * scale, rect[3] * scale];
}
export function applyLayoutDOM(layout) {
  for (const screen of document.querySelectorAll('.screen')) {
    screen.dataset.layout = layout.id;
    const values = { 'time-x': layout.timeCenter[0] / 832 * 100 + '%', 'time-y': layout.timeCenter[1] / 992 * 100 + '%',
      'time-size': layout.timeFontSize / 832 * 100 + 'cqw', 'date-x': layout.dateCenter[0] / 832 * 100 + '%',
      'date-y': layout.dateCenter[1] / 992 * 100 + '%', 'date-size': layout.dateFontSize / 832 * 100 + 'cqw' };
    for (const [key, value] of Object.entries(values)) screen.style.setProperty(`--${key}`, value);
    const panel = screen.querySelector('.layout-information');
    panel.hidden = !layout.informationRect;
    if (layout.informationRect) {
      const [x, y, width, height] = layout.informationRect;
      Object.assign(panel.style, { left: `${x / 832 * 100}%`, top: `${y / 992 * 100}%`, width: `${width / 832 * 100}%`, height: `${height / 992 * 100}%` });
    }
    const [x, y, width, height] = transformRect([83.2, 238.08, 665.6, 684.48], layout);
    Object.assign(screen.querySelector('.safe-area').style, { left: `${x / 832 * 100}%`, top: `${y / 992 * 100}%`, width: `${width / 832 * 100}%`, height: `${height / 992 * 100}%` });
    Object.assign(screen.querySelector('.baseline').style, { left: `${x / 832 * 100}%`, top: `${(y + height) / 992 * 100}%`, width: `${width / 832 * 100}%` });
  }
}
