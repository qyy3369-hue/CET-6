const branches = [
  ['meaning', '同义／近义词'],
  ['affix', '同词根／词缀'],
];

const senseGroups = [
  ['足够', '充足', '充分'], ['可行', '行得通', '切实可行'], ['减少', '降低', '减小'],
  ['开始', '起始', '开端'], ['提高', '提升', '增进'], ['帮助', '协助', '援助'],
  ['强调', '着重', '突出'], ['重要', '关键', '要紧'], ['困难', '艰难', '不易'],
  ['复杂', '错综复杂', '繁复'], ['普遍', '盛行', '流行'], ['暂时', '临时', '短暂'],
  ['建立', '创立', '设立'], ['继续', '持续', '延续'], ['选择', '挑选', '选取'],
];
const equivalentSenses = new Map(senseGroups.flatMap(group => group.map(sense => [sense, group[0]])));

function senses(word) {
  return new Set((word.meaning ?? '').split(/[；;、，,\n/|]/u).map(sense => {
    const clean = sense.replace(/[（(][^）)]*[）)]/gu, '').trim().replace(/的$/u, '');
    return equivalentSenses.get(clean) ?? clean;
  }).filter(sense => sense.length > 1));
}

const roots = [
  ['spect', /^(?:a|circum|intro|retro|re|pro|per|in|su)?spect/u],
  ['tract', /^(?:at|con|de|dis|ex|re|sub)?tract/u],
  ['struct', /^(?:con|de|in|ob|recon)?struct/u],
  ['port', /^(?:(?:im|ex|re|trans|sup|de)port|port(?:able|age|er))/u],
  ['scrib / script', /^(?:de|sub|pre|tran|trans|in|manu|con|post|re)?(?:scrib|script)/u],
  ['dict', /^(?:pre|contra|bene|male|ver|in|inter)?dict/u],
  ['ject', /^(?:pro|re|in|ob|sub|e|inter|de)ject/u],
  ['form', /^(?:trans|re|uni|con|de|in|per)?form(?:s|ed|ing|al|ance|ation|ative|er|ity|less)?$/u],
];
const prefixes = [
  ['un', /^(?:un)(?:clear|fair|happy|able|known|likely|usual|kind|safe|certain|common|expected|necessary|willing|fortunate|comfortable|helpful|lock|do)/u],
  ['re', /^(?:re)(?:build|write|read|use|start|open|play|work|make|do|think|learn|view|place|connect|organize|cover)/u],
  ['pre', /^(?:pre)(?:view|heat|pay|order|test|school|dict|caution|exist|historic|condition|judge|load)/u],
  ['dis', /^(?:dis)(?:like|agree|connect|approve|appear|allow|believe|comfort|honest|able|obey|qualify|regard)/u],
  ['mis', /^(?:mis)(?:take|read|write|lead|understand|spell|judge|use|place|inform|manage|pronounce|behave)/u],
  ['trans', /^(?:trans)(?:port|form|mit|lat|fer|atlantic|continental|national|cribe)/u],
];
const suffix = /(ization|ability|fulness|lessness|ation|sion|tion|ment|ness|able|ible|less|ful|ship|hood|ism|ist|ize|ify|ity|ous|ive|ance|ence|ent|ant|ate|ly)$/u;

function morphology(spelling, vocabulary) {
  const word = spelling.toLowerCase();
  const labels = roots.filter(([, pattern]) => pattern.test(word)).map(([name]) => name);
  for (const [prefix, pattern] of prefixes) {
    const base = word.slice(prefix.length);
    if (pattern.test(word) || (word.startsWith(prefix) && base.length > 2 && vocabulary.has(base))) {
      labels.push(prefix + '-');
    }
  }
  const ending = word.match(suffix)?.[0];
  if (ending) {
    const stem = word.slice(0, -ending.length);
    // A matching ending alone is not enough: family does not have an -ly suffix.
    const bases = [stem, stem + 'e', stem.replace(/i$/u, 'y')];
    if (bases.some(base => base.length >= 3 && vocabulary.has(base))) {
      labels.push(ending.endsWith('tion') ? '-tion' : '-' + ending);
    }
  }
  return new Set(labels);
}

export function suggestBranches(center, library, hasMeaning) {
  const vocabulary = new Set(library.map(word => word.word.toLowerCase()));
  const centerSenses = hasMeaning(center) ? senses(center) : new Set();
  const centerParts = morphology(center.word, vocabulary);
  const result = {meaning: [], affix: []};
  for (const word of library) {
    if (word.id === center.id) continue;
    if (centerSenses.size && hasMeaning(word)) {
      const shared = [...senses(word)].filter(sense => centerSenses.has(sense));
      if (shared.length) result.meaning.push({id: word.id, hints: shared});
    }
    if (centerParts.size) {
      const shared = [...morphology(word.word, vocabulary)].filter(part => centerParts.has(part));
      if (shared.length) result.affix.push({id: word.id, hints: shared});
    }
  }
  for (const [branch] of branches) result[branch].sort((a,b) => b.hints.length - a.hints.length);
  return result;
}

export function createWordTree({node, field, group, panel, button, content}) {
  let centerId;
  let centerQuery = '';
  const reset = () => { centerId = undefined; centerQuery = ''; };

  function show(owner, library, hasMeaning, speak) {
    if (!library.length) {
      const link = node('a', '打开单词本', 'chip');
      link.href = '#words';
      content.append(panel(null, node('p', '先在单词本添加单词，再回来建立词树。'), link));
      return;
    }
    const key = 'goals.word-tree.v1.' + owner;
    const words = new Map(library.map(word => [word.id, word]));
    const ordered = [...library].sort((a,b) => a.word.localeCompare(b.word, 'en'));
    const [centerLabel, filter] = field('搜索中心词', {
      value: centerQuery, type: 'search', placeholder: '英文或中文释义',
    });
    const select = node('select');
    select.setAttribute('aria-label', '中心词');
    const picker = group('word-tree-picker', centerLabel, select);
    const tree = group('stack');
    const status = node('p', '', 'muted');
    status.setAttribute('role', 'status');
    const option = (value, label) => Object.assign(node('option', label), {value});
    const loadChanges = center => {
      try { return JSON.parse(localStorage.getItem(key + '.' + center.id)) ?? {}; }
      catch { return {}; }
    };
    const tokens = word => word.word + ' ' + (hasMeaning(word) ? word.meaning : '');

    let shown = {};
    function updateTree() {
      const center = words.get(centerId);
      tree.replaceChildren();
      status.textContent = '';
      if (!center) return;
      const changes = loadChanges(center);
      const suggestions = suggestBranches(center, library, hasMeaning);
      const relations = {};
      for (const [kind] of branches) {
        const applied = changes[kind] ?? {};
        const automatic = suggestions[kind].filter(item => !applied.removed?.includes(item.id));
        const hints = new Map(suggestions[kind].map(item => [item.id, item.hints.join('、')]));
        relations[kind] = new Map();
        for (const id of applied.added ?? []) {
          if (id !== center.id && words.has(id)) relations[kind].set(id, hints.get(id) ?? '手动添加');
        }
        for (const {id} of automatic) relations[kind].set(id, hints.get(id));
      }
      function changeRelation(kind, id, add) {
        const current = loadChanges(center);
        const branch = current[kind] ?? {added: [], removed: []};
        const added = new Set(branch.added);
        const removed = new Set(branch.removed);
        if (add) { added.add(id); removed.delete(id); }
        else { added.delete(id); removed.add(id); }
        current[kind] = {added: [...added], removed: [...removed]};
        try {
          localStorage.setItem(key + '.' + center.id, JSON.stringify(current));
          updateTree();
          status.textContent = (add ? '已添加 ' : '已移除 ') + words.get(id).word;
          tree.querySelector('summary')?.focus({preventScroll:true});
        } catch {
          status.textContent = '浏览器无法保存这次调整。';
        }
      }

      const root = group('word-tree-root', node('strong', center.word),
        ...(hasMeaning(center) ? [node('span', center.meaning, 'muted')] : []));
      const cards = group('word-tree-branches', ...branches.map(([kind, title], branchIndex) => {
        const points = node('ul', null, 'word-tree-leaves');
        const limit = shown[kind] ?? 8;
        for (const [id, hint] of [...relations[kind]].slice(0, limit)) {
          const word = words.get(id);
          const leaf = node('li');
          const navigate = button(word.word, () => {
            centerId = id;
            shown = {};
            centerQuery = filter.value = '';
            updatePicker();
            select.focus();
          }, 'chip');
          const remove = button('移除', () => changeRelation(kind,id,false));
          remove.setAttribute('aria-label', '从' + title + '移除 ' + word.word);
          leaf.append(group('row', navigate, remove),
            ...(hasMeaning(word) ? [node('p', word.meaning)] : []),
            node('small', hint, 'muted'));
          points.append(leaf);
        }
        const more = button('显示更多关联词', () => {
          shown[kind] = limit + 12;
          updateTree();
          tree.querySelectorAll('.word-tree-branch')[branchIndex]?.querySelectorAll('li .chip')[limit]?.focus();
        });
        return group('word-tree-branch', node('h2', title),
          relations[kind].size ? points : node('p', '暂无关联词，可手动添加。', 'muted'),
          ...(relations[kind].size > limit ? [more] : []));
      }));
      const addControls = node('details', null, 'word-tree-edit');
      const kindSelect = node('select');
      kindSelect.setAttribute('aria-label', '要添加到的分支');
      kindSelect.append(...branches.map(([kind, name]) => option(kind, name)));
      const [wordLabel, search] = field('搜索要添加的词', {type:'search', placeholder:'英文或中文释义'});
      const wordSelect = node('select');
      wordSelect.setAttribute('aria-label','要添加的单词');
      const addWord = button('添加到分支', () => {
        if (wordSelect.value) changeRelation(kindSelect.value, wordSelect.value, true);
      }, 'primary');
      function refreshAddChoices() {
        const query = search.value.toLowerCase().trim();
        const candidates = ordered.filter(word => word.id !== center.id && !relations[kindSelect.value].has(word.id)
          && tokens(word).toLowerCase().includes(query)).slice(0, 40);
        wordSelect.replaceChildren(...(candidates.length ? candidates.map(word => option(word.id, word.word))
          : [option('', '没有可添加的词')]));
        addWord.disabled = !candidates.length;
      }
      kindSelect.addEventListener('change', refreshAddChoices);
      search.addEventListener('input', refreshAddChoices);
      refreshAddChoices();
      addControls.append(node('summary','手动添加关联词'),
        group('word-tree-edit-fields', wordLabel, kindSelect, wordSelect, addWord),
        node('p', '调整保存在当前浏览器。', 'muted'));
      root.append(button('朗读中心词', () => speak(center.word)));
      tree.append(group('word-tree-map', root, cards), addControls);
    }

    function updatePicker() {
      centerQuery = filter.value;
      const query = centerQuery.toLowerCase().trim();
      const matches = ordered.filter(word => tokens(word).toLowerCase().includes(query));
      const candidates = matches.slice(0, 40);
      const exact = matches.find(word => word.word.toLowerCase() === query);
      const current = exact ?? matches.find(word => word.id === centerId) ?? candidates[0];
      if (current && !candidates.includes(current)) candidates.unshift(current);
      if (centerId !== current?.id) shown = {};
      centerId = current?.id;
      select.replaceChildren(...(candidates.length ? candidates.map(word => option(word.id, word.word))
        : [option('', '没有匹配的单词')]));
      select.disabled = !current;
      select.value = centerId ?? '';
      updateTree();
    }
    select.addEventListener('change', () => { centerId = select.value; shown = {}; updateTree(); });
    filter.addEventListener('input', updatePicker);
    content.append(picker, tree, status);
    updatePicker();
  }

  return {show, reset};
}
