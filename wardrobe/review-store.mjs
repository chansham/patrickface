export const STORAGE_KEY = "patrick.wardrobe-review.v2";
export const LEGACY_STORAGE_KEY = "patrick.wardrobe-review.v1";
export const VERDICTS = Object.freeze({ liked: "喜歡", revise: "修改", rejected: "不喜歡" });
const ID = /^[a-zA-Z0-9_-]+$/;
const object = value => value !== null && typeof value === "object" && !Array.isArray(value);

export function fingerprint(item) {
  return `${item.image || "pending"}|${item.revision || item.sha256 || ""}|${item.status || "concept-review"}`;
}

function normalizeReview(id, value) {
  if (!ID.test(id) || !object(value)) return null;
  if (value.verdict !== null && value.verdict !== undefined && !Object.hasOwn(VERDICTS, value.verdict)) return null;
  if (value.note !== undefined && typeof value.note !== "string") return null;
  return { id, verdict: value.verdict || null, note: value.note || "",
    image: value.image === null ? null : typeof value.image === "string" ? value.image : "",
    fingerprint: typeof value.fingerprint === "string" ? value.fingerprint : "",
    reviewedAt: typeof value.reviewedAt === "string" ? value.reviewedAt : "",
    imageAvailableAtReview: value.imageAvailableAtReview === true };
}

function recordKey(record) {
  return JSON.stringify([record.id, record.fingerprint, record.reviewedAt, record.verdict, record.note, record.image]);
}

export function mergeRecords(records, incoming) {
  const result = [...records];
  const keys = new Set(result.map(recordKey));
  for (const record of incoming) {
    const key = recordKey(record);
    if (!keys.has(key)) { result.push(record); keys.add(key); }
  }
  return result;
}

export function migrateStorage(current, legacy) {
  const records = object(current) && current.schemaVersion === 2 && Array.isArray(current.records)
    ? current.records.map(value => normalizeReview(value?.id || "", value)).filter(Boolean) : [];
  const oldRecords = object(legacy)
    ? Object.entries(legacy).map(([id, value]) => normalizeReview(id, value)).filter(Boolean) : [];
  // Keep legacy records even if their version can no longer be identified.
  // They remain history, never silently becoming a vote for a different image.
  return mergeRecords(records, oldRecords);
}

export function latestReview(records, id, versionFingerprint) {
  return records.filter(record => record.id === id && record.fingerprint === versionFingerprint)
    .reduce((latest, record) => {
      if (!latest) return record;
      const nextTime = Date.parse(record.reviewedAt) || 0;
      const previousTime = Date.parse(latest.reviewedAt) || 0;
      // On a timestamp tie, keep the existing local record, not an imported conflict.
      return nextTime > previousTime ? record : latest;
    }, null);
}

export function knownVersions(item) {
  return [item, ...(item.previous ? [item.previous] : [])];
}

export function importReviews(payload, items, records) {
  if (!object(payload) || ![1, 2].includes(payload.schemaVersion)
      || payload.scope !== "wardrobe concept feedback only" || !object(payload.concepts)
      || !object(payload.reviews) || (payload.schemaVersion === 2 && !Array.isArray(payload.history))) {
    throw new Error("這不是可讀取的衣櫥意見檔。請選擇從衣櫥匯出的 JSON 檔案。");
  }
  const raw = payload.schemaVersion === 2
    ? payload.history.map(value => [value?.id, value]) : Object.entries(payload.reviews);
  if (raw.length > 10000) throw new Error("這份意見檔的記錄太多，請改用較小的匯出檔。");
  const catalog = new Map(items.map(item => [item.id, item]));
  const accepted = [];
  const counts = { current: 0, previous: 0, skipped: 0, older: 0, duplicates: 0 };
  const existingKeys = new Set(records.map(recordKey));
  for (const [id, value] of raw) {
    const review = typeof id === "string" ? normalizeReview(id, value) : null;
    const item = catalog.get(id);
    const version = item && review && knownVersions(item).find(candidate =>
      fingerprint(candidate) === review.fingerprint && candidate.image === review.image);
    const snapshot = payload.concepts[id];
    // V1 has one snapshot per item. V2 carries a versioned history; the current
    // catalog still has to recognize every imported image and fingerprint.
    const snapshotMatches = payload.schemaVersion === 2 || (object(snapshot)
      && snapshot.image === review?.image && snapshot.fingerprint === review?.fingerprint);
    if (!review || !version || !snapshotMatches || !Number.isFinite(Date.parse(review.reviewedAt))) {
      counts.skipped++; continue;
    }
    if (existingKeys.has(recordKey(review))) { counts.duplicates++; continue; }
    const existing = latestReview([...records, ...accepted], id, review.fingerprint);
    if (existing && Date.parse(existing.reviewedAt) >= Date.parse(review.reviewedAt)) counts.older++;
    counts[version === item ? "current" : "previous"]++;
    accepted.push(review); existingKeys.add(recordKey(review));
  }
  return { records: mergeRecords(records, accepted), counts };
}

export function exportReviews(items, records, exportedAt = new Date().toISOString()) {
  const concepts = Object.fromEntries(items.map(item => [item.id, {
    title: item.title, image: item.image, category: item.category, mood: item.mood,
    style: item.style, version: item.version, status: item.status,
    fingerprint: fingerprint(item), previous: item.previous ? {
      title: item.previous.title, image: item.previous.image,
      fingerprint: fingerprint(item.previous), version: item.previous.version,
    } : null,
  }]));
  const reviews = Object.fromEntries(items.map(item => [item.id, latestReview(records, item.id, fingerprint(item))])
    .filter(([, review]) => review));
  return { schemaVersion: 2, scope: "wardrobe concept feedback only", exportedAt,
    concepts, reviews, history: records };
}
