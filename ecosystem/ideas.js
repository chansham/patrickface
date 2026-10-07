// A browsable design inventory. No device access, persistence, or health inference.
const $ = selector => document.querySelector(selector);
let data, selected = '全部';
const node = (tag, text, className = '') => { const element = document.createElement(tag); element.textContent = text; element.className = className; return element; };
function show() {
  const query = $('#ideas-search').value.trim().toLocaleLowerCase();
  const items = data.items.filter(item => (selected === '全部' || item.group === selected || item.priority === selected)
    && [item.title,item.combines,item.experience,item.art,item.route].join(' ').toLocaleLowerCase().includes(query));
  $('#ideas-count').textContent = `${items.length} / ${data.items.length} 個組合提案 · 尚未接入實機`;
  $('#ideas-grid').replaceChildren(); $('#no-results').hidden = items.length !== 0;
  for (const item of items) {
    const article = document.createElement('article'); article.className = 'idea'; article.id = item.id;
    article.append(node('span', `${item.group} · ${item.priority}`, 'label'),node('h3',item.title),node('p',item.combines,'combines'),node('p',item.experience,'experience'),node('p',`造型與動作構想：${item.art}`,'art'));
    const details = document.createElement('details'); details.append(node('summary','看接法、限制與官方依據'));
    const dl = document.createElement('dl');
    for (const [title,text] of [['Apple 已有',item.apple],['怎樣接起來',item.route],['資料不足與使用界線',item.limits]]) dl.append(node('dt',title),node('dd',text));
    details.append(dl,node('p',item.status,'state'));
    const links = node('div','','sources');
    for (const key of item.sources) { const source = data.sources[key], a = node('a',source.title); a.href = source.url; links.append(a); }
    details.append(links); article.append(details); $('#ideas-grid').append(article);
  }
  for (const button of $('#filters').children) button.setAttribute('aria-pressed',String(button.textContent === selected));
}
function revealHash() {
  const id = location.hash.slice(1); if (!data.items.some(item => item.id === id)) return;
  selected = '全部'; $('#ideas-search').value = ''; show(); $('#signal-ideas')?.setAttribute('open',''); document.getElementById(id).scrollIntoView();
}
try {
  const response = await fetch('./ideas.json?v=20261007-1'); if (!response.ok) throw new Error(`資料無法載入 (${response.status})`);
  data = await response.json();
  for (const name of ['全部','先做手動版',...new Set(data.items.map(item => item.group))]) {
    const b = node('button',name); b.type = 'button'; b.addEventListener('click',()=>{selected=name;show();}); $('#filters').append(b);
  }
  $('#ideas-search').addEventListener('input',show); window.addEventListener('hashchange',revealHash);
  $('.starting').addEventListener('click',event=>{
    const link = event.target.closest('a[href^="#"]'); if(!link) return;
    event.preventDefault(); history.replaceState(null,'',link.getAttribute('href')); revealHash();
  });
  show(); if(location.hash) revealHash();
  document.documentElement.dataset.ideas = 'ready';
} catch(error) { $('#ideas-count').textContent = '提案資料未能載入，重新整理可重試。'; document.documentElement.dataset.ideas = 'error'; }
