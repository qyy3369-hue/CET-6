const keyFor = word => word.trim().toLowerCase();
const hanOnly = text => text.replace(/[^\p{Script=Han}]/gu,'');
export function validateMnemonic(raw, meaning = '') {
  if (typeof raw !== 'string') return null;
  const hint = raw.trim();
  const length = [...hint].length;
  if (length < 5 || length > 54 || /[\n\r\u2028\u2029]/u.test(hint) ||
      !/[a-zA-Z]/u.test(hint) || !/\p{Script=Han}/u.test(hint) ||
      /就是|意思是|意为|引申为|即为|也就是|表示整个词|[，；：。]\s*即|[→=]/u.test(hint)) return null;

  const cue = hanOnly(hint);
  for (const definition of meaning.split(/[；;、，,。/]/u)) {
    const core = hanOnly(definition).replace(/的$/u,'');
    if (core.length >= 2 && cue.includes(core)) return null;
    if (core.length > 3 && /^[使让令]/u.test(core) && cue.includes(core.slice(1))) return null;
    if (core.length === 1 && hint.split(/[\s\p{P}]+/u).includes(core)) return null;
  }
  return hint;
}

export function createFlashcardMnemonics({ rpc, ai, enabled, owner, levelFor, meaningFor, node, button }) {
  let cache = new Map();
  const failures = new Map();
  let pending = false;
  let visible;
  let generation = 0;
  const verified = word => validateMnemonic(cache.get(keyFor(word.word)), meaningFor(word));

  async function load() {
    const current = generation;
    const account = owner();
    if (!account) return;
    const remote = await rpc('mnemonics',{});
    if (generation === current && owner() === account) {
      cache = new Map(Object.entries(remote));
      paint();
    }
  }

  function paint() {
    if (!visible?.element.isConnected) return;
    const { element, word } = visible;
    const hint = verified(word);
    const failure = failures.get(keyFor(word.word));
    element.replaceChildren();
    if (hint) element.append(node('span','助记  ' + hint,'flash-mnemonic-text'));
    else if (failure) {
      const retry = button('重试生成助记',() => {
        failures.delete(keyFor(word.word));
        paint();
        void prepare(true);
      });
      retry.disabled = pending;
      retry.title = failure;
      element.append(retry);
    } else if (enabled()) element.append(node('span','正在生成助记…'));
    element.hidden = !element.childElementCount;
  }

  async function prepare(preferScene = false) {
    if (pending || !enabled() || !visible?.element.isConnected || verified(visible.word) ||
        failures.has(keyFor(visible.word.word))) return;
    const initial = visible;
    const account = owner();
    const cycle = generation;
    if (!account) return;
    let requested = [initial.word];
    pending = true;
    paint();
    try {
      await load();
      if (cycle !== generation || owner() !== account || !initial.element.isConnected || verified(initial.word)) return;
      const candidates = preferScene ? [initial.word] : [initial.word,...initial.upcoming.slice(0,16)];
      const seen = new Set();
      requested = candidates.filter(word => {
        const id = keyFor(word.word);
        if (seen.has(id) || levelFor(word) > 4 || verified(word) || failures.has(id)) return false;
        seen.add(id);
        return true;
      }).slice(0,8);
      if (!requested.length) return;

      const words = new Map(requested.map(word=>[keyFor(word.word),word]));
      const inputs = requested.map(word=>({
        word:keyFor(word.word),meaning:meaningFor(word).slice(0,180),reference:(word.mnemonic ?? '').slice(0,180),
      }));
      const result = await ai('mnemonic_batch',JSON.stringify(inputs),{scene:preferScene});
      if (cycle !== generation || owner() !== account) return;
      const additions = Object.create(null);
      const expected = Object.create(null);
      for (const item of Array.isArray(result.entries) ? result.entries : []) {
        const key = typeof item?.word === 'string' ? keyFor(item.word) : '';
        if (!words.has(key) || Object.hasOwn(additions,key)) continue;
        const hint = validateMnemonic(item.hint,meaningFor(words.get(key)));
        if (!hint) continue;
        additions[key]=hint;
        if (cache.has(key)) expected[key]=cache.get(key);
      }
      if (Object.keys(additions).length) {
        const remote=await rpc('mnemonics',{additions,expected});
        if (cycle !== generation || owner() !== account) return;
        cache = new Map(Object.entries(remote));
      }
      for (const [key,word] of words) {
        if (!verified(word)) failures.set(key,'这条助记没有通过检查，可以重试。');
      }
    } catch (error) {
      if (cycle === generation) {
        for (const word of requested) failures.set(keyFor(word.word),error.message);
      }
    } finally {
      if (cycle === generation) {
        pending = false;
        paint();
        if (visible !== initial) void prepare();
      }
    }
  }

  function mount(element, word, upcoming) {
    visible = { element,word,upcoming };
    paint();
    void prepare();
  }

  function reset() {
    generation++;
    cache.clear();
    failures.clear();
    visible = null;
    pending = false;
  }

  return { load,mount,reset };
}
