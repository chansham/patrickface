// Recipe preview only. This page does not run Shortcuts or access devices.
const $ = selector => document.querySelector(selector);
const node = (tag,text,className='') => {const e=document.createElement(tag);e.textContent=text;e.className=className;return e;};
let data, group='全部', downloadURL;
const optionalSteps=()=>[
  $('#night-brightness').checked ? '設定 iPhone 螢幕亮度為 20%' : null,
  $('#night-volume').checked ? '設定 iPhone 媒體音量為 0%（不要選鬧鐘／計時器音量）' : null,
  $('#night-home').checked ? '控制家庭：執行你已建立並測試的 Home「晚安」場景' : null
].filter(Boolean);
function recipe() {
  const steps=[
    '開始晚安流程紀錄：保存回傳的流程編號，後續都傳同一個編號（需包含2026-10-13新入口的App；尚待Apple編譯安裝）。',
    '設定專注模式：選「睡眠」，明確開啟；不要用切換。其後「回報晚安步驟結果」選睡眠專注、已完成、執行次數1。',
    '本配方不改鬧鐘：「回報晚安步驟結果」選指定鬧鐘、未選用、執行次數1。若日後明確選了既有鬧鐘，另在啟用後回報；不反覆新建。',
    '執行晚安中的派大星步驟：傳入流程編號和執行次數1，由App套用睡前狀態並記錄本機結果。',
    $('#night-home').checked ? '執行已選的Home晚安場景；其後「回報晚安步驟結果」選晚安燈光、已完成、執行次數1。' : '回報晚安步驟結果：晚安燈光、未選用、執行次數1。',
    ...optionalSteps().filter(s=>!s.startsWith('控制家庭')),
    '讀取晚安流程結果：傳入流程編號，將回傳文字交給「顯示結果」。也可在App「流程」查看。'
  ];
  return ['派大星晚安｜iPhone 組合捷徑設定步驟','這是文字配方，不是可匯入的 .shortcut 檔；尚未替你設定或執行。','',
    '一次準備：先設定睡眠專注、允許的通知與來電；同帳號開啟專注模式「在裝置間共享」。手錶配對／Focus跟隨與捷徑相容性另測。',
    '在捷徑 App 建立捷徑，命名「派大星晚安」，依序加入：',...steps.map((s,i)=>`${i+1}. ${s}`),'',
    '想依情境換睡衣，先把派大星衣服設為自動；固定服裝、App音效偏好與原計時不會被覆寫。',
    '系統睡眠專注和派大星睡前是不同步驟。捷徑遇錯可能在該步停止；不應回報全部成功。手機完成不等於手錶已確認同步。',
    '中途停止而沒有回報的步驟保持「尚無回報」，不自動判失敗或重做。若明確知道某步失敗，可回報「未完成」，再用「準備重試晚安失敗步驟」取得新次數；只執行那一步，並帶新次數回報。',
    '四步紀錄目前只涵蓋專注、指定鬧鐘、派大星和Home；額外亮度／媒體音量仍不在逐步紀錄內，不能用四步完整代替全部选配的確認。',
    '原有鬧鐘與睡眠排程不變；若需要新的叫醒時間，另行明確設定並核對。亮度／音量沒有自動安全還原。',
    '日常：喚起 Siri 說「派大星晚安」；也可把同一捷徑綁背面輕點、控制中心或手機 NFC。',
    '只想直接說「晚安」：另在 iPhone 輔助使用設定語音捷徑，訓練短句；這不是 Watch 無喚醒詞功能。','',
    '早安配方：取得目前專注模式 → 只有目前是睡眠才關閉 → 套用派大星生活流程「早安」。',
    '早安使派大星保持清醒覆寫直到你下次設定；想回原時間表，另選「恢復原作息」。不停止所有鬧鐘、不修改工作／駕駛專注。','',
    '官方依據：https://support.apple.com/guide/iphone/turn-sleep-focus-on-or-off-iph7cdb86325/ios',
    '手錶相容性：https://support.apple.com/guide/watch/shortcuts-apd99050d435/watchos'].join('\n');
}
function updateRecipe() {
  if(downloadURL) URL.revokeObjectURL(downloadURL); downloadURL=URL.createObjectURL(new Blob([recipe()],{type:'text/plain;charset=utf-8'})); $('#download-night').href=downloadURL;
  $('#copy-result').textContent=''; $('#night-result-summary').textContent='配方已更新；點「查看模擬結果」重新預覽。'; $('#night-result-steps').replaceChildren();
}
for(const id of ['#night-brightness','#night-volume','#night-home']) $(id).addEventListener('change',updateRecipe);
$('#copy-night').addEventListener('click',async()=>{try{await navigator.clipboard.writeText(recipe());$('#copy-result').textContent='已複製文字步驟；尚未安裝或執行捷徑。';}catch{$('#copy-result').textContent='無法寫入剪貼簿，請使用「下載步驟」。';}});
$('#night-scenario').addEventListener('change',()=>{$('#night-result-steps').replaceChildren();$('#night-result-summary').textContent='情況已更換；點「查看模擬結果」查看。';});
$('#preview-night').addEventListener('click',()=>{
  const scenario=$('#night-scenario').value,optional=optionalSteps(),list=$('#night-result-steps');list.replaceChildren();
  if(scenario==='optional-failed'&&!optional.length){$('#night-result-summary').textContent='請先勾選一個選配，才能預覽選配失敗。';return;}
  const steps=['iPhone：開啟睡眠專注','派大星：儲存晚安設定，嘗試傳給配對手錶',...optional];
  const failAt=scenario==='focus-failed'?0:scenario==='app-failed'?1:scenario==='optional-failed'?2:-1;
  steps.forEach((text,i)=>{const state=failAt<0||i<failAt?'done':i===failAt?'failed':'skipped';list.append(node('li',`${i+1}. ${text}\n模擬：${state==='done'?'這一步已完成':state==='failed'?'這一步失敗':'尚未執行'}`,state));});
  const summary=scenario==='focus-failed'?'模擬：睡眠專注未設定成功，沒有繼續後面的流程。'
    :scenario==='app-failed'?'模擬：手機睡眠專注已開，派大星這一步失敗；不能說全部準備好了。'
    :scenario==='optional-failed'?'模擬：專注與派大星本機設定已完成；選配失敗，後面的動作尚未執行。'
    :scenario==='watch-offline'?'模擬：手機端已完成；手錶暫時離線，不能宣稱錶上已切換。'
    :'模擬：手機端已完成。手錶的 Focus 和派大星狀態仍需各自確認。';
  $('#night-result-summary').textContent=summary;list.append(node('li','實機驗收：手機捷徑成功、Focus跨裝置跟隨、派大星狀態同步，分開確認。','pending'));
});
updateRecipe();
function show() {
  const query=$('#routine-search').value.trim().toLocaleLowerCase();
  const items=data.items.filter(i=>(group==='全部'||i.group===group)&&[i.title,i.phrase,i.trigger,i.benefit,...i.steps.map(s=>s.action)].join(' ').toLocaleLowerCase().includes(query));
  $('#routine-grid').replaceChildren();$('#routine-empty').hidden=items.length!==0;$('#routine-count').textContent=`${items.length} / ${data.items.length} 套流程 · 完整捷徑待手機設定`;
  for(const item of items) {
    const card=node('article','','routine-card');card.id=`routine-${item.id}`;card.append(node('span',`「${item.phrase}」`,'phrase'),node('h3',item.title),node('p',item.benefit,'benefit'),node('p',`入口：${item.trigger}`,'trigger'));
    const ol=document.createElement('ol');for(const step of item.steps){const li=node('li',step.action);li.append(node('span',`${step.owner} · ${step.state}`));ol.append(li);}card.append(ol,node('p',`造型與動作構想：${item.art}`,'art'));
    const details=document.createElement('details');details.append(node('summary','失敗時怎麼辦、要先設定什麼'),node('p',`退路：${item.fallback}`),node('p',item.limits));
    const links=node('div','','sources');for(const source of item.sources){const a=node('a',source.title);a.href=source.url;links.append(a);}details.append(links);card.append(details);$('#routine-grid').append(card);
  }
  for(const button of $('#routine-filters').children)button.setAttribute('aria-pressed',String(button.textContent===group));
}
try {
  const response=await fetch('./routines.json?v=20261013-1');if(!response.ok)throw new Error('routines unavailable');data=await response.json();
  for(const name of ['全部',...new Set(data.items.map(i=>i.group))]){const b=node('button',name);b.addEventListener('click',()=>{group=name;show();});$('#routine-filters').append(b);}
  $('#routine-search').addEventListener('input',show);show();document.documentElement.dataset.routines='ready';
}catch{$('#routine-count').textContent='流程清單未能載入，請重新整理。';document.documentElement.dataset.routines='error';}
