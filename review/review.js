const KEY = "patrick.asset-review.v1";
const PAGE_SIZE = 24;
const $ = selector => document.querySelector(selector);
let reviews = {};
try { const saved = JSON.parse(localStorage.getItem(KEY)); if (saved && typeof saved === "object" && !Array.isArray(saved)) reviews = saved; } catch { /* Fresh local review. */ }
let items = [], page = 0;
const states = { liked: "喜歡", revise: "要修改", rejected: "不喜歡" };
const categoryNames = {
  "retired-style-research": "退役風格研究", "retired-animation-runtime": "退役角色素材", "eye-color-error-evidence": "眼部錯色舊稿", "animation-keyframe-rough": "新動畫關鍵畫稿",
  "new-scene-concept": "新生活情境概念", "comparison-candidate": "畫風比較候選", "historical-backup": "歷史備份",
  "historical-rejected-runtime": "已退役來源", "legacy-source-reference": "舊版來源參考", "motion-effect-placeholder": "動作特效草稿",
  "qa-screenshot": "驗收截圖", "qr-build-artifact": "QR 圖片", "qr-payload": "QR 連結記錄", "reference": "原始參考",
  "retired-runtime-copy": "已清理的舊素材", "retired-runtime-metadata": "已清理的舊設定", "runtime-or-preview": "現用角色與預覽",
  "source-or-superseded-art": "來源與舊稿", "style-library-accessories": "配件", "style-library-arms": "手臂", "style-library-body": "身體",
  "style-library-clothing": "服裝", "style-library-eyes-lids-brows": "眼睛與眉毛", "style-library-feet": "腳", "style-library-mouths": "嘴巴",
  "style-library-overlays": "疊加效果", "style-preview": "組合造型預覽", "theme-contact-sheets": "交付總覽", "theme-qr": "QR 入口",
  "theme-shortcuts-icons": "捷徑圖示", "theme-sounds": "音效", "theme-source-layers": "交付角色分層", "theme-wallpapers": "桌布候選",
  "theme-watch": "手錶構圖", "theme-widgets": "小工具構圖",
};
function save() {
  try { localStorage.setItem(KEY, JSON.stringify(reviews)); }
  catch { $(".notice").textContent = "瀏覽器無法儲存意見。請在離開前按『匯出我的意見』保留本次內容。"; }
}
function entry(tag, cls, text) { const node = document.createElement(tag); if (cls) node.className = cls; if (text) node.textContent = text; return node; }
function receivedReview(item) {
  const verdict = item.userVerdict || (item.status === "rejected" ? "rejected" : null);
  const fingerprint = typeof item.reviewFingerprint === "string" ? item.reviewFingerprint.split("|") : [];
  // Received feedback applies only to the exact file version that was reviewed.
  if (!states[verdict] || !item.feedbackVersionVerified || !/^[a-f0-9]{64}$/i.test(item.sha256 || "") ||
      fingerprint.length !== 3 || fingerprint[0] !== item.path || fingerprint[1] !== item.sha256) return {};
  return { verdict, note: typeof item.userNote === "string" ? item.userNote : "", sha256: item.sha256,
    reviewedAt: item.reviewedAt, reviewFingerprint: item.reviewFingerprint, feedbackSource: item.feedbackSource,
    feedbackExportedAt: item.feedbackExportedAt, reviewSource: "received-feedback" };
}
function getReview(item) {
  const saved = reviews[item.path];
  const local = saved && typeof saved === "object" && !Array.isArray(saved) ? saved : {};
  // An explicit local null means the user cleared a choice; do not restore it.
  return Object.hasOwn(local, "verdict") ? local : { ...receivedReview(item), ...local };
}
function isRejectedVersion(item) { return item.status === "rejected" || receivedReview(item).verdict === "rejected"; }
function exportReviews() {
  const result = { ...reviews };
  for (const item of items) {
    const review = getReview(item);
    if (Object.keys(review).length) result[item.path] = review;
  }
  return result;
}
function visibleItems() {
  const query = $("#search").value.trim().toLowerCase(), category = $("#category").value, filter = $("#filter").value;
  return items.filter(item => {
    if (query && !item.path.toLowerCase().includes(query)) return false;
    if (category && item.category !== category) return false;
    if (filter === "all") return true;
    if (filter === "removed") return ["removed", "replaced"].includes(item.status);
    const vote = getReview(item).verdict;
    if (filter === "pending") return !isRejectedVersion(item) && ["pending-review", "replaced"].includes(item.status) && !vote;
    return vote === filter;
  });
}
function render() {
  const filtered = visibleItems();
  const maxPage = Math.max(0, Math.ceil(filtered.length / PAGE_SIZE) - 1); page = Math.min(page, maxPage);
  $("#summary").textContent = `這裡有 ${filtered.length} 個素材 · 已留下 ${items.filter(item => getReview(item).verdict).length} 筆選擇`;
  $("#grid").replaceChildren();
  for (const item of filtered.slice(page * PAGE_SIZE, (page + 1) * PAGE_SIZE)) {
    const review = getReview(item);
    const card = entry("article", "card"), media = entry("div", "media");
    const safePath = !item.path.includes("..") && !item.path.startsWith("/") && !item.path.includes(":");
    const src = `../${item.path.split("/").map(encodeURIComponent).join("/")}`;
    if (item.exists && safePath) {
      const ext = item.path.split(".").pop().toLowerCase();
      const tag = ["wav", "m4a"].includes(ext) ? "audio" : ext === "mp4" ? "video" : "img";
      const resource = entry(tag);
      resource.src = src;
      if (tag === "img") { resource.alt = item.path.split("/").pop(); resource.loading = "lazy"; }
      else { resource.controls = true; resource.preload = "none"; }
      resource.addEventListener("error", () => media.replaceChildren(entry("span", "missing", "這個檔案無法預覽，請查看盤點紀錄。")));
      media.append(resource);
    } else media.append(entry("span", "missing", "已從使用中的資料夾移除；備份與理由保存在清理紀錄。"));
    card.append(media, entry("p", "path", item.path));
    card.append(entry("span", "badge", item.status === "removed" ? "已清理" : isRejectedVersion(item) ?
      (review.verdict === "rejected" ? "已標記不喜歡 · 舊版留作對照" : "舊版留作對照") :
      item.status === "replaced" ? "已更新版本 · 待你確認" : item.status === "retained" ? "參考／歷史" : "待你確認"));
    const issues = item.technicalIssues?.length ? "有技術備註，詳見盤點" : "技術狀態和審美分開";
    card.append(entry("p", "meta", `${item.width ? `${item.width} × ${item.height} · ` : ""}${issues}`));
    if (item.status === "removed") {
      card.append(entry("p", "meta", item.reason));
    } else {
      const votes = entry("div", "votes");
      for (const [verdict, label] of Object.entries(states)) {
        const button = entry("button", review.verdict === verdict ? "selected" : "", label);
        button.setAttribute("aria-label", `${label}：${item.path}`);
        button.addEventListener("click", () => {
          const current = getReview(item);
          reviews[item.path] = { ...current, verdict: current.verdict === verdict ? null : verdict,
            sha256: item.sha256, reviewedAt: new Date().toISOString(), reviewSource: "browser" };
          save(); render();
        }); votes.append(button);
      }
      const note = entry("textarea"); note.placeholder = "哪裡喜歡，或想怎麼改？"; note.setAttribute("aria-label", `意見：${item.path}`);
      note.value = typeof review.note === "string" ? review.note : "";
      note.addEventListener("change", () => { reviews[item.path] = { ...getReview(item), note: note.value, sha256: item.sha256, reviewedAt: new Date().toISOString(), reviewSource: "browser" }; save(); });
      card.append(votes, note);
    }
    $("#grid").append(card);
  }
  if (!filtered.length) $("#grid").append(entry("p", "detail", "這個條件下暫時沒有素材。"));
  $("#page").textContent = `${page + 1} / ${maxPage + 1}`;
  $("#previous").disabled = page === 0; $("#next").disabled = page >= maxPage;
}
for (const id of ["search", "category", "filter"]) $("#" + id).addEventListener(id === "search" ? "input" : "change", () => { page = 0; render(); });
$("#previous").addEventListener("click", () => { page--; render(); });
$("#next").addEventListener("click", () => { page++; render(); });
$("#export").addEventListener("click", () => {
  const blob = new Blob([JSON.stringify({ schemaVersion: 1, exportedAt: new Date().toISOString(), scope: "individual assets only", reviews: exportReviews() }, null, 2)], { type: "application/json" });
  const url = URL.createObjectURL(blob), a = entry("a"); a.href = url; a.download = "patrick-my-asset-review.json"; a.click(); setTimeout(() => URL.revokeObjectURL(url), 1000);
});
try {
  const response = await fetch("../docs/asset-audit.json", { cache: "no-store" });
  if (!response.ok) throw new Error(String(response.status));
  const report = await response.json();
  items = report.items.filter(item => typeof item.path === "string").sort((a, b) =>
    Number(b.category === "new-scene-concept") - Number(a.category === "new-scene-concept") || a.path.localeCompare(b.path));
  // Approval belongs to the bytes reviewed, not just to a reused filename.
  for (const item of items) {
    if (reviews[item.path]?.sha256 && reviews[item.path].sha256 !== item.sha256) {
      reviews[item.path] = { ...reviews[item.path], previousVerdict: reviews[item.path].verdict,
        verdict: null, note: `${reviews[item.path].note || ""}\n素材已更新，請重新確認。`.trim(), sha256: item.sha256 };
    }
  }
  save();
  for (const category of [...new Set(items.map(item => item.category))].sort()) $("#category").add(new Option(categoryNames[category] || category, category));
  render();
} catch { $("#summary").textContent = "盤點檔無法載入。請透過本機預覽網址開啟，或先重新產生素材盤點。"; }
