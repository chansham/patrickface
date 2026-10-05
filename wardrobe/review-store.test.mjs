import assert from "node:assert/strict";
import { fingerprint, latestReview, migrateStorage, importReviews, exportReviews } from "./review-store.mjs";

const old = { image: "concepts/suit-v1.png", revision: "old-hash", status: "concept-review", version: 1 };
const item = { id: "suit", title: "正裝", image: "concepts/suit-v2.png", revision: "new-hash", status: "concept-review", style: "2D", version: 2, previous: old };
const original = { verdict: "rejected", note: "", image: old.image, fingerprint: fingerprint(old), reviewedAt: "2026-09-27T09:34:01.146Z", imageAvailableAtReview: true };
const legacy = { suit: original };
const legacyBefore = JSON.stringify(legacy);
const migrated = migrateStorage(null, legacy);
assert.equal(JSON.stringify(legacy), legacyBefore, "Migration must not alter the old browser data");
assert.equal(latestReview(migrated, item.id, fingerprint(item)), null, "Old rejection must not become a V2 rejection");
assert.equal(latestReview(migrated, item.id, fingerprint(old)).reviewedAt, original.reviewedAt);

const v1 = { schemaVersion: 1, scope: "wardrobe concept feedback only", concepts: {
  suit: { image: old.image, fingerprint: fingerprint(old) },
}, reviews: legacy };
const imported = importReviews(v1, [item], []);
assert.equal(imported.counts.previous, 1);
assert.equal(imported.records[0].reviewedAt, original.reviewedAt);
assert.equal(importReviews(v1, [item], imported.records).counts.duplicates, 1);

const newer = { id: item.id, ...original, verdict: "liked", note: "重新看後喜歡", reviewedAt: "2026-09-28T12:00:00.000Z" };
const merge = importReviews(v1, [item], [newer]);
assert.equal(merge.counts.older, 1);
assert.equal(merge.records.length, 2, "Older feedback must remain in history");
assert.equal(latestReview(merge.records, item.id, fingerprint(old)).verdict, "liked", "Import cannot replace a newer opinion");

const spoofed = structuredClone(v1);
spoofed.reviews.suit.fingerprint = fingerprint(item);
assert.equal(importReviews(spoofed, [item], []).counts.skipped, 1, "Matching ID without matching image must not be applied");
const mismatchedSnapshot = structuredClone(v1);
mismatchedSnapshot.concepts.suit.image = item.image;
assert.equal(importReviews(mismatchedSnapshot, [item], []).counts.skipped, 1);
const unknown = structuredClone(v1);
unknown.reviews.other = unknown.reviews.suit;
assert.equal(importReviews(unknown, [item], []).counts.skipped, 1);
assert.throws(() => importReviews({ schemaVersion: 99 }, [item], []));
assert.throws(() => importReviews({ ...v1, scope: "different app" }, [item], []));

const current = { id: item.id, ...newer, image: item.image, fingerprint: fingerprint(item), reviewedAt: "2026-09-29T12:00:00.000Z" };
const exported = exportReviews([item], [...migrated, current]);
assert.equal(exported.reviews.suit.verdict, "liked");
assert.equal(exported.history.length, 2);
const roundtrip = importReviews(exported, [item], []);
assert.equal(roundtrip.counts.current, 1);
assert.equal(roundtrip.counts.previous, 1);
assert.deepEqual(roundtrip.records, exported.history);
const equalTimeConflict = { ...original, id: item.id, verdict: "liked" };
assert.equal(latestReview(importReviews(v1, [item], [equalTimeConflict]).records, item.id, fingerprint(old)).verdict, "liked");
const pending = { ...item, image: null, revision: "", status: "revision-blocked" };
const pendingNote = { ...current, image: null, fingerprint: fingerprint(pending), verdict: null, note: "希望換成方框眼鏡" };
const pendingRoundtrip = importReviews(exportReviews([pending], [pendingNote]), [pending], []);
assert.equal(pendingRoundtrip.counts.current, 1, "Notes for an awaiting-revision item must survive export and import");
assert.equal(pendingRoundtrip.records[0].image, null);
console.log("PASS: legacy preservation, version isolation, V1/V2 imports, identity validation, timestamp precedence, duplicate merge and export roundtrip");
