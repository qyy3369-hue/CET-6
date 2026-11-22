import { createWorkspace } from './workspace.js';
import { addIcon } from './icons.js';
import { installButtonMotion } from './button-motion.js';
import { showVocabularyImport } from './vocabulary-import.js';
import { createFlashcardMnemonics } from './flashcard-mnemonic.js';
import { createWordTree } from './word-tree.js';

const [config, starter] = await Promise.all([
  fetch('./GoalsCloud.json').then(response => response.json()).catch(() => ({})),
  fetch('./starter-words.json').then(response => response.json()).catch(() => []),
]);

const content = document.querySelector('#content');
const notice = document.querySelector('#notice');
const title = document.querySelector('#title');
const header = document.querySelector('#header-actions');
const crumb = document.querySelector('#crumb');
const sidebar = document.querySelector('#sidebar-toggle');
const quickSearch = document.querySelector('#quick-search');
const query = document.querySelector('#quick-query');
const quickResults = document.querySelector('#quick-results');
document.querySelectorAll('[data-icon]').forEach(item => addIcon(item,item.dataset.icon));
installButtonMotion();
const pages = { goals: '目标总览', today: '今日日程', plans: '计划书', words: '单词本',
  cards: '闪卡复习', tree: '词树', favorites: '错词收藏', translation: '翻译训练', writing: '写作训练',
  roots: '词根词缀', friends: '好友与排行', settings: '设置' };
const workspace = createWorkspace({node, field, group, panel, button, form, run, rpc, ai, content, header, notice, render});
const wordTree = createWordTree({node, field, group, panel, button, content});
const starterIDs = new Set(starter.map(word => word.id));
const reviewModes = [['due','到期优先'],['all','全部'],['favorites','收藏'],['hard','高难']];
let reviewMode = 'due';
let reviewLibrary = null;
let settingsMode = 'general';
let wordFilter = '';
let wordOrder = [];
let addWordDraft = '';
let wordBookFeedback = '';
let expandedWords = new Set();
let cardMessage = '';
let lastSpoken = null;
const mnemonics = createFlashcardMnemonics({
  rpc,ai,node,button,
  enabled:()=>workspace.aiConfigured(),
  owner:()=>session?.user?.id,
  levelFor:word=>get(word.id,'progress')?.level ?? 0,
  meaningFor:word=>hasMeaning(word) ? word.meaning : '',
});
let speech = { auto: false, accent: 'en-US', rate: 0.9, ...readLocal('goals.speech') };
const mobile = matchMedia('(max-width: 680px)');
const defaults = { skip: 's', unknown: 'u', favorite: 'f' };
const shortcuts = { ...defaults, ...readLocal('goals.shortcuts') };
const authKey = 'goals.auth';
let session = readLocal(authKey);
let entries = new Map();
let social;
let editingNickname = false;
let detail;
let activeId;
let revealed = false;
let correction = false;
let cardStartedAt = null;
let busy = false;
let ready = false;
let queueIndex = 0;
let refreshInFlight;
let renderedPage;

function readLocal(key) {
  try { return JSON.parse(localStorage.getItem(key)); } catch { return null; }
}

function node(tag, value, className) {
  const element = document.createElement(tag);
  if (value != null) element.textContent = value;
  if (className) element.className = className;
  return element;
}

function button(label, handler, style) {
  const element = node('button', label, style);
  element.type = 'button';
  element.addEventListener('click', handler);
  return element;
}

function group(className, ...children) {
  const element = node('div', null, className);
  element.append(...children);
  return element;
}

function panel(heading, ...children) {
  return group('panel stack', ...(heading ? [node('h2', heading)] : []), ...children);
}

function field(label, options = {}) {
  const input = Object.assign(node('input'), options);
  const wrapper = node('label', label);
  wrapper.append(input);
  return [wrapper, input];
}

function form(elements, label, submit) {
  const element = node('form', null, 'stack');
  const action = node('button', label, 'primary');
  element.append(...elements, group('controls', action));
  element.addEventListener('submit', event => {
    event.preventDefault();
    run(submit, action);
  });
  return element;
}

function page() {
  const value = location.hash.slice(1);
  return Object.hasOwn(pages, value) ? value : 'goals';
}

async function request(path, body, token) {
  const response = await fetch(config.url.replace(/\/$/, '') + path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', apikey: config.publishableKey,
      ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: JSON.stringify(body),
  });
  const value = await response.json();
  if (!response.ok) {
    const error = new Error(value.message ?? value.msg ?? value.error_description ?? '请求失败');
    error.status = response.status;
    throw error;
  }
  return value;
}

function setSession(value) {
  session = value?.access_token ? { ...value, expires_at: value.expires_at ?? Date.now() / 1000 + value.expires_in } : null;
  if (session) localStorage.setItem(authKey, JSON.stringify(session));
  else localStorage.removeItem(authKey);
}

async function token(force = false) {
  if (!session) throw new Error('请先登录 Goals');
  if (!force && session.expires_at > Date.now() / 1000 + 45) return session.access_token;
  refreshInFlight ??= request('/auth/v1/token?grant_type=refresh_token', { refresh_token: session.refresh_token })
    .then(setSession)
    .finally(() => { refreshInFlight = undefined; });
  await refreshInFlight;
  return session.access_token;
}

function rpc(name, body) {
  return authorizedRequest('/rest/v1/rpc/goals_' + name, body);
}

function ai(action, input, options = {}) {
  return authorizedRequest('/functions/v1/goals-deepseek', { action, input, ...options });
}

async function authorizedRequest(path, body) {
  const access = await token();
  try { return await request(path, body, access); }
  catch (error) {
    if (error.status !== 401) throw error;
    return request(path, body, await token(true));
  }
}

const keyFor = (id, kind) => id + '\u0000' + kind;
const get = (id, kind) => entries.get(keyFor(id, kind))?.value;
function syncedWords() {
  const positions = new Map(wordOrder.map((id,index)=>[id,index]));
  return [...entries.values()].filter(row=>row.kind==='word' && row.value).map(row=>row.value)
    .sort((a,b)=>(positions.get(a.id) ?? Infinity)-(positions.get(b.id) ?? Infinity));
}

async function refreshWordOrder(ids = []) {
  try { wordOrder = await rpc('word_order',{word_ids:ids}); }
  catch {
    if (ids.length) wordOrder = [...new Set([...ids,...wordOrder])];
  }
}

function words() {
  const mine = syncedWords();
  const owned = new Set(mine.map(word => word.word.toLowerCase()));
  return [...mine, ...starter.filter(word => !owned.has(word.word.toLowerCase()) && !entries.has(keyFor(word.id, 'word')))];
}
function studyWords() {
  const mine = syncedWords();
  const source = reviewLibrary ?? (mine.some(word => !starterIDs.has(word.id)) ? 'mine' : 'all');
  return source === 'mine' ? mine : words();
}

const dueWords = () => studyWords().filter(word => !get(word.id, 'dismissed') && (get(word.id, 'progress')?.nextReview ?? 0) <= Date.now() / 1000);
const write = (id, kind, value) => ({ word_id: id, kind, value, revision: entries.get(keyFor(id, kind))?.revision ?? 0 });

async function sync(changes = [], events = []) {
  const rows = await rpc('sync', { changes, events });
  const added = changes.filter(row=>row.kind==='word' && row.value && !get(row.word_id,'word'))
    .map(row=>row.word_id);
  entries = new Map(rows.map(row => [keyFor(row.word_id, row.kind), row]));
  await refreshWordOrder(added);
  ready = true;
  if (changes.some(row => JSON.stringify(canonical(get(row.word_id, row.kind))) !== JSON.stringify(canonical(row.value)))) {
    notice.textContent = '这条记录刚在另一端更新，已载入云端记录。';
  }
}

function canonical(value) {
  if (Array.isArray(value)) return value.map(canonical);
  if (value && typeof value === 'object') return Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])]));
  return value;
}

async function run(handler, control) {
  if (busy) return;
  busy = true;
  if (control) control.disabled = true;
  notice.textContent = '';
  try { await handler(); render(); }
  catch (error) {
    notice.textContent = error instanceof TypeError ? '连接失败，请检查网络后重试。' : error.message;
  } finally {
    busy = false;
    if (control) control.disabled = false;
  }
}

function render() {
  const current = page();
  const registering = !session && location.hash === '#register';
  title.textContent = !session ? (registering ? '创建 Goals 账号' : '登录 Goals') : pages[current];
  crumb.textContent = title.textContent;
  document.body.classList.toggle('auth-view', !session);
  header.replaceChildren();
  for (const link of document.querySelectorAll('.sidebar a:not(.brand)')) {
    if (link.hash === '#' + current) link.setAttribute('aria-current', 'page');
    else link.removeAttribute('aria-current');
  }
  content.replaceChildren();
  if (!config.url || !config.publishableKey) {
    content.append(panel('正在配置学习服务', node('p', '账号和云端学习记录启用后即可使用。', 'muted')));
    return;
  }
  if (!session) { renderLogin(registering); return; }
  if (current !== renderedPage) {
    if (current !== 'cards') {
      cardStartedAt = null;
      if (!revealed) activeId = null;
    }
    detail = null;
    editingNickname = false;
    if (typeof content.animate === 'function' && !matchMedia('(prefers-reduced-motion: reduce)').matches) {
      content.animate([{ opacity: 0.35, transform: 'translateY(3px)' }, { opacity: 1, transform: 'none' }], 220);
    }
  }
  renderedPage = current;
  if (current === 'settings') { renderSettings(); return; }
  if (!ready) {
    content.append(panel('加载学习记录', button('重新加载', () => run(openSession), 'primary')));
    return;
  }
  if (current === 'words' || current === 'favorites') renderWords(current === 'favorites');
  if (current === 'tree') wordTree.show(session.user?.id, wordBookWords(), hasMeaning, speak);
  if (current === 'cards') {
    const library = node('select');
    library.setAttribute('aria-label', '闪卡词库');
    for (const [kind, label] of [['mine','我的词库'],['all','全部词库']]) {
      const option = node('option',label);
      option.value = kind;
      library.append(option);
    }
    const librarySource = reviewLibrary ?? (syncedWords().some(word => !starterIDs.has(word.id)) ? 'mine' : 'all');
    library.value = librarySource;
    library.addEventListener('change',() => {
      if (busy) {
        library.value = librarySource;
        return;
      }
      reviewLibrary = library.value;
      queueIndex = 0;
      resetCard();
      render();
    });
    header.append(library,addIcon(button('朗读设置', () => openSettings('speech')), 'speaker'));
    renderCard();
  }
  if (current === 'friends') renderFriends();
  if (['goals','today','plans','translation','writing','roots'].includes(current)) workspace.show(current);
}

function renderLogin(registering) {
  const [emailField, email] = field('邮箱', {
    type: 'email', required: true, autocomplete: 'email', placeholder: '输入你的邮箱',
  });
  const [passwordField, password] = field(registering ? '设置密码（至少 10 位）' : '密码', {
    type: 'password', required: true, maxLength: 72,
    autocomplete: registering ? 'new-password' : 'current-password',
  });
  const [codeField, code] = field('注册邀请码', {
    required: registering, spellcheck: false, autocomplete: 'off', placeholder: '粘贴完整的邀请码',
  });
  const fields = registering ? [emailField, passwordField, codeField] : [emailField, passwordField];

  const display = form(fields, registering ? '创建账号' : '登录', async () => {
    const address = email.value.trim();
    if (!address || !email.validity.valid) {
      email.focus();
      throw new Error('请输入有效的邮箱地址。');
    }
    if (!password.value || (registering && password.value.length < 10)) {
      password.focus();
      throw new Error(registering ? '请设置至少 10 位的密码。' : '请输入你的 Goals 密码。');
    }
    if (registering) {
      const invite = code.value.trim();
      if (!/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/iu.test(invite)) {
        code.focus();
        throw new Error('请粘贴完整的注册邀请码，包括中间的连字符。');
      }
      await request('/functions/v1/goals-enroll', { email: address, password: password.value, code: invite });
    }
    try {
      setSession(await request('/auth/v1/token?grant_type=password', { email: address, password: password.value }));
    } catch (error) {
      if (registering) {
        location.hash = 'login';
        throw new Error('账号已创建，请用刚设置的邮箱和密码登录。');
      }
      throw error;
    }
    if (registering) history.replaceState(null, '', '#goals');
    detail = social = null;
    try {
      await openSession();
    } finally { render(); }
  });
  display.noValidate = true;
  const switchMode = node('a', registering ? '已有账号？去登录' : '使用邀请码注册', 'chip');
  switchMode.href = registering ? '#login' : '#register';
  content.append(panel(null,
    node('p', registering ? '填写你的邮箱，设置一个 Goals 密码，再粘贴邀请码。' : '请使用你为 Goals 注册的邮箱和密码。', 'muted'),
    display, group('controls', switchMode),
  ));
}

const pendingMeaning = '自定义词，待补充释义';
const hasMeaning = word => !['',pendingMeaning,'历史已斩词；恢复后可在单词本中补充释义'].includes(word.meaning?.trim() ?? '');
const wordPattern = /^[a-z]+(?:['-][a-z]+)*$/u;

function wordBookWords() {
  const mine = syncedWords();
  return mine.length ? mine : words();
}

function wordValue(spelling,result = {},current) {
  const text = key => typeof result[key] === 'string' ? result[key].trim() : '';
  const lists = key => Array.isArray(result[key]) ? result[key].filter(item=>typeof item==='string').slice(0,8) : [];
  const head = current?.word ?? (wordPattern.test(text('word').toLowerCase()) ? text('word').toLowerCase() : spelling);
  return {
    id:current?.id ?? customWordId(head),word:head,meaning:text('meaning') || current?.meaning || pendingMeaning,
    phonetic:current?.phonetic || text('phonetic'),partOfSpeech:text('partOfSpeech') || current?.partOfSpeech || '未标注',
    example:current?.example || text('example'),exampleTranslation:current?.exampleTranslation || text('exampleTranslation'),
    phrases:current?.phrases?.length ? current.phrases : lists('phrases'),
    phraseTranslations:current?.phraseTranslations?.length ? current.phraseTranslations : lists('phraseTranslations'),
    mnemonic:current?.mnemonic || text('mnemonic'),tag:text('tag') || current?.tag || '自定义',
    difficulty:Math.round(Math.max(1,Math.min(5,Number(result.difficulty) || current?.difficulty || 3))),
  };
}

function customWordId(spelling) {
  const id = 'custom-' + spelling;
  const current = get(id, 'word');
  // Editing a spelling keeps its ID so review progress and favorites follow the word.
  return current && current.word.toLowerCase() !== spelling ? id + '-' + crypto.randomUUID() : id;
}

function missingNotice() {
  return '请先在「设置 → DeepSeek」配置 API 密钥，再补全释义。';
}

async function completeWords(items) {
  if (!workspace.aiConfigured()) throw new Error(missingNotice());
  let finished = 0;
  for (let start=0;start<items.length;start+=8) {
    const batch=items.slice(start,start+8);
    try {
      const response=await ai('word_batch',JSON.stringify(batch.map(word=>word.word)));
      const results=Array.isArray(response.words) ? response.words : [];
      const byWord=new Map(results.filter(result=>typeof result?.word==='string' && typeof result?.meaning==='string' && result.meaning.trim())
        .map(result=>[result.word.toLowerCase(),result]));
      const writes=batch.filter(word=>byWord.has(word.word.toLowerCase()))
        .map(word=>write(word.id,'word',wordValue(word.word,byWord.get(word.word.toLowerCase()),word)));
      if (writes.length) await sync(writes);
      finished+=writes.length;
    } catch (error) {
      if (!finished) throw error;
      wordBookFeedback='已补全 '+finished+' 个词。'+error.message;
      return;
    }
  }
  wordBookFeedback='已补全 '+finished+' 个词的释义';
}

async function addWord() {
  const spelling=addWordDraft.trim().toLowerCase();
  if (!wordPattern.test(spelling)) throw new Error('请输入一个英文单词。');
  const existing=wordBookWords().find(word=>word.word.toLowerCase()===spelling);
  if (existing) {
    if (!hasMeaning(existing)) await completeWords([existing]);
    else wordBookFeedback=spelling+' 已在单词本里';
    addWordDraft='';
    return;
  }
  let result;
  let failure;
  if (workspace.aiConfigured()) {
    try { result=await ai('word',spelling); }
    catch (error) { failure=error; }
  }
  const word=wordValue(spelling,result);
  if (wordBookWords().some(item=>item.word.toLowerCase()===word.word)) {
    wordBookFeedback=word.word+' 已在单词本里';
  } else {
    await sync([write(word.id,'word',word)]);
    wordBookFeedback=hasMeaning(word) ? '已补全并加入 '+word.word : '已先加入 '+word.word+'，释义待补全';
    if (failure) wordBookFeedback+='。'+failure.message;
  }
  addWordDraft=''; wordFilter='';
}

async function importWords(candidates) {
  const existing=new Set(words().map(word=>word.word.toLowerCase()));
  const additions=[];
  for (const raw of candidates) {
    const word=raw.toLowerCase();
    const value=wordValue(word);
    // A previous tombstone also covers words removed using 斩.
    if (!wordPattern.test(word) || existing.has(word) || entries.has(keyFor(value.id,'word'))) continue;
    existing.add(word);
    additions.push(write(value.id,'word',value));
  }
  for (let index=0;index<additions.length;index+=200) await sync(additions.slice(index,index+200));
  if (additions.length) wordFilter='';
  const skipped=candidates.length-additions.length;
  return '已从图片加入 '+additions.length+' 个单词'+(skipped ? '，跳过 '+skipped+' 个重复或已删除的词' : '');
}

function wordDetail(label, text, note) {
  const children=[node('strong',label,'muted'),node('p',text,'prose')];
  if (note) children.push(node('p',note,'muted'));
  return group('word-detail',...children);
}

function removeWord(word) {
  return sync([write(word.id,'word',null),write(word.id,'progress',null),
    write(word.id,'favorite',false),write(word.id,'dismissed',false)]);
}

function confirmWordRemoval(word) {
  const dialog = node('dialog', null, 'word-editor');
  const heading = node('h2', '删除「' + word.word + '」？');
  heading.id = 'word-delete-title';
  const description = node('p', '删除后，该词的收藏和复习进度也会移除。');
  description.id = 'word-delete-description';
  dialog.setAttribute('aria-labelledby', heading.id);
  dialog.setAttribute('aria-describedby', description.id);
  const cancel = button('取消', () => dialog.close());
  cancel.autofocus = true;
  const remove = button('确认删除', () => {
    dialog.close();
    run(async () => {
      await removeWord(word);
      if (get(word.id, 'word') === null) {
        expandedWords.delete(word.id);
        wordBookFeedback = '已删除「' + word.word + '」';
      }
    });
  }, 'danger');
  dialog.addEventListener('close', () => dialog.remove());
  dialog.append(heading, group('stack', description, group('controls', cancel, remove)));
  document.body.append(dialog);
  dialog.showModal();
}

function editWord(word) {
  const dialog = node('dialog', null, 'word-editor');
  const heading = node('h2', '编辑单词');
  heading.id = 'word-editor-title';
  dialog.setAttribute('aria-labelledby', heading.id);
  const spelling = field('英文单词', {
    value: word.word, required: true, maxLength: Math.max(256, word.word.length),
    autocomplete: 'off', spellcheck: false, autofocus: true,
  });
  const meaning = field('中文释义', { value: hasMeaning(word) ? word.meaning : '', placeholder: '留空可稍后补充' });
  const phonetic = field('音标', { value: word.phonetic ?? '' });
  const partOfSpeech = field('词性', { value: word.partOfSpeech === '未标注' ? '' : word.partOfSpeech ?? '' });
  const example = field('例句', { value: word.example ?? '' });
  const exampleTranslation = field('例句翻译', { value: word.exampleTranslation ?? '' });
  const tag = field('标签', { value: word.tag === '自定义' ? '' : word.tag ?? '' });
  const error = node('p', '', 'word-editor-error danger');
  error.setAttribute('role', 'alert');
  const revision = entries.get(keyFor(word.id, 'word'))?.revision;
  const editor = form([
    spelling[0], meaning[0], group('word-editor-pair', phonetic[0], partOfSpeech[0]),
    example[0], exampleTranslation[0], tag[0], error,
  ], '保存修改', async () => {
    error.textContent = '';
    const nextSpelling = spelling[1].value.trim().toLowerCase();
    if (!wordPattern.test(nextSpelling)) {
      spelling[1].focus();
      error.textContent = '请输入一个有效的英文单词。';
      return;
    }
    if (nextSpelling !== word.word.toLowerCase() &&
        words().some(item => item.id !== word.id && item.word.toLowerCase() === nextSpelling)) {
      spelling[1].focus();
      error.textContent = '「' + nextSpelling + '」已在单词本里。';
      return;
    }
    const next = {
      ...word,
      word: nextSpelling,
      meaning: meaning[1].value.trim() || pendingMeaning,
      phonetic: phonetic[1].value.trim(),
      partOfSpeech: partOfSpeech[1].value.trim() || '未标注',
      example: example[1].value.trim(),
      exampleTranslation: exampleTranslation[1].value.trim(),
      tag: tag[1].value.trim() || '自定义',
    };
    const change = write(word.id, 'word', next);
    try {
      if (change.revision === revision) {
        await sync([change]);
        if (JSON.stringify(canonical(get(word.id, 'word'))) === JSON.stringify(canonical(next))) {
          wordBookFeedback = '已保存「' + next.word + '」的修改';
          dialog.close();
          return;
        }
      }
      error.textContent = '词条已在另一端更新。请取消后重新打开词条。';
    } catch (failure) {
      error.textContent = failure instanceof TypeError ? '连接失败，请检查网络后重试。' : failure.message;
    }
  });
  const cancel = button('取消', () => { if (!busy) dialog.close(); });
  editor.lastElementChild.prepend(cancel);
  dialog.addEventListener('cancel', event => { if (busy) event.preventDefault(); });
  dialog.addEventListener('close', () => dialog.remove());
  dialog.append(heading, editor);
  document.body.append(dialog);
  dialog.showModal();
}

function wordCard(word) {
  const expanded=expandedWords.has(word.id);
  const tags=word.tag && word.tag!=='自定义';
  const title=group('word-heading',node('strong',word.word),
    node('span',[word.phonetic,word.partOfSpeech!=='未标注' ? word.partOfSpeech : ''].filter(Boolean).join('  '),'muted'));
  const reading=group('word-summary',title,node('p',word.meaning));
  const tools=group('word-row-tools');
  const favorite=Boolean(get(word.id,'favorite'));
  if (!hasMeaning(word)) tools.append(addIcon(button('补全释义',()=>run(()=>completeWords([word]))),'sparkles'));
  if (word.phrases?.length || word.example || word.mnemonic || tags) {
    const toggle=addIcon(button('',()=> {
      if (expandedWords.has(word.id)) expandedWords.delete(word.id);
      else expandedWords.add(word.id);
      update();
    },'word-disclosure'),'chevron');
    const update=()=>{
      const open=expandedWords.has(word.id);
      toggle.setAttribute('aria-label',open?'收起词条详情':'展开词条详情');
      toggle.setAttribute('aria-expanded',String(open));
      details.hidden=!open;
    };
    const details=group('word-details');
    if (word.phrases?.length) details.append(wordDetail('搭配',word.phrases.join(' · '),word.phraseTranslations?.join(' · ')));
    if (word.example) details.append(wordDetail('例句',word.example,word.exampleTranslation));
    if (word.mnemonic) details.append(wordDetail('助记',word.mnemonic));
    if (tags) details.append(node('small',word.tag,'muted'));
    details.hidden=!expanded;
    reading.append(details);
    tools.append(toggle);
    update();
  }
  const bookmark=addIcon(button('',()=>run(()=>changeFavorite(word)),'word-bookmark chip'),favorite?'bookmark-fill':'bookmark');
  bookmark.setAttribute('aria-label',favorite?'从错词收藏移除':'加入错词收藏');
  bookmark.setAttribute('aria-pressed',String(favorite));
  tools.append(bookmark);
  const card=group('word-card panel',reading,tools);
  if (!starterIDs.has(word.id) && get(word.id, 'word')) {
    card.classList.add('custom-word-card');
    const edit = addIcon(button('编辑', () => editWord(word)), 'pen');
    const remove = addIcon(button('删除', () => confirmWordRemoval(word), 'danger'), 'trash');
    tools.append(edit, remove);
    return group('word-entry', card);
  }
  const remove=addIcon(button('删除',()=>confirmWordRemoval(word),'word-remove danger'),'trash');
  remove.hidden=true;
  const frame=group('word-entry',card,remove);
  let start;
  card.addEventListener('contextmenu',event=>{event.preventDefault();remove.hidden=false;});
  card.addEventListener('pointerdown',event=>{
    if (event.button===0 && !event.target.closest('button')) start=[event.clientX,event.clientY];
  });
  card.addEventListener('pointercancel',()=>{start=null;});
  card.addEventListener('pointerup',event=>{
    if (!start) return;
    const dx=event.clientX-start[0],dy=event.clientY-start[1];
    start=null;
    if (dx < -28 && Math.abs(dx)>Math.abs(dy)) remove.hidden=false;
    else if (dx>20 || Math.abs(dx)<5) remove.hidden=true;
  });
  return frame;
}

function renderWords(favoritesOnly) {
  const list=group('word-list');
  const library=wordBookWords();
  const count=node('strong');
  const feedback=node('span',wordBookFeedback,'muted');
  const missing=library.filter(word=>!hasMeaning(word));
  if (!favoritesOnly) {
    const [label,input]=field('输入新单词',{value:addWordDraft,required:true,maxLength:60,placeholder:'输入新单词'});
    label.className='word-input';
    label.firstChild.remove();
    input.setAttribute('aria-label','输入新单词');
    const add=form([label],'添加单词',addWord);
    add.classList.add('word-add-form');
    const submit=add.querySelector('button');
    addIcon(submit,'plus');
    submit.disabled=!input.value.trim();
    input.addEventListener('input',()=>{
      addWordDraft=input.value;
      submit.disabled=!input.value.trim();
    });
    const photo=addIcon(button('图片导词',()=>showVocabularyImport({
      node,group,button,addIcon,ai,importWords,onImported:message=>{wordBookFeedback=message;render();},
    })),'scan');
    content.append(group('word-add-row',add,photo));
  }
  const [searchLabel,search]=field('搜索单词、释义或标签',{
    type:'search',value:wordFilter,placeholder:'搜索单词、释义或标签',
  });
  searchLabel.firstChild.remove();
  search.setAttribute('aria-label','搜索单词、释义或标签');
  searchLabel.className='word-search';
  addIcon(searchLabel,'search');
  const actions=group('controls',feedback);
  if (!favoritesOnly && missing.length) {
    actions.append(addIcon(button('补全缺失释义（'+missing.length+'）',()=>run(()=>completeWords(missing))),'sparkles'));
  }
  function update() {
    const text=wordFilter.trim().toLowerCase();
    const chosen=library.filter(word=>(!favoritesOnly || get(word.id,'favorite'))
      && [word.word,word.meaning,word.tag,word.phonetic,word.partOfSpeech].join(' ').toLowerCase().includes(text));
    count.textContent=chosen.length+' 个单词';
    list.replaceChildren(...chosen.map(wordCard));
    if (!chosen.length) list.append(panel(favoritesOnly?'还没有收藏错词。':library.length?'没有匹配的单词':'还没有单词'));
  }
  search.addEventListener('input',()=>{wordFilter=search.value;update();});
  update();
  content.append(searchLabel,group('row word-count',count,actions),list);
}

function materialize(word) {
  return entries.has(keyFor(word.id,'word')) ? [] : [write(word.id,'word',word)];
}

async function changeFavorite(word) {
  const next = !get(word.id, 'favorite');
  await sync([...materialize(word), write(word.id, 'favorite', next), write(word.id, 'dismissed', !next)]);
}

function resetCard() {
  activeId = null;
  revealed = correction = false;
  cardStartedAt = null;
  cardMessage = '';
}

function skipCard() {
  if (busy) return;
  queueIndex++;
  resetCard();
  render();
}

const meaningSeparator = /[；;、,，/|]/u;
const normalizeMeaning = text => text.toLowerCase().replace(/[\s。.．…⋯!！?？:：\-—_()（）\[\]【】"'“”‘’]/gu, '');

function meaningParts(text) {
  return text.split(meaningSeparator).map(normalizeMeaning).filter(Boolean);
}

function matches(answer, expected) {
  const supplied = meaningParts(answer);
  const accepted = new Set(meaningParts(expected));
  return supplied.length > 0 && supplied.every(part => accepted.has(part));
}

function startTiming() {
  if (page() === 'cards' && !revealed && activeId && !document.hidden && document.hasFocus()) cardStartedAt ??= performance.now();
}

async function submitReview(word, answer) {
  const cleaned = answer.trim();
  if (!cleaned) return;
  const spent = elapsedStudy();
  if (cleaned === '、') return markUnknown(word, spent);
  if (!hasMeaning(word)) return review(word, false, '这个单词还缺少释义。可以在单词本补充后再练习。', spent);
  if (matches(cleaned, word.meaning)) return review(word, true, '已命中标准释义中的核心义项。', spent);
  if (!workspace.aiConfigured()) return review(word, false, '未匹配标准释义。可在设置中开启 AI 判分。', spent);
  const judgment = await ai('judge', JSON.stringify({ word: word.word, meaning:word.meaning, answer:cleaned }));
  if (typeof judgment.isCorrect !== 'boolean') throw new Error('DeepSeek 未返回有效判分，请重试。');
  return review(word, judgment.isCorrect, judgment.reason, spent);
}

function submitCorrection(word, answer) {
  if (!matches(answer, word.meaning)) return false;
  correction = false;
  cardMessage = '重输正确。';
  speak(word.word);
  return true;
}

function markUnknown(word, duration = elapsedStudy()) {
  speak(word.word);
  return review(word, false, '已标记为不认识。', duration);
}

function elapsedStudy() {
  return cardStartedAt === null ? 0 : Math.min(60, Math.round((performance.now() - cardStartedAt) / 1000));
}

async function review(word, correct, reason = '', duration = elapsedStudy()) {
  if (correct) speak(word.word);
  const previous = get(word.id, 'progress');
  const level = correct ? Math.min((previous?.level ?? 0) + 1, 5) : 0;
  const now = Math.floor(Date.now() / 1000);
  const nextReview = now + (correct ? [1800, 43200, 259200, 604800, 1296000][level - 1] : 0);
  const progress = { wordID: word.id, level, lastReview: now, nextReview,
    correctCount: (previous?.correctCount ?? 0) + Number(correct),
    incorrectCount: (previous?.incorrectCount ?? 0) + Number(!correct) };
  const changes = [...materialize(word), write(word.id, 'progress', progress), write(word.id, 'dismissed', false)];
  if (!correct) changes.push(write(word.id, 'favorite', true));
  await sync(changes, [{
    event_id: crypto.randomUUID(), word_id: word.id, spelling: word.word, level,
    reviewed_at: new Date(now * 1000).toISOString(), active_seconds: duration,
  }]);
  if (activeId !== word.id) return;
  revealed = true;
  correction = !correct && hasMeaning(word);
  cardMessage = typeof reason === 'string' ? reason : '';
}

function speak(text) {
  if (!('speechSynthesis' in window)) {
    notice.textContent = '当前浏览器不支持朗读。';
    return;
  }
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = speech.accent;
  utterance.rate = speech.rate;
  speechSynthesis.cancel();
  speechSynthesis.speak(utterance);
  return true;
}

function reviewQueue() {
  if (reviewMode === 'all') return studyWords();
  if (reviewMode === 'favorites') return studyWords().filter(word => get(word.id,'favorite'));
  if (reviewMode === 'hard') return studyWords().filter(word => word.difficulty >= 4);
  return dueWords().sort((a,b) =>
    (get(a.id,'progress')?.nextReview ?? Infinity) - (get(b.id,'progress')?.nextReview ?? Infinity));
}

function cardMetric(value, label) {
  return group('metric', node('strong', value), node('span', label));
}

function renderCard() {
  const queue = reviewQueue();
  const mine = studyWords();
  const metric = group('metrics',
    cardMetric(dueWords().length, '待复习'),
    cardMetric(mine.filter(word => get(word.id,'progress')).length,'已开始'),
    cardMetric(mine.filter(word => get(word.id,'progress')?.level === 5).length,'已掌握'));
  content.append(group('card-toolbar', workspace.tabs(reviewModes, reviewMode, mode => {
    if (busy) return;
    reviewMode = mode; queueIndex = 0; resetCard(); render();
  }, '复习模式'), metric));
  const position = queue.length ? ((queueIndex % queue.length) + queue.length) % queue.length : 0;
  const word = (revealed ? mine : queue).find(item => item.id === activeId) ?? queue[position];
  if (!word) {
    resetCard();
    content.append(panel(reviewMode === 'due' ? '当前没有到期单词' : '当前模式没有可复习的单词',
      button('查看全部闪卡', () => {
        if (!mine.length) reviewLibrary = 'all';
        reviewMode = 'all';
        render();
      })));
    return;
  }
  if (activeId !== word.id) { resetCard(); activeId = word.id; }
  const level = get(word.id, 'progress')?.level ?? 0;
  const currentIndex = queue.findIndex(item => item.id === word.id);
  content.append(node('p',[currentIndex < 0 ? '本词已完成' : (currentIndex + 1) + ' / ' + queue.length,
    word.tag, '等级 ' + level + '/5'].filter(Boolean).join('  ·  '), 'muted card-count'));
  const pronunciation = addIcon(button('', () => speak(word.word)), 'speaker');
  pronunciation.classList.add('chip');
  pronunciation.setAttribute('aria-label', '朗读 ' + word.word);
  const face = group('panel flashcard', group('',
    group('row spelling-row', node('div', word.word, 'spelling'), pronunciation),
    node('div', [word.phonetic, word.partOfSpeech].filter(item => item && item !== '未标注').join(' '), 'muted')
  ));
  if (revealed) {
    face.firstElementChild.append(node('p',word.meaning,'answer'));
    if (!correction) face.firstElementChild.append(node('p',word.example,'muted answer'),
      node('p',word.exampleTranslation,'muted'));
  }
  const stack = group('stack card-stack', face);
  content.append(stack);
  if (!revealed && level <= 4) {
    const hint = group('flash-mnemonic muted');
    hint.setAttribute('aria-live','polite');
    face.firstElementChild.append(hint);
    mnemonics.mount(hint,word,queue.slice(currentIndex+1));
  }
  if (!revealed && speech.auto && lastSpoken !== word.id) {
    lastSpoken = word.id;
    speak(word.word);
  }
  const favorite = addIcon(button(get(word.id,'favorite') ? '取消收藏' : '不熟收藏',
    () => run(() => changeFavorite(word))), 'bookmark');
  const cut = addIcon(button('斩', () => run(async () => {
    if (!confirm('从单词本和复习中移除这个单词？')) return;
    await sync([write(word.id,'word',null),write(word.id,'progress',null),
      write(word.id,'favorite',false),write(word.id,'dismissed',false)]);
    resetCard();
  }), 'danger'), 'cut');
  const controls = group('controls card-actions');
  if (!correction) controls.append(button('上一个', () => {
    if (busy) return;
    queueIndex--;
    resetCard();
    render();
  }), favorite, cut);
  let continueButton;
  if (!revealed) {
    const [label, input] = field('中文释义', { placeholder: '输入中文含义，或输入 、 标记不认识', required: true });
    input.addEventListener('input',startTiming);
    const answer = form([label],'提交判分',() => submitReview(word,input.value));
    answer.classList.add('card-answer-form');
    stack.append(answer, node('p','输入一个核心中文含义。','muted card-note'));
    controls.append(button('不认识', () => run(() => markUnknown(word))),
      button('跳过',skipCard,'primary'));
    startTiming();
    input.focus({preventScroll:true});
  } else if (correction) {
    const [label, input] = field('重新输入中文释义', {required:true, autocomplete:'off'});
    const feedback = node('p', '', 'danger card-correction-feedback');
    feedback.setAttribute('role', 'alert');
    input.setAttribute('aria-describedby', 'card-correction-help');
    const help = node('p', '从上方释义中选一个义项，重新输入正确后才能继续。', 'muted');
    help.id = 'card-correction-help';
    const retry = node('form', null, 'card-answer-form');
    retry.append(label, node('button', '检查释义', 'primary'));
    retry.addEventListener('submit', event => {
      event.preventDefault();
      if (busy) return;
      if (submitCorrection(word, input.value)) render();
      else {
        feedback.textContent = '还不正确，请按上方释义再输入一次。';
        input.focus();
        input.select();
      }
    });
    stack.append(panel('订正释义', help, retry, feedback));
    input.focus({preventScroll:true});
  } else {
    if (cardMessage) stack.append(node('p',cardMessage,'muted card-note'));
    continueButton = button('继续',() => {
      if (reviewMode === 'due') queueIndex = 0;
      else queueIndex++;
      resetCard();
      render();
    },'primary');
    continueButton.title = '按 Enter 进入下一个单词';
    controls.append(continueButton);
  }
  if (controls.childElementCount) stack.append(controls);
  // The answer field is removed when judgment finishes. Keep the next action reachable by Enter.
  continueButton?.focus({preventScroll:true});
}

const duration = seconds => seconds < 60 ? seconds + ' 秒' : Math.floor(seconds / 60) + ' 分 ' + seconds % 60 + ' 秒';

async function socialAction(action = 'list', target = null) {
  social = await rpc('social', { action, target });
}

function renderFriends() {
  if (!social) {
    content.append(panel('好友与排行', button('加载今日排行', () => run(() => socialAction(), null), 'primary')));
    return;
  }
  if (!social.profile) {
    const [label, name] = field('好友可见的昵称', { required: true, maxLength: 32 });
    content.append(panel('创建好友资料', node('p', '成为好友后，双方可查看当天的单词、等级和学习时长。', 'muted'),
      form([label], '保存昵称', () => socialAction('nickname', name.value.trim()))));
    return;
  }
  if (detail) {
    content.append(panel(detail.person.nickname + ' · 今日学习',
      node('p', duration(detail.person.seconds) + ' · ' + detail.person.word_count + ' 个单词', 'muted'),
      group('controls', button('返回排行榜', () => { detail = null; render(); })),
      group('list', ...detail.words.map(item => group('row', node('strong', item.word), node('span', '等级 ' + item.level, 'chip')))),
      ...(!detail.words.length ? [node('p', '今天还没有复习记录。', 'muted')] : []),
      ...(!detail.person.is_me ? [group('controls', button('移除好友', () => run(async () => {
        if (!confirm('确定移除这位好友吗？')) return;
        await socialAction('remove', detail.person.user_id);
        detail = null;
      })))] : [])));
    return;
  }
  const [codeLabel, code] = field('对方的好友码', { required: true, maxLength: 36 });
  content.append(panel('好友',
    group('controls', node('span', '我的好友码', 'muted'), button('复制好友码', () => run(async () => {
      await navigator.clipboard.writeText(social.profile.invite_code);
      notice.textContent = '好友码已复制。';
    }))),
    node('code', social.profile.invite_code),
    form([codeLabel], '发送申请', () => socialAction('invite', code.value.trim())),
    ...social.requests.map(person => group('row',
      node('span', person.nickname + (person.incoming ? ' 请求添加你' : ' · 等待确认')),
      group('controls',
        ...(person.incoming ? [button('接受', () => run(() => socialAction('accept', person.user_id)))] : []),
        button(person.incoming ? '忽略' : '撤回', () => run(() => socialAction('remove', person.user_id)))
      )
    ))));
  const ranking = social.ranking.map((person, index) => {
    const row = button('', () => run(async () => {
      const data = await rpc('social', { action: 'detail', target: person.user_id });
      detail = { person, words: data.words };
    }), 'rank-row row');
    row.append(node('strong', (index + 1) + '. ' + person.nickname + (person.is_me ? '（我）' : '')),
      node('span', person.word_count + ' 个单词 · ' + duration(person.seconds), 'muted'));
    return row;
  });
  const actions = group('controls', button('修改昵称', () => {
    editingNickname = true;
    render();
    document.querySelector('#ranking-nickname')?.focus();
  }), button('刷新', () => run(() => socialAction())));
  const editor = [];
  if (editingNickname) {
    const [label, name] = field('排行榜昵称', {
      id: 'ranking-nickname', value: social.profile.nickname, required: true, maxLength: 32,
    });
    const edit = form([label], '保存昵称', async () => {
      const nickname = name.value.trim();
      if (!nickname) throw new Error('请输入排行榜昵称。');
      await socialAction('nickname', nickname);
      editingNickname = false;
      notice.textContent = '排行榜昵称已更新。';
    });
    edit.lastElementChild.append(button('取消修改', () => { editingNickname = false; render(); }));
    editor.push(edit);
  }
  content.append(panel(null, group('row', node('h2', '今日排行榜'), actions),
    node('p', '北京时间 · 按复习词数排名，词数相同看学习时长', 'muted'), ...editor, ...ranking));
}

function openSettings(mode) {
  settingsMode = mode;
  if (page() !== 'settings') location.hash = 'settings';
  else render();
}

function renderSettings() {
  const modes = [['general','通用'],['deepseek','DeepSeek'],['speech','朗读'],['shortcuts','快捷键'],['account','账号']];
  content.append(workspace.tabs(modes,settingsMode,mode => openSettings(mode),'设置分类'));
  if (settingsMode === 'deepseek') content.append(workspace.aiSettings());
  if (settingsMode === 'shortcuts') content.append(shortcutSettings());
  if (settingsMode === 'speech') {
    const [speedLabel,speed] = field('语速', { type:'range', min:0.5, max:1.5, step:0.05, value:speech.rate });
    const [autoLabel,auto] = field('闪卡自动朗读', { type:'checkbox', checked:speech.auto });
    autoLabel.classList.add('task-toggle');
    const saveSpeech = () => localStorage.setItem('goals.speech', JSON.stringify(speech));
    speed.addEventListener('input', () => { speech.rate = Number(speed.value); saveSpeech(); });
    auto.addEventListener('change', () => { speech.auto = auto.checked; saveSpeech(); });
    content.append(panel('朗读设置', autoLabel,
      workspace.tabs([['en-US','美式'],['en-GB','英式']],speech.accent,accent => {
        speech.accent = accent; saveSpeech(); render();
      }, '发音'),speedLabel,group('controls',addIcon(button('试听发音', () => speak("Good morning. Let's get started.")),'speaker'))));
  }
  if (settingsMode === 'general') {
    content.append(panel('通用',node('p','工作区跟随设备的浅色或深色外观。','muted'),
      group('controls',button('显示 / 隐藏侧栏',toggleSidebar))));
  }
  if (settingsMode === 'account') {
    content.append(panel('账号',node('p',session.user?.email ?? ''),
      node('p','在新版 Mac Goals 的「设置 → 账号」登录同一个账号，即可同步词库、收藏和闪卡进度。','muted'),
      group('controls',button('立即同步',() => run(async () => {
        await openSession();
        notice.textContent = '已读取云端学习记录。';
      }),'primary'),button('退出登录',() => {
        setSession(null);
        resetCard();
        wordTree.reset();
        entries.clear();
        wordOrder=[]; expandedWords.clear(); addWordDraft=''; wordBookFeedback=''; wordFilter='';
        ready = false;
        detail = social = null;
        mnemonics.reset();
        workspace.reset();
        location.hash = 'login';
        render();
      }))));
  }
}

function shortcutSettings() {
  const labels = { skip: '跳过当前单词', unknown: '标记为不认识', favorite: '切换错词收藏' };
  const fields = Object.entries(labels).map(([action, label]) => {
    const select = node('select');
    const wrapper = node('label', label);
    wrapper.append(select);
    for (const value of ['', ...'abcdefghijklmnopqrstuvwxyz1234567890']) {
      const option = node('option', value ? 'Ctrl + Shift + ' + value.toUpperCase() : '关闭');
      option.value = value;
      option.disabled = !!value && value !== shortcuts[action] && Object.values(shortcuts).includes(value);
      select.append(option);
    }
    select.value = shortcuts[action];
    select.addEventListener('change', () => {
      shortcuts[action] = select.value;
      localStorage.setItem('goals.shortcuts', JSON.stringify(shortcuts));
      render();
    });
    return wrapper;
  });
  return panel('快捷键', ...fields, node('p', '仅在闪卡复习中生效。浏览器保留的组合键可以换成其他字母。', 'muted'),
    group('controls', button('恢复默认', () => {
      Object.assign(shortcuts, defaults);
      localStorage.removeItem('goals.shortcuts');
      render();
    })));
}

async function openSession() {
  await sync();
  const results = await Promise.allSettled([workspace.load(), workspace.loadDeepSeek(), mnemonics.load()]);
  if (results[0].status === 'rejected') notice.textContent = '学习工作区暂时未连接，请重新加载。';
  if (page() === 'friends') await socialAction();
}

function toggleSidebar() {
  const hidden = document.body.classList.toggle('sidebar-closed');
  sidebar.setAttribute('aria-expanded',String(!hidden));
  if (!mobile.matches) localStorage.setItem('goals.sidebarHidden',JSON.stringify(hidden));
}

function fillSearch() {
  const text = query.value.trim().toLowerCase();
  const actions = Object.entries(pages).filter(([, title]) => title.toLowerCase().includes(text))
    .map(([id,title]) => button(title,() => { quickSearch.close(); location.hash = id; }));
  const matchingWords = text && session ? words().filter(word => [word.word,word.meaning].join(' ').toLowerCase().includes(text))
    .slice(0,12).map(word => button(word.word + '  ' + word.meaning,() => {
      quickSearch.close();
      wordFilter = word.word;
      if (page() === 'words') render();
      else location.hash = 'words';
    })) : [];
  quickResults.replaceChildren(...actions,...matchingWords);
  if (!actions.length && !matchingWords.length) quickResults.append(node('p','没有匹配的内容。','muted'));
}

function isSearchBackdrop(event) {
  if (event.target !== quickSearch) return false;
  const bounds = quickSearch.getBoundingClientRect();
  return event.clientX < bounds.left || event.clientX >= bounds.right
    || event.clientY < bounds.top || event.clientY >= bounds.bottom;
}

let searchPressStartedOutside = false;
quickSearch.addEventListener('pointerdown', event => {
  searchPressStartedOutside = event.button === 0 && isSearchBackdrop(event);
});
quickSearch.addEventListener('pointercancel', () => { searchPressStartedOutside = false; });
quickSearch.addEventListener('click', event => {
  const dismiss = searchPressStartedOutside && isSearchBackdrop(event);
  searchPressStartedOutside = false;
  if (dismiss) quickSearch.close();
});

function showSearch() {
  if (quickSearch.open) { quickSearch.close(); return; }
  query.value = '';
  fillSearch();
  quickSearch.showModal();
  query.focus();
}

sidebar.addEventListener('click',toggleSidebar);
document.querySelector('#search-toggle').addEventListener('click',showSearch);
query.addEventListener('input',fillSearch);
const startHidden = mobile.matches || readLocal('goals.sidebarHidden') === true;
document.body.classList.toggle('sidebar-closed',startHidden);
sidebar.setAttribute('aria-expanded',String(!startHidden));
document.querySelector('.sidebar').addEventListener('click', event => {
  if (mobile.matches && event.target.closest('a') && !document.body.classList.contains('sidebar-closed')) toggleSidebar();
});

document.addEventListener('keydown', event => {
  const key = event.key.toLowerCase();
  if ((event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && key === 'k') {
    event.preventDefault(); showSearch(); return;
  }
  if ((event.metaKey || event.ctrlKey) && !event.shiftKey && !event.altKey && key === ',') {
    event.preventDefault(); openSettings('general'); return;
  }
  if (!session || page() !== 'cards' || busy || event.repeat || event.isComposing ||
      !event.ctrlKey || !event.shiftKey || event.metaKey || event.altKey) return;
  const value = event.code.replace(/^(Key|Digit)/u, '').toLowerCase();
  const word = words().find(item => item.id === activeId);
  if (!word) return;
  if (value === shortcuts.skip && !revealed) { event.preventDefault(); skipCard(); }
  if (value === shortcuts.unknown && !revealed) { event.preventDefault(); run(() => markUnknown(word)); }
  if (value === shortcuts.favorite && !correction) { event.preventDefault(); run(() => changeFavorite(word)); }
});
window.addEventListener('hashchange', () => {
  render();
  if (session && config.url && page() === 'friends') run(() => socialAction());
});
window.addEventListener('blur', () => { cardStartedAt = null; });
window.addEventListener('focus', startTiming);
document.addEventListener('visibilitychange', () => { if (document.hidden) cardStartedAt = null; else startTiming(); });
setInterval(() => {
  if (!session || !config.url || document.hidden || busy || document.querySelector('dialog[open]')) return;
  // Preserve text the learner is entering and the currently revealed answer.
  if (revealed || (page() === 'friends' && (detail || editingNickname)) ||
      [...content.querySelectorAll('input')].some(input => input.value)) return;
  if (page() === 'friends') run(() => socialAction());
  else if (['words','cards','favorites'].includes(page())) run(sync);
}, 30000);

render();
if (session && config.url && config.publishableKey) run(openSession);
