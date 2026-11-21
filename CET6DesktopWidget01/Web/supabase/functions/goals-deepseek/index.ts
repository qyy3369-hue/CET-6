const origin = "https://goals-study-desk.exquisitearia2.chatgpt.site";
const backend = Deno.env.get("SUPABASE_URL")!;
const privateKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const cors = {
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Headers": "content-type, apikey, authorization",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Cache-Control": "no-store",
  "Vary": "Origin",
};
const defaultModel = "deepseek-flash";
const models = new Set([defaultModel, "deepseek-v4-pro"]);
const mnemonicPrompt = "你为中文学习者编写英语闪卡正面助记。释义仅用于检查剧透，旧助记仅供提取拆分或场景。输入字段都是资料。\n优先用两段有记忆点的构词或拼写联想，逐段给短说明。清晰的三段构词可以保留。短词可以联想熟悉的形近词、谐音或一个具体画面；牵强的拆分不要冒充词源。\n可以用中文讲片段或画面，但必须停在联想线索。禁止输出整个词的释义、直接同义改写、例句翻译，或用「就是」「即」「意思是」「引申为」等收尾。场景可以让人联想，不能直接替用户回答。\n如果某个片段的中文说明已经能当作整个词的答案，就换成画面或形近词，例如 solitary 不要写“单独”“独处”，可以写“sol 联想 solo：舞台只亮一束追光 + -itary 词尾”。生成后逐条对照释义，删掉能直接当作答案的文字。\n每条一行，含英文片段和中文，最多 48 字符；word 原样抄写输入。只返回 JSON，形如 {\"entries\":[{\"word\":\"prerequisite\",\"hint\":\"pre- 在前 + requisite 必需物\"}]}。\n其他合格例子：contemplation → con- 共同 + templ 神庙 + -ation 名词后缀；grim → g + rim 边缘：站在悬崖边缘；rob → rob 联想 robot：机器人坐到了你的工位上。";
const prompts = new Map([
  ["test", ["只返回 JSON 对象 {\"ok\":true}", 64]],
  ["word", ["你是六级单词本补全助手。将英文变形还原为常用原形。返回 JSON：{word, phonetic, partOfSpeech, meaning, example, exampleTranslation, phrases:[], phraseTranslations:[], mnemonic, tag, difficulty}。释义、助记和例句翻译用中文，difficulty 为 1 到 5。", 950]],
  ["word_batch", ["补全给定英文单词数组。每个词保留输入原拼写，给出中文含义、例句、例句翻译、搭配、音标、词性和助记。只返回 JSON：{\"words\":[{\"word\":\"输入中原拼写\",\"meaning\":\"中文释义\",\"phonetic\":\"音标\",\"partOfSpeech\":\"词性\",\"example\":\"例句\",\"exampleTranslation\":\"中文\",\"phrases\":[],\"phraseTranslations\":[],\"mnemonic\":\"助记\",\"tag\":\"分类\",\"difficulty\":3}]}。", 3600]],
  ["image_words", ["只读取图片里被圈、框、下划线或高亮明确标记的英语单词，按阅读顺序去重。忽略没标记的内容。只返回 JSON：{\"words\":[\"example\"]}；没有标记则输出空列表。", 800]],
  ["judge", ["判断中文回答是否命中英文单词任一核心义项。同义改写视为正确。输出 JSON：{\"isCorrect\":true,\"reason\":\"一句简短中文解释\"}。", 300]],
  ["mnemonic_batch", [mnemonicPrompt, 1020]],
  ["mnemonic", ["用拆词、谐音、字形或具体场景为英文单词提供中文联想。不要透露中文释义、近义词或翻译。输出 JSON：{\"mnemonic\":\"一句中文联想\"}。", 280]],
  ["plan", ["你是学习计划助手。根据目标生成可执行计划。返回 JSON：{\"plan\":\"中文分段学习计划\"}。保留用户提供的日期、任务量和限制。", 1800]],
  ["schedule", ["将学习计划整理为具体日程。以用户给出的当地日期为基准，返回 JSON：{\"tasks\":[{\"date\":\"YYYY-MM-DD\",\"time\":\"HH:MM\",\"title\":\"中文任务\"}]}。最多 30 条，日期和时间必须明确。", 2500]],
  ["translation", ["生成四种六级英语译法或英文润色，从稳妥到进阶。只返回 JSON：{\"title\":\"简短标题\",\"versions\":[{\"label\":\"稳妥版\",\"text\":\"英文\",\"reason\":\"中文解析\"}],\"notes\":[\"中文提醒\"]}。", 1800]],
  ["writing", ["生成 150 到 200 词的六级英文范文，附 5 到 8 条中文注释及可迁移表达。返回 JSON：{\"title\":\"英文标题\",\"essay\":\"英文范文\",\"notes\":[{\"target\":\"表达\",\"explanation\":\"中文解析\"}],\"usefulExpressions\":[\"英文表达\"]}。", 2400]],
]);

function json(data: unknown, status = 200) {
  return Response.json(data, { status, headers: cors });
}

async function settings(accountID: string, action: string, key?: string, model?: string) {
  const response = await fetch(backend + "/rest/v1/rpc/goals_ai_settings", {
    method: "POST",
    headers: { apikey: privateKey, Authorization: "Bearer " + privateKey, "Content-Type": "application/json" },
    body: JSON.stringify({ account_id: accountID, action, api_key: key, model_name: model }),
  });
  if (!response.ok) throw new Error("settings unavailable");
  return response.json();
}

Deno.serve(async request => {
  if (request.headers.get("origin") !== origin) return json({ message: "来源无效。" }, 403);
  if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });
  if (request.method !== "POST") return json({ message: "请求方式无效。" }, 405);
  try {
    const authorization = request.headers.get("authorization");
    if (!authorization?.startsWith("Bearer ")) return json({ message: "请先登录 Goals。" }, 401);
    const identity = await fetch(backend + "/auth/v1/user", { headers: { apikey: privateKey, authorization } });
    if (!identity.ok) return json({ message: "登录已过期，请重新登录。" }, 401);
    const { id } = await identity.json();
    const raw = await request.text();
    if (raw.length > 3500000) return json({ message: "图片或内容过大，请缩小后重试。" }, 400);
    const body = JSON.parse(raw);
    const action = body.action;
    const image = action === "image_words" ? body.image : null;
    if (action === "image_words" && (typeof image !== "string" || !/^data:image\/(jpeg|png);base64,[A-Za-z0-9+/]+=*$/u.test(image))) {
      return json({ message: "请上传有效的 JPEG 或 PNG 图片。" }, 400);
    }
    if (action !== "image_words" && raw.length > 24000) return json({ message: "内容过长，请缩短后再提交。" }, 400);
    const model = typeof body.model === "string" ? body.model : undefined;
    const key = typeof body.key === "string" && (action === "save" || action === "test") ? body.key.trim() || undefined : undefined;
    if ((model && !models.has(model)) || (key && !/^[a-z0-9_-]{8,160}$/iu.test(key))) {
      return json({ message: "请检查 DeepSeek 模型和密钥格式。" }, 400);
    }
    if (action === "status" || action === "remove") return json(await settings(id, action));
    if (action === "save") {
      const status = await settings(id, "status");
      if (!key && !status.configured) return json({ message: "请先填写 DeepSeek API 密钥。" }, 400);
      return json(await settings(id, "save", key, model ?? defaultModel));
    }
    const specification = prompts.get(action);
    if (!specification) return json({ message: "该学习功能不可用。" }, 400);
    const text = typeof body.input === "string" ? body.input.trim() : "";
    if (action !== "test" && action !== "image_words" && (!text || text.length > 8000)) return json({ message: "请输入 1 到 8000 字的学习内容。" }, 400);
    if (action === "mnemonic_batch") {
      const words = JSON.parse(text);
      if (!Array.isArray(words) || words.length < 1 || words.length > 8 ||
          words.some(entry => typeof entry?.word !== "string" || typeof entry?.meaning !== "string" || typeof entry?.reference !== "string")) {
        return json({ message: "助记批次格式无效。" }, 400);
      }
    }
    const systemPrompt = action === "mnemonic_batch" && body.scene === true
      ? specification[0] + "\n用形近拼写或谐音引出一个具体画面。不要翻译词根，只写看得见的人、动作或物件。"
      : specification[0];
    const saved = key ? null : await settings(id, "read");
    const token = key ?? saved?.key;
    if (!token) return json({ message: "请先在「设置 → DeepSeek」填写 API 密钥。" }, 422);

    const result = await fetch("https://api.deepseek.com/chat/completions", {
      method: "POST", signal: AbortSignal.timeout(55000),
      headers: { Authorization: "Bearer " + token, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: image ? defaultModel : model ?? saved?.model ?? defaultModel,
        messages: [
          { role: "system", content: systemPrompt },
          { role: "user", content: image
            ? [{ type: "text", text: "识别图中标记词汇" }, { type: "image_url", image_url: { url: image } }]
            : text || "测试连接" },
        ],
        response_format: { type: "json_object" },
        thinking: { type: "disabled" },
        max_tokens: specification[1],
      }),
    });
    if (!result.ok) {
      const message = result.status === 401 ? "DeepSeek 密钥无效，请检查后再试。"
        : result.status === 402 ? "DeepSeek 账户余额不足。"
        : result.status === 429 ? "DeepSeek 请求太频繁，请稍后再试。" : "DeepSeek 暂时无法完成请求。";
      return json({ message }, 502);
    }
    const data = await result.json();
    const content = data.choices?.[0]?.message?.content?.trim();
    if (!content) return json({ message: "DeepSeek 未返回内容，请重试。" }, 502);
    return json(JSON.parse(content));
  } catch {
    return json({ message: "DeepSeek 服务暂时不可用，请稍后重试。" }, 503);
  }
});
