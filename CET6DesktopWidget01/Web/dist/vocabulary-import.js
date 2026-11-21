import { cleanWord, imageCanvas, recognizeImage } from './vocabulary-ocr.js';

const unique = words => [...new Set(words)];
const dialogHeight = 380;

export function showVocabularyImport({ node,group,button,addIcon,ai,importWords,onImported }) {
  if (document.querySelector('#vocabulary-import')) return;
  const dialog = node('dialog',null,'vocabulary-import');
  dialog.id = 'vocabulary-import';
  dialog.setAttribute('aria-labelledby','vocabulary-import-title');
  const title = node('h2','图片导词');
  title.id = 'vocabulary-import-title';
  const picker = node('input');
  picker.type = 'file';
  picker.accept = 'image/*';
  picker.hidden = true;
  const openFile = addIcon(button('选取图片',() => picker.click()),'folder');
  const landing = group('ocr-placeholder',addIcon(node('span'),'photo'),
    node('strong','将图片拖到这里'),node('p','支持圈选、方框、下划线和荧光笔','muted'));
  const preview = group('ocr-preview',landing);
  const count = node('span','已选 0','muted');
  const status = node('p','','muted ocr-status');
  status.setAttribute('role','status');
  const options = group('ocr-options');
  const showAll = node('input');
  showAll.type = 'checkbox';
  const allLabel = node('label',null,'task-toggle');
  allLabel.append(showAll,node('span','查看整页识别词'));
  allLabel.hidden = true;
  const results = group('ocr-results panel',group('row',node('strong','识别结果'),count),status,options,allLabel);
  let canvas = null;
  let detected = [];
  let suggested = [];
  let selected = new Set();
  let job = null;
  let loading = false;
  let committing = false;

  function updateSelection() {
    count.textContent = '已选 ' + selected.size;
    add.textContent = '加入 ' + selected.size + ' 个单词';
    add.disabled = loading || committing || !selected.size;
    cloud.disabled = !canvas || loading || committing;
    cancel.disabled = committing;
    showAll.disabled = loading || committing;
    cloudControls.hidden = !canvas;
  }

  function renderBoxes() {
    if (!canvas) return;
    let overlay = preview.querySelector('.ocr-boxes');
    if (!overlay) {
      const framed = group('ocr-picture',canvas);
      overlay = group('ocr-boxes');
      framed.append(overlay);
      preview.replaceChildren(framed);
    }
    overlay.replaceChildren();
    for (const word of detected) {
      if (!selected.has(word.text) || (!word.marked && !showAll.checked)) continue;
      const box = node('span');
      box.style.left = word.box.x0 / canvas.width * 100 + '%';
      box.style.top = word.box.y0 / canvas.height * 100 + '%';
      box.style.width = (word.box.x1-word.box.x0)/canvas.width*100 + '%';
      box.style.height = (word.box.y1-word.box.y0)/canvas.height*100 + '%';
      overlay.append(box);
    }
  }

  function visibleWords() {
    return unique([...suggested,...(showAll.checked ? detected.map(word=>word.text) : [])]);
  }

  function renderResults() {
    options.replaceChildren();
    for (const word of visibleWords()) {
      const check = node('input');
      check.type = 'checkbox';
      check.checked = selected.has(word);
      check.disabled = committing;
      check.addEventListener('change',() => {
        if (check.checked) selected.add(word);
        else selected.delete(word);
        updateSelection();
        renderBoxes();
      });
      const row = node('label',null,'task-toggle');
      row.append(check,node('span',word));
      options.append(row);
    }
    allLabel.hidden = !detected.some(word => !suggested.includes(word.text));
    updateSelection();
    renderBoxes();
  }

  function useSuggestions(words) {
    suggested = unique(words);
    selected = new Set(suggested);
    showAll.checked = false;
  }

  async function load(file) {
    if (committing) return;
    job?.abort();
    const controller = new AbortController();
    job = controller;
    canvas = null;
    loading = true;
    detected = [];
    useSuggestions([]);
    preview.replaceChildren(landing);
    status.textContent = '正在本地识别…';
    renderResults();
    try {
      const image = await imageCanvas(file);
      if (job !== controller || controller.signal.aborted) return;
      canvas = image;
      canvas.style.setProperty('--image-ratio',canvas.width/canvas.height);
      canvas.style.setProperty('--preview-height',dialogHeight+'px');
      renderBoxes();
      detected = await recognizeImage(canvas,controller.signal);
      if (job !== controller || controller.signal.aborted) return;
      useSuggestions(detected.filter(word => word.marked).map(word=>word.text));
      status.textContent = suggested.length ? '' : detected.length
        ? '没有找到明确标记。可查看整页识别词，或用 DeepSeek 重识别。' : '没有读到英文单词。';
    } catch (error) {
      if (job === controller && !controller.signal.aborted) status.textContent = error.message || '识别失败。';
    } finally {
      if (job === controller && !controller.signal.aborted) {
        loading = false;
        job = null;
        renderResults();
      }
    }
  }

  showAll.addEventListener('change',() => {
    if (!showAll.checked) selected = new Set([...selected].filter(word=>suggested.includes(word)));
    renderResults();
  });
  picker.addEventListener('change',() => {
    const file = picker.files[0];
    picker.value = '';
    if (file) load(file);
  });
  for (const name of ['dragenter','dragover']) preview.addEventListener(name,event=>{
    event.preventDefault();
    preview.classList.add('is-dragging');
  });
  preview.addEventListener('dragleave',()=>preview.classList.remove('is-dragging'));
  preview.addEventListener('drop',event=>{
    event.preventDefault(); preview.classList.remove('is-dragging');
    const file = event.dataTransfer.files[0];
    if (file) load(file);
  });
  dialog.addEventListener('paste',event=>{
    const file = [...event.clipboardData.files].find(item=>item.type.startsWith('image/'));
    if (!file) return;
    event.preventDefault();
    load(file);
  });

  const paste = addIcon(button('粘贴图片',async () => {
    try {
      const items = await navigator.clipboard.read();
      for (const item of items) {
        const type = item.types.find(name=>name.startsWith('image/'));
        if (type) { await load(await item.getType(type)); return; }
      }
      status.textContent = '剪贴板里没有图片。';
    } catch {
      status.textContent = '浏览器未允许读取剪贴板。可在窗口中按 Ctrl+V 或 ⌘V 粘贴图片。';
    }
  }),'clipboard');
  const cloud = addIcon(button('DeepSeek 重识别',async () => {
    if (!canvas || loading || committing) return;
    const snapshot = canvas;
    loading = true;
    status.textContent = 'DeepSeek 正在识图…';
    updateSelection();
    try {
      const result = await ai('image_words',undefined,{image:snapshot.toDataURL('image/jpeg',.85)});
      if (!dialog.open || snapshot !== canvas) return;
      const words = Array.isArray(result.words) ? result.words
        .filter(word=>typeof word==='string').map(cleanWord).filter(Boolean) : [];
      if (words.length) { useSuggestions(words); status.textContent = ''; }
      else status.textContent = 'DeepSeek 没有找到被标记的英文。';
    } catch (error) {
      if (dialog.open && snapshot === canvas) status.textContent = error.message;
    } finally {
      if (dialog.open && snapshot === canvas) { loading = false; renderResults(); }
    }
  }),'sparkles');
  const cloudControls = group('controls ocr-cloud',cloud,node('small','上传当前图片，按用量计费','muted'));
  const cancel = button('取消',()=>dialog.close());
  const add = button('加入 0 个单词',async () => {
    if (!selected.size || loading || committing) return;
    committing = true;
    status.textContent = '正在加入单词本…';
    renderResults();
    try {
      const message = await importWords(visibleWords().filter(word=>selected.has(word)));
      dialog.close();
      onImported(message);
    } catch (error) {
      status.textContent = error.message || '导入失败，请重试。';
    } finally {
      committing = false;
      if (dialog.open) renderResults();
    }
  },'primary');
  dialog.addEventListener('cancel',event=>{ if (committing) event.preventDefault(); });
  dialog.addEventListener('close',()=>{ job?.abort(); dialog.remove(); });
  dialog.append(group('row ocr-title',title,group('controls',openFile,paste)),picker,
    group('ocr-body',preview,results),group('row ocr-footer',cloudControls,group('controls',cancel,add)));
  document.body.append(dialog);
  updateSelection();
  dialog.showModal();
}
