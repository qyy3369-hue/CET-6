using System;
using System.Collections.Concurrent;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.Sqlite;

namespace Goals.Windows.Services;

/// <summary>
/// Runs a bundled OPUS-MT (Marian) ja→zh ONNX model on CPU to translate
/// Japanese dictionary definitions to Chinese, fully offline. Inference is
/// serialized and results are cached in memory and in a small SQLite database.
/// </summary>
public sealed class LocalTranslationService : IDisposable
{
    public static string ModelsDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "GoalsStudyDesk", "Models");

    private static readonly string CacheDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "GoalsStudyDesk");

    private static readonly string CacheDbPath = Path.Combine(CacheDirectory, "translation-cache.db");

    private readonly SemaphoreSlim _inferenceLock = new(1, 1);
    private readonly ConcurrentDictionary<string, string> _memoryCache = new(StringComparer.Ordinal);
    private OnnxSeq2SeqTranslator? _translator;

    public bool IsLoaded => _translator is not null;
    public string? ModelPath => ResolveModelDirectory();
    public string ModelName => "OPUS-MT ja→zh（本地 ONNX）";
    public string? LoadError { get; private set; }

    public long ModelSizeBytes
    {
        get
        {
            var directory = ResolveModelDirectory();
            if (directory is null) return 0;
            try
            {
                return Directory.EnumerateFiles(directory, "*.onnx").Sum(file => new FileInfo(file).Length);
            }
            catch { return 0; }
        }
    }

    public bool ModelFound => ResolveModelDirectory() is not null;

    /// <summary>
    /// True when the text contains kana (hiragana/katakana), i.e. a Japanese
    /// dictionary gloss a beginner would want translated. Pure Chinese text
    /// shares kanji with Japanese, so kana presence is required to distinguish.
    /// </summary>
    public static bool LooksLikeJapanese(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return false;
        var kana = 0;
        var cjk = 0;
        var latin = 0;
        foreach (var ch in text)
        {
            if (ch is >= '぀' and <= 'ヿ' or '々' or '〆' or '〇') kana++;
            else if (ch is >= '㐀' and <= '鿿') cjk++;
            else if (char.IsLetter(ch)) latin++;
        }
        if (kana == 0) return false;
        return latin <= (kana + cjk) * 2;
    }

    public async Task<string?> TranslateAsync(string text, CancellationToken cancellationToken = default)
    {
        var key = text?.Trim() ?? "";
        if (key.Length == 0) return null;
        if (_memoryCache.TryGetValue(key, out var hit)) return hit;
        var fromDisk = ReadFromCache(key);
        if (fromDisk is not null)
        {
            _memoryCache[key] = fromDisk;
            return fromDisk;
        }

        await _inferenceLock.WaitAsync(cancellationToken);
        try
        {
            if (!await EnsureLoadedAsync()) return null;
            var output = await Task.Run(() => _translator!.Translate(key), cancellationToken);
            if (string.IsNullOrWhiteSpace(output)) return null;
            var translated = output.Trim();
            // Small NMT models fail in two ways that must never reach the learner:
            // echoing Japanese back, or producing repetitive/looping pseudo-Chinese.
            if (ContainsKana(translated) || LooksDegenerate(translated)) return null;
            _memoryCache[key] = translated;
            WriteToCache(key, translated);
            return translated;
        }
        finally
        {
            _inferenceLock.Release();
        }
    }

    /// <summary>
    /// Detects degenerate NMT output: a few characters repeated in a loop
    /// ("油油油…" or "刷油后,再刷油,刷油后,再刷油…"). Serving that to a learner
    /// is worse than no translation, so it is treated as a failed result.
    /// </summary>
    private static bool LooksDegenerate(string text)
    {
        if (text.Length < 8) return false;
        if (text.Distinct().Count() <= 2) return true;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        for (var i = 0; i + 4 <= text.Length; i++)
        {
            if (!seen.Add(text.Substring(i, 4))) return true;
        }
        return false;
    }

    private async Task<bool> EnsureLoadedAsync()
    {
        if (_translator is not null) return true;

        var directory = ResolveModelDirectory();
        if (directory is null)
        {
            LoadError = "未找到本地翻译模型。请把 ONNX 模型放入 Models 文件夹，或运行 Scripts/fetch_translation_model.ps1。";
            return false;
        }

        try
        {
            _translator = await Task.Run(() => new OnnxSeq2SeqTranslator(directory));
            LoadError = null;
            return true;
        }
        catch (Exception ex)
        {
            LoadError = ex.Message;
            _translator = null;
            return false;
        }
    }

    private static string? ResolveModelDirectory()
    {
        foreach (var root in new[] { Path.Combine(AppContext.BaseDirectory, "Models"), ModelsDirectory })
        {
            try
            {
                if (File.Exists(Path.Combine(root, "encoder_model.onnx"))) return root;
                var subdirectory = Path.Combine(root, "opus-mt-ja-zh");
                if (File.Exists(Path.Combine(subdirectory, "encoder_model.onnx"))) return subdirectory;
            }
            catch { }
        }
        return null;
    }

    private static bool ContainsKana(string text) => text.Any(ch =>
        ch is >= '぀' and <= 'ヿ' or '々' or '〆' or '〇');

    private static SqliteConnection OpenCacheConnection()
    {
        Directory.CreateDirectory(CacheDirectory);
        var connection = new SqliteConnection($"Data Source={CacheDbPath}");
        connection.Open();
        using var command = connection.CreateCommand();
        command.CommandText =
            "CREATE TABLE IF NOT EXISTS translations (source_hash TEXT PRIMARY KEY, translated TEXT NOT NULL, created_ticks INTEGER NOT NULL)";
        command.ExecuteNonQuery();
        return connection;
    }

    private static string? ReadFromCache(string source)
    {
        try
        {
            using var connection = OpenCacheConnection();
            using var command = connection.CreateCommand();
            command.CommandText = "SELECT translated FROM translations WHERE source_hash = $hash LIMIT 1";
            command.Parameters.AddWithValue("$hash", KeyHash(source));
            return command.ExecuteScalar() as string;
        }
        catch { return null; }
    }

    private static void WriteToCache(string source, string translated)
    {
        try
        {
            using var connection = OpenCacheConnection();
            using var command = connection.CreateCommand();
            command.CommandText =
                "INSERT INTO translations (source_hash, translated, created_ticks) VALUES ($hash, $translated, $ticks) " +
                "ON CONFLICT(source_hash) DO UPDATE SET translated = $translated, created_ticks = $ticks";
            command.Parameters.AddWithValue("$hash", KeyHash(source));
            command.Parameters.AddWithValue("$translated", translated);
            command.Parameters.AddWithValue("$ticks", DateTime.UtcNow.Ticks);
            command.ExecuteNonQuery();
        }
        catch { }
    }

    private static string KeyHash(string value) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();

    public void Dispose()
    {
        _inferenceLock.Dispose();
        _translator?.Dispose();
        _translator = null;
    }
}
