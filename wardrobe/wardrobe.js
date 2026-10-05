import { STORAGE_KEY, LEGACY_STORAGE_KEY, VERDICTS, fingerprint, latestReview, migrateStorage,
  mergeRecords, importReviews, exportReviews } from "./review-store.mjs";
const MANIFEST = "../concepts/wardrobe.json";
const $ = selector => document.querySelector(selector);
const CATEGORY_NAMES = { sleep: "睡前", daily: "日常", work: "工作", leisure: "休閒" };
const CATEGORY_ALIASES = {
  sleep: "sleep", bedtime: "sleep", sleeping: "sleep", sleepwear: "sleep", "睡前": "sleep", "睡眠": "sleep",
  daily: "daily", everyday: "daily", charging: "daily", "日常": "daily",
  work: "work", office: "work", formal: "work", "工作": "work", "職場": "work",
  leisure: "leisure", casual: "leisure", relaxation: "leisure", relax: "leisure", fitness: "leisure", bath: "leisure", "休閒": "leisure", "放鬆": "leisure",
};
const MOOD_LINES = {
  serious: "「今天，我是認真的。」", "嚴肅": "「今天，我是認真的。」", "認真": "「今天，我是認真的。」",
  calm: "「不用趕，我們慢慢來。」", "平靜": "「不用趕，我們慢慢來。」", "放鬆": "「今天先把肩膀放下來。」",
  sleepy: "「剩下的事情，明天再說。」", "睏倦": "「剩下的事情，明天再說。」", "想睡": "「剩下的事情，明天再說。」",
  confident: "「穿好這一身，就出發吧。」", "自信": "「穿好這一身，就出發吧。」",
  happy: "「今天，有一點好心情。」", "開心": "「今天，有一點好心情。」", "得意": "「嗯，今天這身不錯。」",
  tired: "「我先歇一會，你也別太勉強。」", "疲倦": "「我先歇一會，你也別太勉強。」", "慵懶": "「現在，是我的慢半拍時間。」",
  blank: "「……讓我再放空一下。」", "放空": "「……讓我再放空一下。」", "無奈": "「好吧，先深呼吸一下。」",
  "不耐煩": "「再五分鐘，真的就五分鐘。」", "沉思": "「宇宙很大，明天吃什麼也很重要。」", "發呆": "「我有在刷牙，思緒只是暫時出門了。」", "懷疑": "「等一下，這件事有點意思。」",
};
const FALLBACK_LINES = { sleep: "「換好睡衣，今天就到這裡。」", daily: "「今天，想用這個樣子陪你。」", work: "「先整理好自己，再處理世界。」", leisure: "「留一點時間，什麼也不急。」" };
let items = [], selectedCategory = "", selectedId = null, loadSequence = 0;
let records = [], noteDraftRecord = null;
let storageAvailable = true;
const imageStates = new Map();

function text(value, fallback = "") { return typeof value === "string" ? value : fallback; }
function element(tag, className, content) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (content !== undefined) node.textContent = content;
  return node;
}
function safeImagePath(value) {
  if (typeof value !== "string") return null;
  const path = value.replaceAll("\\", "/");
  if (!path || path.startsWith("/") || path.includes(":") || path.split("/").some(part => part === ".." || part === "." || !part)) return null;
  return path;
}
function imageURL(path) { return `../${path.split("/").map(encodeURIComponent).join("/")}`; }
function normalizeItems(raw) {
  if (!Array.isArray(raw?.items)) throw new Error("Missing items array");
  const seen = new Set();
  return raw.items.filter(item => item && typeof item.id === "string" && /^[a-zA-Z0-9_-]+$/.test(item.id) && !seen.has(item.id) && seen.add(item.id))
    .map(item => ({ id: item.id, title: text(item.title, "未命名造型"), description: text(item.description),
      image: safeImagePath(item.image || item.path), category: CATEGORY_ALIASES[text(item.category).trim()] || text(item.category).trim() || "daily",
      mood: text(item.mood), tags: Array.isArray(item.tags) ? item.tags.filter(x => typeof x === "string") : [],
      details: Array.isArray(item.details) ? item.details.filter(x => typeof x === "string") : [],
      moodLine: text(item.moodLine), scene: text(item.scene), status: text(item.status, "concept-review"), generationNote: text(item.generationNote),
      revision: text(item.sha256) || text(item.revision) || "",
      style: ["2D", "3D"].includes(item.style) ? item.style : "unknown",
      version: Number.isInteger(item.version) && item.version > 0 ? item.version : 1,
      changeNote: text(item.changeNote),
      previous: item.previous && safeImagePath(item.previous.image) ? {
        id: `${item.id}-previous`, image: safeImagePath(item.previous.image),
        title: text(item.previous.title, text(item.title)), revision: text(item.previous.sha256),
        status: text(item.previous.status, "concept-review"),
        style: ["2D", "3D"].includes(item.previous.style) ? item.previous.style : "unknown",
        version: Number.isInteger(item.previous.version) ? item.previous.version : Math.max(1, (item.version || 2) - 1),
        verdict: Object.hasOwn(VERDICTS, item.previous.verdict) ? item.previous.verdict : null,
        note: text(item.previous.note), reviewedAt: text(item.previous.reviewedAt),
      } : null, }));
}
function currentReview(item) {
  return latestReview(records, item.id, fingerprint(item)) || {};
}
function readReviews() {
  const read = key => { try { return JSON.parse(localStorage.getItem(key)); } catch { return null; } };
  records = migrateStorage(read(STORAGE_KEY), read(LEGACY_STORAGE_KEY));
}
function seedPreviousReviews() {
  const previous = items.filter(item => item.previous?.verdict || item.previous?.note).map(item => ({
    id: item.id, verdict: item.previous.verdict, note: item.previous.note,
    image: item.previous.image, fingerprint: fingerprint(item.previous), reviewedAt: item.previous.reviewedAt,
    imageAvailableAtReview: true,
  }));
  records = mergeRecords(records, previous);
}
function saveReviews() {
  try {
    localStorage.setItem(STORAGE_KEY, JSON.stringify({ schemaVersion: 2, records })); storageAvailable = true;
  }
  catch { storageAvailable = false; }
  $("#save-note").classList.toggle("error", !storageAvailable);
  $("#save-note").textContent = storageAvailable
    ? "喜好、修改選擇與註記會儲存在這個瀏覽器，也可以匯出留存。"
    : "這個瀏覽器無法儲存意見。離開前請按「匯出我的意見」，保留這次選擇。";
}
function record(item, update) {
  const previous = currentReview(item);
  const review = { id: item.id, verdict: previous.verdict || null, note: text(previous.note), ...update,
    image: item.image, fingerprint: fingerprint(item), imageAvailableAtReview: imageStates.get(item.id) === "ready", reviewedAt: new Date().toISOString() };
  // A typing session is one saved edit. Earlier decisions and other versions stay intact.
  if (Object.hasOwn(update, "note") && noteDraftRecord?.id === item.id && noteDraftRecord.fingerprint === review.fingerprint) {
    records = records.filter(value => value !== noteDraftRecord);
  }
  records.push(review);
  noteDraftRecord = Object.hasOwn(update, "note") ? review : null;
  saveReviews();
}
function categoryName(category) { return CATEGORY_NAMES[category] || category; }
function styleName(item) { return item.style === "unknown" ? "畫風待標示" : item.style === "2D" ? "2D 平面" : "3D 立體"; }
function versionName(item) { return `第 ${item.version} 版`; }
function visibleItems() {
  const query = $("#search").value.trim().toLocaleLowerCase(), mood = $("#mood").value, verdict = $("#verdict").value, style = $("#style").value;
  return items.filter(item => {
    const review = currentReview(item);
    return (!selectedCategory || item.category === selectedCategory)
      && (!mood || item.mood === mood)
      && (!style || item.style === style)
      && (!query || [item.title, item.description, item.mood, ...item.tags].join(" ").toLocaleLowerCase().includes(query))
      && (!verdict || (verdict === "pending" ? !review.verdict : review.verdict === verdict));
  });
}
function placeholder(item) {
  const wrap = element("span", "missing-image");
  const blocked = item.status === "generation-blocked";
  const revising = item.status === "revision-blocked";
  wrap.append(element("span", "missing-mark", "✳"), element("strong", "", revising ? "待重做 · 新圖還沒到" : blocked ? "本輪未生成 · 待補" : "圖片尚未到位"),
    element("small", "", revising ? "已收到你的意見。重畫尚未產生新圖，舊圖留在對照裡。" : blocked ? item.generationNote || "本輪未產生圖片，先保留服裝與表情方向。" : "先看看服裝與表情方向，圖片到位後可更新清單。"));
  return wrap;
}
function attachImage(container, item, { large = false } = {}) {
  const pending = placeholder(item); container.append(pending);
  if (!item.image || ["generation-blocked", "revision-blocked"].includes(item.status)) { imageStates.set(item.id, "pending"); return; }
  const image = element("img", "art-image");
  image.alt = `${item.title}：靜態造型候選`;
  image.loading = large ? "eager" : "lazy"; image.decoding = "async";
  image.classList.add("is-loading");
  image.addEventListener("load", () => { pending.remove(); image.classList.remove("is-loading"); imageStates.set(item.id, "ready"); }, { once: true });
  image.addEventListener("error", () => { image.remove(); imageStates.set(item.id, "pending"); }, { once: true });
  image.src = imageURL(item.image); container.append(image);
}
function makeVotes(item, onChange) {
  const wrap = element("div", "votes"); wrap.setAttribute("role", "group"); wrap.setAttribute("aria-label", `${item.title}的審稿選擇`);
  for (const [verdict, label] of Object.entries(VERDICTS)) {
    const button = element("button", "", label); button.type = "button";
    button.disabled = !item.image || ["generation-blocked", "revision-blocked"].includes(item.status);
    button.setAttribute("aria-pressed", String(currentReview(item).verdict === verdict));
    button.addEventListener("click", () => {
      record(item, { verdict: currentReview(item).verdict === verdict ? null : verdict });
      onChange();
    }); wrap.append(button);
  }
  return wrap;
}
function renderCategories() {
  const categories = ["", ...Object.keys(CATEGORY_NAMES), ...new Set(items.map(item => item.category).filter(category => !Object.hasOwn(CATEGORY_NAMES, category)))];
  $("#categories").replaceChildren();
  for (const category of categories) {
    const count = category ? items.filter(item => item.category === category).length : items.length;
    const button = element("button", "", category ? categoryName(category) : "全部"); button.type = "button";
    button.setAttribute("aria-pressed", String(category === selectedCategory)); button.append(element("span", "tab-count", String(count)));
    button.addEventListener("click", () => { selectedCategory = category; renderCategories(); renderGrid(); });
    $("#categories").append(button);
  }
}
function renderGrid() {
  const visible = visibleItems(), reviewed = items.filter(item => currentReview(item).verdict).length;
  const generated = items.filter(item => item.image && item.status === "concept-review").length;
  const revising = items.filter(item => item.status === "revision-blocked").length;
  $("#summary").textContent = `${items.length} 款造型方向 · ${generated} 張已生成`
    + (revising ? ` · ${revising} 款待重做` : "") + ` · ${items.length - generated - revising} 款待補`
    + (visible.length !== items.length ? ` · 目前 ${visible.length} 款` : "") + (reviewed ? ` · 已選 ${reviewed} 款` : "");
  $("#grid").replaceChildren();
  for (const item of visible) {
    const card = element("article", "card"), open = element("button", "card-open"); open.type = "button";
    open.setAttribute("aria-haspopup", "dialog"); open.setAttribute("aria-label", `放大看 ${item.title}`); open.dataset.itemId = item.id;
    const media = element("span", "card-media"); attachImage(media, item);
    media.append(element("span", "card-number", String(items.indexOf(item) + 1).padStart(2, "0")),
      element("span", "image-state", item.status === "revision-blocked" ? `擬議 ${styleName(item)} · 待重做`
        : item.status === "generation-blocked" ? `擬議 ${styleName(item)} · 待補` : `${styleName(item)} · ${versionName(item)}`));
    const copy = element("span", "card-text");
    copy.append(element("span", "card-meta", `${categoryName(item.category)}${item.mood ? ` / ${item.mood}` : ""}`), element("span", "card-title", item.title), element("span", "card-description", item.description));
    open.append(media, copy); open.addEventListener("click", () => openDetail(item.id));
    const bottom = element("div", "card-bottom"); bottom.append(makeVotes(item, renderGrid));
    const review = currentReview(item);
    bottom.append(element("p", "review-indicator", review.note ? "已寫下細節意見 · 點圖查看" : review.verdict ? "已記住這一版的選擇。"
      : item.status === "revision-blocked" ? "點開看重做方向與上一版意見" : item.previous ? "新版來了 · 點圖比較上一版" : "點圖，看大一點再決定。"));
    card.append(open, bottom); $("#grid").append(card);
  }
  $("#empty").hidden = visible.length > 0;
  $("#empty-message").textContent = items.length ? "換個分類或搜尋詞，看看其他樣子。" : "造型清單正在整理，稍後按「更新清單」再來看看。";
}
function openDetail(id) {
  selectedId = id; noteDraftRecord = null; renderDetail();
  if (!$("#detail").open) $("#detail").showModal();
  document.body.classList.add("modal-open");
}
function renderDetail() {
  const item = items.find(value => value.id === selectedId); if (!item) return;
  const review = currentReview(item), visible = visibleItems(), position = visible.findIndex(value => value.id === item.id);
  $("#detail-position").textContent = `${item.status === "revision-blocked" ? "擬議 " : ""}${styleName(item)} / ${versionName(item)}${item.status === "revision-blocked" ? " · 待重做" : ""}`;
  $("#detail-title").textContent = item.title;
  $("#detail-category").textContent = `${categoryName(item.category)}${item.mood ? ` / ${item.mood}` : ""}`;
  $("#detail-line").textContent = item.moodLine || MOOD_LINES[item.mood] || FALLBACK_LINES[item.category] || "「這也是我的一面。」";
  $("#detail-description").textContent = item.description;
  $("#detail-change").textContent = item.changeNote ? `這次調整：${item.changeNote}` : "";
  $("#detail-change").hidden = !item.changeNote || item.changeNote === item.description;
  $("#try-look").href = "../preview/?v=20260927-animation2";
  $("#try-look").hidden = item.id !== "bedtime-cel-v1";
  $("#detail-media").replaceChildren(); attachImage($("#detail-media"), item, { large: true });
  const details = item.details.length ? item.details : item.tags;
  $("#detail-tags").replaceChildren(...(details.length ? details : ["細節待你確認"]).map(tag => element("li", "", tag)));
  $("#detail-votes").replaceChildren(...makeVotes(item, () => { renderGrid(); renderDetail(); }).children);
  $("#detail-note").value = text(review.note);
  $("#detail-review-note").textContent = !item.image || ["generation-blocked", "revision-blocked"].includes(item.status)
    ? "新圖還沒到，可以先留下想法；有圖後再選喜歡或不喜歡。"
    : !review.verdict && item.previous ? "這是新版，可以重新選；上一版的意見留在下方。" : "選擇與註記會自動儲存在這個瀏覽器。";
  renderComparison(item); renderHistory(item);
  $("#previous").disabled = position <= 0; $("#next").disabled = position < 0 || position >= visible.length - 1;
}
function reviewDate(value) {
  const timestamp = Date.parse(value);
  return Number.isFinite(timestamp) ? new Date(timestamp).toLocaleString("zh-TW", { hour12: false }) : "時間未提供";
}
function renderComparison(item) {
  const container = $("#comparison-grid"); container.replaceChildren();
  $("#version-comparison").hidden = !item.previous;
  if (!item.previous) return;
  for (const [version, label] of [[item.previous, "上一版"], [item, "這一版"]]) {
    const figure = element("figure", "version-figure"), media = element("div", "version-media");
    attachImage(media, version, { large: true });
    const review = latestReview(records, item.id, fingerprint(version));
    const caption = element("figcaption");
    caption.append(element("strong", "", `${label} · ${versionName(version)}`),
      element("p", "", version.title),
      element("p", "version-verdict", review?.verdict ? `你的選擇：${VERDICTS[review.verdict]}` : "還沒選擇"));
    if (review?.note) caption.append(element("p", "", review.note));
    if (review?.reviewedAt) caption.append(element("time", "", reviewDate(review.reviewedAt)));
    figure.append(media, caption); container.append(figure);
  }
}
function renderHistory(item) {
  const history = records.filter(record => record.id === item.id).sort((a, b) => (Date.parse(b.reviewedAt) || 0) - (Date.parse(a.reviewedAt) || 0));
  $("#review-history").hidden = !history.length;
  $("#history-list").replaceChildren();
  for (const record of history) {
    const label = record.fingerprint === fingerprint(item) ? `這一版 · ${versionName(item)}`
      : item.previous && record.fingerprint === fingerprint(item.previous) ? `上一版 · ${versionName(item.previous)}` : "較早版本";
    const row = element("li");
    row.append(element("strong", "", `${label}：${VERDICTS[record.verdict] || "只留註記／取消選擇"}`),
      element("time", "", reviewDate(record.reviewedAt)));
    if (record.note) row.append(element("p", "", record.note));
    $("#history-list").append(row);
  }
}
async function loadManifest() {
  const sequence = ++loadSequence; $("#reload").disabled = true;
  try {
    const response = await fetch(MANIFEST, { cache: "no-store" });
    if (!response.ok) throw new Error(`Manifest ${response.status}`);
    const loaded = normalizeItems(await response.json()); if (sequence !== loadSequence) return;
    items = loaded; imageStates.clear(); seedPreviousReviews(); saveReviews();
    const currentMood = $("#mood").value;
    $("#mood").replaceChildren(new Option("所有情緒", ""));
    for (const mood of [...new Set(items.map(item => item.mood).filter(Boolean))]) $("#mood").add(new Option(mood, mood));
    $("#mood").value = [...$("#mood").options].some(option => option.value === currentMood) ? currentMood : "";
    if (selectedCategory && !items.some(item => item.category === selectedCategory)) selectedCategory = "";
    renderCategories(); renderGrid();
    if ($("#detail").open) {
      if (items.some(item => item.id === selectedId)) renderDetail(); else $("#detail").close();
    }
  } catch {
    if (sequence !== loadSequence) return;
    if (!items.length) { renderCategories(); renderGrid(); $("#empty-message").textContent = "造型清單暫時無法讀取。請使用本機預覽網址開啟，或稍後按「更新清單」。"; }
    $("#summary").textContent = items.length ? "清單更新失敗，先保留目前的造型和意見。" : "造型清單待更新，尚未讀取到款式。";
  } finally { if (sequence === loadSequence) $("#reload").disabled = false; }
}

readReviews();
$("#reload").addEventListener("click", loadManifest);
$("#search").addEventListener("input", renderGrid);
for (const id of ["mood", "verdict", "style"]) $("#" + id).addEventListener("change", renderGrid);
$("#close-detail").addEventListener("click", () => $("#detail").close());
$("#detail").addEventListener("close", () => {
  document.body.classList.remove("modal-open"); renderGrid();
  const opener = [...document.querySelectorAll(".card-open")].find(button => button.dataset.itemId === selectedId);
  (opener || $("#verdict")).focus({ preventScroll: true });
});
$("#detail").addEventListener("click", event => {
  if (event.target !== $("#detail")) return;
  const box = $("#detail").getBoundingClientRect();
  if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) $("#detail").close();
});
for (const [id, step] of [["previous", -1], ["next", 1]]) $("#" + id).addEventListener("click", () => {
  const visible = visibleItems(), position = visible.findIndex(item => item.id === selectedId);
  if (visible[position + step]) { selectedId = visible[position + step].id; noteDraftRecord = null; renderDetail(); $("#detail").scrollTop = 0; }
});
$("#detail-note").addEventListener("input", event => {
  const item = items.find(value => value.id === selectedId);
  if (item) { record(item, { note: event.target.value }); renderHistory(item); renderComparison(item); }
});
$("#import").addEventListener("click", () => $("#import-file").click());
$("#import-file").addEventListener("change", async event => {
  const file = event.target.files?.[0]; if (!file) return;
  const message = $("#import-note"); message.hidden = false; message.classList.remove("error");
  try {
    if (file.size > 5 * 1024 * 1024) throw new Error("請選擇5MB以內的衣櫥意見檔。");
    const payload = JSON.parse(await file.text());
    const result = importReviews(payload, items, records);
    records = result.records; noteDraftRecord = null; saveReviews(); renderGrid();
    if ($("#detail").open) renderDetail();
    const { current, previous, skipped, older, duplicates } = result.counts;
    message.textContent = `已匯入 ${current + previous} 則意見${previous ? `（${previous} 則是上一版）` : ""}。`
      + (older ? ` ${older} 則較早意見保留在記錄裡，較新的選擇照舊。` : "")
      + (duplicates ? ` ${duplicates} 則已有記錄。` : "")
      + (skipped ? ` ${skipped} 則款式或圖片版本不相符，未套用。` : "")
      + (previous ? " 新版仍可重新選擇。" : "");
  } catch (error) {
    message.classList.add("error");
    message.textContent = error instanceof SyntaxError ? "這份檔案不是有效的 JSON，原來的意見仍保留。" : error.message;
  } finally { event.target.value = ""; }
});
$("#export").addEventListener("click", () => {
  const payload = exportReviews(items, records);
  const url = URL.createObjectURL(new Blob([JSON.stringify(payload, null, 2)], { type: "application/json" }));
  const anchor = element("a"); anchor.href = url; anchor.download = "patrick-wardrobe-review.json"; anchor.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
await loadManifest();
