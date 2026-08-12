using System.Net.Http.Headers;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.IO;
using Goals.Windows.Models;

namespace Goals.Windows.Services;

public sealed class DeepSeekService
{
    private static readonly Uri Endpoint = new("https://api.deepseek.com/chat/completions");
    private const string Model = "deepseek-v4-flash";
    private readonly WindowsCredentialStore _credentials;
    private readonly HttpClient _client = new() { Timeout = TimeSpan.FromSeconds(75) };
    private readonly JsonSerializerOptions _json = new() { PropertyNameCaseInsensitive = true };

    public DeepSeekService(WindowsCredentialStore credentials) => _credentials = credentials;
    public bool HasKey => _credentials.HasKey;
    public string ModelName => Model;
    public void SaveKey(string key) => _credentials.Save(key);
    public void DeleteKey() => _credentials.Delete();

    public async Task<string> TestAsync(CancellationToken cancellationToken = default)
    {
        var answer = await CallAsync("你是连接测试助手。", "只回复：连接成功", false, cancellationToken);
        return string.IsNullOrWhiteSpace(answer) ? "连接成功" : answer.Trim();
    }

    public async Task<AiPlanResult> GeneratePlanAsync(StudyTrack track, string background, CancellationToken cancellationToken = default)
    {
        var language = track.Mode switch
        {
            LearningMode.Japanese => "JLPT N4 日语",
            LearningMode.English => "CET-6 英语",
            _ => "自定义学习目标"
        };
        var system = "你是学习计划助理。只输出 JSON，不要 Markdown。格式：{\"summary\":\"计划摘要\",\"tasks\":[{\"dayOffset\":0,\"time\":\"19:30\",\"title\":\"具体任务\"}]}。dayOffset 从 0 开始，生成未来 7 天、每天 1 至 3 项可执行任务。";
        var text = await CallAsync(system, $"目标：{track.Title}\n类型：{language}\n重点：{track.Focus}\n用户背景：{background}", true, cancellationToken);
        return JsonSerializer.Deserialize<AiPlanResult>(CleanJson(text), _json) ?? throw new InvalidDataException("计划返回内容无法解析。");
    }

    public async Task<VocabularyWord> LookupWordAsync(StudyTrack track, string input, CancellationToken cancellationToken = default)
    {
        var japanese = track.Mode == LearningMode.Japanese;
        var schema = japanese
            ? "{\"word\":\"経験\",\"reading\":\"けいけん\",\"romanization\":\"keiken\",\"partOfSpeech\":\"名词/サ变\",\"meaning\":\"经验；经历\",\"example\":\"自然日语例句\",\"exampleTranslation\":\"中文翻译\",\"phrases\":[\"常用搭配\"],\"mnemonic\":\"中文助记\",\"tag\":\"N4 重点\",\"difficulty\":3}"
            : "{\"word\":\"allocate\",\"phonetic\":\"/ˈæləkeɪt/\",\"partOfSpeech\":\"v.\",\"meaning\":\"分配；拨出\",\"example\":\"自然英文例句\",\"exampleTranslation\":\"中文翻译\",\"phrases\":[\"常用搭配\"],\"mnemonic\":\"中文助记\",\"tag\":\"写作高频\",\"difficulty\":3}";
        var system = $"你是{(japanese ? "JLPT N4 日语" : "CET-6 英语")}词条助手。只输出 JSON，不要 Markdown。格式：{schema}";
        var text = await CallAsync(system, "补全词条：" + input.Trim(), true, cancellationToken);
        var word = JsonSerializer.Deserialize<VocabularyWord>(CleanJson(text), _json) ?? throw new InvalidDataException("词条返回内容无法解析。");
        word.Id = (japanese ? "ja-" : "en-") + Guid.NewGuid().ToString("N");
        word.TrackId = track.Id;
        word.Difficulty = Math.Clamp(word.Difficulty, 1, 5);
        return word;
    }

    public async Task<VocabularyWord> GenerateRandomWordAsync(StudyTrack track, string level, IReadOnlySet<string>? existingWords = null, CancellationToken cancellationToken = default)
    {
        var targetLevel = level is "CET-4" or "CET4" ? "CET-4" : "CET-6";
        var schema = "{\"word\":\"allocate\",\"phonetic\":\"/ˈæləkeɪt/\",\"partOfSpeech\":\"v.\",\"meaning\":\"分配；拨出\",\"example\":\"自然英文例句\",\"exampleTranslation\":\"中文翻译\",\"phrases\":[\"常用搭配\"],\"mnemonic\":\"中文助记\",\"tag\":\"写作高频\",\"difficulty\":3}";
        var system = $"你是 {targetLevel} 英语词汇生成助手。随机生成一个 {targetLevel} 考试常考核心词汇的完整词条。只输出 JSON，不要 Markdown。格式：{schema}";
        var excludeText = existingWords is not null && existingWords.Count > 0
            ? $"。不要生成以下已有词汇：{string.Join(", ", existingWords.Take(80))}"
            : "";
        var text = await CallAsync(system, $"随机生成一个 {targetLevel} 词汇" + excludeText, true, cancellationToken);
        var word = JsonSerializer.Deserialize<VocabularyWord>(CleanJson(text), _json) ?? throw new InvalidDataException("词条返回内容无法解析。");
        word.Id = "lib-" + Guid.NewGuid().ToString("N");
        word.TrackId = track.Id;
        if (string.IsNullOrWhiteSpace(word.Tag)) word.Tag = targetLevel;
        word.Difficulty = Math.Clamp(word.Difficulty, 1, 5);
        return word;
    }

    public async Task<bool> JudgeAnswerAsync(VocabularyWord word, string answer, CancellationToken cancellationToken = default)
    {
        var system = "判断学习者给出的中文含义是否命中词条释义中的任意核心义项。只输出 JSON：{\"correct\":true}。允许近义词，不因附加无关词语直接判错。";
        var text = await CallAsync(system, $"词条：{word.Word}\n标准释义：{word.Meaning}\n用户回答：{answer}", true, cancellationToken);
        using var document = JsonDocument.Parse(CleanJson(text));
        return document.RootElement.TryGetProperty("correct", out var correct) && correct.GetBoolean();
    }

    public Task<string> TranslateAsync(string input, CancellationToken cancellationToken = default) =>
        CallAsync("你是 CET-6 翻译训练助手。输入中文时给出稳妥版与高分版英文翻译；输入英文时给出中文解释和润色建议。用清晰的中文分段回答。", input, false, cancellationToken);

    public Task<string> TranslateJapaneseSelectionAsync(string input, CancellationToken cancellationToken = default) =>
        CallAsync("你是日语学习词典助手。把用户选中的日文翻译成简明、自然的中文；必要时补充一个关键语法或词义说明。只输出翻译和必要说明，不要寒暄、不要 Markdown。", input, false, cancellationToken);

    public Task<string> WriteEssayAsync(string input, CancellationToken cancellationToken = default) =>
        CallAsync("你是 CET-6 写作训练助手。根据题目生成 150-200 词英文范文，并在后面用中文列出结构和三条高分表达。", input, false, cancellationToken);

    private async Task<string> CallAsync(string system, string user, bool jsonMode, CancellationToken cancellationToken)
    {
        var key = _credentials.Read();
        if (string.IsNullOrWhiteSpace(key)) throw new InvalidOperationException("尚未配置 DeepSeek 密钥，请先前往“设置”。");

        var body = new Dictionary<string, object?>
        {
            ["model"] = Model,
            ["messages"] = new[]
            {
                new { role = "system", content = system },
                new { role = "user", content = user }
            },
            ["temperature"] = 0.4,
            ["thinking"] = new { type = "disabled" },
            ["max_tokens"] = 1600
        };
        if (jsonMode) body["response_format"] = new { type = "json_object" };

        using var request = new HttpRequestMessage(HttpMethod.Post, Endpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", key);
        request.Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json");
        using var response = await _client.SendAsync(request, cancellationToken);
        var payload = await response.Content.ReadAsStringAsync(cancellationToken);
        if (!response.IsSuccessStatusCode)
            throw new InvalidOperationException($"DeepSeek 请求失败（{(int)response.StatusCode}）：{ReadApiError(payload)}");

        using var document = JsonDocument.Parse(payload);
        var content = document.RootElement.GetProperty("choices")[0].GetProperty("message").GetProperty("content").GetString();
        return content ?? throw new InvalidDataException("DeepSeek 没有返回内容。");
    }

    private static string ReadApiError(string payload)
    {
        try
        {
            using var document = JsonDocument.Parse(payload);
            return document.RootElement.GetProperty("error").GetProperty("message").GetString() ?? "未知错误";
        }
        catch { return payload.Length > 180 ? payload[..180] : payload; }
    }

    private static string CleanJson(string text)
    {
        var value = text.Trim();
        if (value.StartsWith("```"))
        {
            var firstBreak = value.IndexOf('\n');
            if (firstBreak >= 0) value = value[(firstBreak + 1)..];
            if (value.EndsWith("```")) value = value[..^3];
        }
        return value.Trim();
    }
}
