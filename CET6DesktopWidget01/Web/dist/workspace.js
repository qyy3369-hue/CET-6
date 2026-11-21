export function createWorkspace(ui) {
  const { node, field, group, panel, button, form, run, rpc, ai, content, header, notice, render } = ui;
  let records = [];
  let loaded = false;
  let selectedGoal = null;
  let selectedPlan = null;
  let newGoal = false;
  let planMode = 'manual';
  let selectedDate = today();
  let deepseek = null;

  function today() {
    return new Intl.DateTimeFormat('sv-SE', { timeZone: 'Asia/Shanghai' }).format(new Date());
  }

  function type(kind) { return records.filter(item => item.kind === kind); }

  async function load() {
    records = await rpc('workspace', { action: 'list' });
    loaded = true;
    refreshSidebar();
  }

  async function save(kind, value, id = crypto.randomUUID()) {
    records = await rpc('workspace', { action: 'save', record_kind: kind, record_id: id, payload: value });
    refreshSidebar();
    return id;
  }

  async function remove(record) {
    if (!window.confirm('删除这条记录？')) return;
    records = await rpc('workspace', { action: 'remove', record_id: record.id });
    refreshSidebar();
  }

  function reset() {
    records = [];
    loaded = false;
    selectedGoal = selectedPlan = null;
    newGoal = false;
    deepseek = null;
    selectedDate = today();
    refreshSidebar();
  }

  function refreshSidebar() {
    const goal = type('goal').find(item => item.id === selectedGoal) ?? type('goal')[0];
    document.querySelector('#goal-caption').textContent = goal?.value.title ?? '暂无目标';
    const tasks = type('task').filter(item => item.value.date === today());
    const done = tasks.filter(item => item.value.done).length;
    document.querySelector('#today-progress span:last-child').textContent = done + ' / ' + tasks.length;
    const meter = document.querySelector('#today-meter');
    meter.max = tasks.length || 1;
    meter.value = done;
  }

  function editor(label, initial, placeholder, required = true) {
    const wrapper = node('label', label);
    const input = node('textarea');
    input.required = required;
    input.maxLength = 8000;
    input.value = initial;
    input.placeholder = placeholder;
    wrapper.append(input);
    return [wrapper, input];
  }

  function picker(label, items, current, apply) {
    const wrapper = node('label', label);
    const select = node('select');
    for (const [value, text] of items) {
      const option = node('option', text);
      option.value = value;
      select.append(option);
    }
    select.value = current;
    select.addEventListener('change', () => apply(select.value));
    wrapper.append(select);
    return wrapper;
  }

  function tabs(options, current, apply, label) {
    const bar = group('segmented', ...options.map(([value, text]) => {
      const choice = button(text, () => apply(value));
      choice.setAttribute('aria-pressed', String(value === current));
      return choice;
    }));
    bar.setAttribute('role', 'group');
    bar.setAttribute('aria-label', label);
    return bar;
  }

  function compactDate(record) {
    return new Intl.DateTimeFormat('zh-CN', { dateStyle: 'medium', timeZone: 'Asia/Shanghai' })
      .format(new Date(record.updated_at));
  }

  function goalCard(goal) {
    const [label, title] = field('目标名称', { value: goal.value.title, required: true, maxLength: 80 });
    const [focusLabel, focus] = editor('学习重点', goal.value.focus ?? '', '例如：六级词汇与写作', false);
    const plans = type('plan').filter(plan => plan.value.goal === goal.id);
    return panel(null, node('h2', goal.value.title), node('p', goal.value.focus, 'muted'),
      group('controls', button('查看计划书 · ' + plans.length, () => {
        selectedGoal = goal.id; selectedPlan = null; location.hash = 'plans';
      })),
      disclosure('编辑目标', form([label, focusLabel], '保存修改', async () => {
        if (!title.value.trim()) throw new Error('请输入目标名称。');
        await save('goal', { title: title.value.trim(), focus: focus.value.trim() }, goal.id);
      })));
  }

  function disclosure(label, child) {
    const details = node('details');
    details.append(node('summary', label), child);
    return details;
  }

  function goalsView() {
    header.append(button('新建目标', () => { newGoal = !newGoal; render(); }, 'primary'));
    if (newGoal || !type('goal').length) {
      const [label, name] = field('目标名称', { required: true, maxLength: 80, placeholder: '例如：CET-6 备考' });
      const [focusLabel, focus] = editor('学习重点', '', '写下你希望提高的能力', false);
      content.append(panel(type('goal').length ? '新建目标' : '创建你的第一个学习目标',
        form([label, focusLabel], '创建目标', async () => {
          if (!name.value.trim()) throw new Error('请输入目标名称。');
          selectedGoal = await save('goal', { title: name.value.trim(), focus: focus.value.trim() });
          newGoal = false;
          refreshSidebar();
        })));
    }
    const cards = type('goal').map(goalCard);
    if (cards.length) content.append(group('responsive-grid', ...cards));
  }

  function plansView() {
    const goals = type('goal');
    if (!goals.length) {
      content.append(panel('还没有学习目标', button('去创建目标', () => { location.hash = 'goals'; }, 'primary')));
      return;
    }
    const goal = goals.find(item => item.id === selectedGoal) ?? goals[0];
    selectedGoal = goal.id;
    const plans = type('plan').filter(item => item.value.goal === goal.id);
    const active = plans.find(item => item.id === selectedPlan) ?? plans[0];
    header.append(picker('学习目标', goals.map(item => [item.id,item.value.title]), goal.id, value => {
      selectedGoal = value; selectedPlan = null; refreshSidebar(); render();
    }));
    content.append(tabs([['manual','计划编辑'],['ai','AI 制定计划']], planMode,
      value => { planMode = value; render(); }, '计划编辑方式'));
    if (planMode === 'ai') {
      const [label, prompt] = editor('目标和学习安排', goal.value.focus ?? '', '填写考试日期、每天可用时间和薄弱项');
      content.append(panel('AI 制定计划', form([label], '生成并保存计划', async () => {
        const result = await ai('plan', goal.value.title + '\n' + prompt.value.trim());
        if (typeof result.plan !== 'string' || !result.plan.trim()) throw new Error('DeepSeek 未生成可用计划。');
        selectedPlan = await save('plan', { goal: goal.id, title: 'AI 学习计划', text: result.plan });
        planMode = 'manual';
      })));
      return;
    }

    const [titleLabel, title] = field('计划名称', { value: active?.value.title ?? '学习计划', required: true, maxLength: 80 });
    const [textLabel, text] = editor('计划内容', active?.value.text ?? '', '输入学习计划，或从 AI 制定计划开始');
    const savePlan = async () => {
      if (!title.value.trim() || !text.value.trim()) throw new Error('请输入计划名称和内容。');
      selectedPlan = await save('plan', { goal: goal.id, title: title.value.trim(), text: text.value.trim() }, active?.id);
    };
    const list = group('controls', ...plans.map(item => button(item.value.title, () => {
      selectedPlan = item.id; render();
    }, item.id === active?.id ? 'primary' : '')), button('添加计划书', () => run(async () => {
      selectedPlan = await save('plan', { goal: goal.id, title: '计划书 ' + (plans.length + 1), text: '' });
    })));
    content.append(panel('计划书', list, form([titleLabel, textLabel], '保存计划', savePlan),
      group('controls', button('用 DeepSeek 生成日程', () => run(async () => {
        if (!text.value.trim()) throw new Error('请先填写计划内容。');
        const result = await ai('schedule', '当地日期：' + today() + '\n' + text.value.trim());
        const tasks = Array.isArray(result.tasks) ? result.tasks.filter(task => task &&
          /^\d{4}-\d{2}-\d{2}$/u.test(task.date) && /^(?:[01]\d|2[0-3]):[0-5]\d$/u.test(task.time) &&
          typeof task.title === 'string' && task.title.trim()).slice(0,30) : [];
        if (!tasks.length) throw new Error('DeepSeek 未生成带有日期和时间的任务。');
        await savePlan();
        const exists = new Set(type('task').map(item => [item.value.date,item.value.time,item.value.title].join('|')));
        for (const task of tasks) {
          const key = [task.date,task.time,task.title].join('|');
          if (exists.has(key)) continue;
          await save('task', { date: task.date, time: task.time, title: task.title.trim().slice(0,180), done: false, goal: goal.id });
          exists.add(key);
        }
        notice.textContent = '日程已保存，可在「今日日程」查看。';
      })), ...(active ? [button('删除计划', () => run(() => remove(active)), 'danger')] : []))));
  }

  function todayView() {
    const [dateFilterLabel, dateFilter] = field('查看日期', { type: 'date', value: selectedDate });
    dateFilter.addEventListener('change', () => { if (dateFilter.value) selectedDate = dateFilter.value; render(); });
    header.append(dateFilterLabel);
    const [taskLabel, title] = field('学习任务', { required: true, maxLength: 180, placeholder: '例如：复习 20 张闪卡' });
    const [timeLabel, time] = field('时间', { type: 'time', value: '08:00', required: true });
    const tasks = type('task').filter(item => item.value.date === selectedDate)
      .sort((a,b) => a.value.time.localeCompare(b.value.time));
    const list = group('list', ...tasks.map(item => {
      const check = node('input');
      check.type = 'checkbox';
      check.checked = item.value.done;
      check.addEventListener('change', () => run(async () => {
        const next = check.checked;
        check.disabled = true;
        try { await save('task', { ...item.value, done: next }, item.id); }
        catch (error) { check.checked = !next; throw error; }
        finally { check.disabled = false; }
      }));
      const label = node('label', null, 'task-toggle');
      label.append(check,node('span', item.value.time + '  ' + item.value.title));
      return group('row', label, button('删除', () => run(() => remove(item)), 'danger'));
    }));
    content.append(panel(selectedDate, tasks.length ? list : node('p', '这一天还没有学习任务。', 'muted')),
      panel('添加任务', form([group('form-grid', taskLabel, timeLabel)], '添加任务', async () => {
        if (!title.value.trim()) throw new Error('请输入学习任务。');
        await save('task', { title: title.value.trim(), time: time.value, date: selectedDate, done: false });
      })));
  }

  function practice(kind) {
    const writing = kind === 'writing';
    const [label, input] = editor(writing ? '写作主题或真题' : '中文原句或英文草稿', '',
      writing ? '输入题目、主题或写作要求' : '输入中文获得多个译法，输入英文获得润色版本');
    content.append(panel(writing ? '六级写作' : '六级翻译',
      form([label], writing ? '生成范文' : '生成译法', async () => {
        if (!input.value.trim()) throw new Error('请先填写学习内容。');
        const result = await ai(kind, input.value.trim());
        if (writing ? typeof result.essay !== 'string' || !result.essay.trim() : !Array.isArray(result.versions) || !result.versions.length) {
          throw new Error('DeepSeek 返回的内容不完整，请重试。');
        }
        await save(kind, { input: input.value.trim(), result });
      })));
    for (const record of type(kind)) {
      const {input: original,result} = record.value;
      const array = value => Array.isArray(value) ? value : [];
      const parts = writing ? [
        node('p', result.essay, 'prose'),
        node('p', (result.essay.match(/[A-Za-z]+(?:['’-][A-Za-z]+)*/gu) ?? []).length + ' 词', 'muted'),
        ...array(result.notes).filter(item => item?.target).map(item => group('list', node('strong', item.target), node('p', item.explanation, 'muted'))),
        ...array(result.usefulExpressions).map(item => node('p', item, 'chip')),
      ] : [
        ...array(result.versions).filter(item => item?.text).map(item => group('list', node('strong', item.label),
          node('p', item.text, 'prose'), node('p', item.reason, 'muted'))),
        ...array(result.notes).map(item => node('p', item, 'muted')),
      ];
      content.append(panel(result.title || original,
        group('row', node('p', compactDate(record), 'muted'), button('删除记录', () => run(() => remove(record)), 'danger')),
        node('p', original, 'muted prose'), ...parts));
    }
  }

  const roots = [
    ['spect','看','inspect 检查、spectator 观众、perspective 视角'],
    ['tract','拉、牵引','attract 吸引、extract 提取、distract 分散注意'],
    ['struct','建造','construct 建造、structure 结构、instruct 指导'],
    ['port','携带、运送','import 进口、export 出口、portable 便携的'],
    ['scrib / script','写','describe 描述、subscribe 订阅、manuscript 手稿'],
    ['form','形状、形成','transform 转变、reform 改革、uniform 一致的'],
    ['dict','说','predict 预测、dictate 口述、contradict 反驳'],
    ['ject','投、抛','project 投射、reject 拒绝、inject 注入'],
    ['mit / miss','送、发','transmit 传输、admit 承认、mission 任务'],
    ['ced / cess','行进、让步','proceed 继续、access 进入、recede 后退'],
    ['trans-','跨越、转变','transport 运输、transform 转变、translate 翻译'],
    ['pre-','在……之前','preview 预览、predict 预测、precaution 预防措施'],
    ['-able','能够……的','adaptable 适应性强的、reliable 可靠的、portable 便携的'],
    ['-tion','动作、过程或结果','translation 翻译、construction 建造、participation 参与'],
  ];

  function rootsView() {
    const [label, search] = field('搜索词根、词缀或例词', { type: 'search' });
    const list = group('responsive-grid');
    const update = () => {
      const query = search.value.trim().toLowerCase();
      const matches = roots.filter(item => item.join(' ').toLowerCase().includes(query));
      list.replaceChildren(...matches.map(([name, meaning, words]) => panel(name,
        node('strong', meaning), node('p', words, 'muted'))));
      if (!matches.length) list.append(node('p', '没有匹配的词根或词缀。', 'muted'));
    };
    search.addEventListener('input', update);
    update();
    content.append(label, list);
  }

  function aiSettings() {
    const status = deepseek;
    if (!status) {
      return panel('DeepSeek API', button('加载配置', () => run(loadDeepSeek)));
    }
    const [keyLabel, key] = field(status.configured ? 'API 密钥（留空保留现有密钥）' : 'API 密钥', {
      type: 'password', maxLength: 160, autocomplete: 'off', placeholder: status.configured ? '已保存' : 'sk-…',
    });
    let model = status.model ?? 'deepseek-flash';
    const modelField = picker('模型', [['deepseek-flash','deepseek-flash'],['deepseek-v4-pro','deepseek-v4-pro']], model,
      value => { model = value; });
    const test = button('测试连接', () => run(async () => {
      const result = await ai('test', undefined, { key: key.value.trim(), model });
      if (result.ok !== true) throw new Error('DeepSeek 有响应，但未返回预期结果。');
      notice.textContent = 'DeepSeek 连接成功。';
    }, test));
    const body = form([keyLabel, modelField,
      node('p', '用自己的 API 密钥。保存后密钥加密存储，仅用于该账号的 DeepSeek 请求。', 'muted')],
      '保存 DeepSeek 配置', async () => {
        deepseek = await ai('save', undefined, { key: key.value.trim(), model });
        key.value = '';
        notice.textContent = 'DeepSeek 配置已保存。';
      });
    body.append(group('controls', test, ...(status.configured ? [button('移除密钥', () => run(async () => {
      if (!window.confirm('移除 DeepSeek 密钥？')) return;
      deepseek = await ai('remove');
    }), 'danger')] : [])));
    return panel('DeepSeek API', body);
  }

  async function loadDeepSeek() { deepseek = await ai('status'); }

  function show(page) {
    if (page === 'roots') { rootsView(); return; }
    if (!loaded) {
      content.append(panel('读取学习工作区', button('加载记录', () => run(load))));
      return;
    }
    if (page === 'goals') goalsView();
    if (page === 'plans') plansView();
    if (page === 'today') todayView();
    if (page === 'translation' || page === 'writing') practice(page);
  }

  return { load, reset, show, aiSettings, loadDeepSeek, tabs, aiConfigured: () => deepseek?.configured };
}
