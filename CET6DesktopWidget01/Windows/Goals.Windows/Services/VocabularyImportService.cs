using System.Collections.ObjectModel;
using System.IO;
using System.Net;
using System.Reflection;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Goals.Windows.Models;
using MDict.Csharp.Models;

namespace Goals.Windows.Services;

public sealed record VocabularyImportPreview(
    IReadOnlyList<VocabularyWord> Words,
    int Skipped,
    string SourceName,
    string Detail);

public sealed record WordImportProgress(string Message, long Processed, int Total, int Added);
public sealed record WordImportResult(
    string SourceName,
    int Added,
    int Duplicates,
    int Skipped,
    long Processed,
    bool Resumed,
    bool AlreadyComplete);

public sealed class VocabularyImportService
{
    public const int MaxImportEntries = 10_000;
    public const int ImportBatchSize = 1_000;
    private static readonly string[] WordNames = ["word", "headword", "term", "title", "词语", "单词"];
    private static readonly string[] MeaningNames = ["meaning", "definition", "translation", "gloss", "释义", "意思", "翻译"];
    private static readonly string[] WrapperNames = ["words", "vocabulary", "entries", "items", "data", "词条", "单词"];

    public Task<VocabularyImportPreview> ReadAsync(string filePath, StudyTrack track, IProgress<string>? progress = null)
    {
        return Task.Run(() =>
        {
            var extension = Path.GetExtension(filePath).ToLowerInvariant();
            return extension switch
            {
                ".json" => ParseJson(File.ReadAllText(filePath), track, Path.GetFileName(filePath)),
                ".mdx" => ParseMdx(filePath, track, null, progress),
                ".mdd" => ParseMdd(filePath, track, progress),
                ".css" => ParseCss(filePath, track, progress),
                _ => throw new NotSupportedException("请选择 JSON、MDX、MDD 或 CSS 格式的词书文件。")
            };
        });
    }

    /// <summary>
    /// Imports a full wordbook into the disk-backed library in small transactions.
    /// The checkpoint is updated after every batch, so selecting the same file after
    /// an interruption continues from the last committed entry.
    /// </summary>
    public Task<WordImportResult> ImportToLibraryAsync(
        string selectedPath,
        StudyTrack track,
        WordLibraryStore store,
        IReadOnlySet<string>? localWordKeys,
        IProgress<WordImportProgress>? progress = null,
        CancellationToken cancellationToken = default)
    {
        return Task.Run(() =>
        {
            var (sourcePath, selectedCompanion) = ResolveSourcePath(selectedPath);
            var extension = Path.GetExtension(sourcePath).ToLowerInvariant();
            return extension switch
            {
                ".mdx" => ImportMdxToLibrary(sourcePath, selectedCompanion, track, store, localWordKeys, progress, cancellationToken),
                ".json" => ImportJsonToLibrary(sourcePath, track, store, localWordKeys, progress, cancellationToken),
                _ => throw new NotSupportedException("请选择 JSON、MDX、MDD 或 CSS 格式的词书文件。")
            };
        }, cancellationToken);
    }

    private static (string SourcePath, string? SelectedCompanion) ResolveSourcePath(string selectedPath)
    {
        var extension = Path.GetExtension(selectedPath).ToLowerInvariant();
        if (extension == ".mdx" || extension == ".json") return (selectedPath, null);
        if (extension == ".mdd")
        {
            var mdx = FindCompanionMdx(selectedPath, false);
            if (string.IsNullOrWhiteSpace(mdx))
                throw new InvalidDataException("MDD 是资源包。请把同名 MDX 词条文件放在同一文件夹后再导入；原文件不会被修改。");
            return (mdx, "MDD");
        }
        if (extension == ".css")
        {
            var mdx = FindCompanionMdx(selectedPath, true);
            if (string.IsNullOrWhiteSpace(mdx))
                throw new InvalidDataException("CSS 是词书样式文件，本身没有词条。请把配套 MDX 放在同一文件夹；程序会自动匹配并导入。");
            return (mdx, "CSS");
        }
        throw new NotSupportedException("请选择 JSON、MDX、MDD 或 CSS 格式的词书文件。");
    }

    private WordImportResult ImportMdxToLibrary(
        string mdxPath,
        string? selectedCompanion,
        StudyTrack track,
        WordLibraryStore store,
        IReadOnlySet<string>? localWordKeys,
        IProgress<WordImportProgress>? progress,
        CancellationToken cancellationToken)
    {
        progress?.Report(new WordImportProgress("正在读取词书索引…", 0, 0, 0));
        var sourceName = Path.GetFileName(mdxPath);
        var sourceId = CreateSourceId(mdxPath, track.Id);
        var dictionary = new MdxDict(mdxPath);
        WordImportSession? session = null;
        long processed = 0;
        var skipped = 0;
        var addedThisRun = 0;
        var duplicatesThisRun = 0;
        try
        {
            var keys = GetInternalField<List<KeyWordItem>>(dictionary, "keywordList");
            keys.Sort((left, right) => left.RecordStartOffset.CompareTo(right.RecordStartOffset));
            session = store.BeginImport(sourceId, track.Id, mdxPath, sourceName, keys.Count);
            if (session.IsComplete)
                return new WordImportResult(sourceName, 0, 0, session.Skipped, session.Processed, false, true);

            processed = Math.Clamp(session.Processed, 0, keys.Count);
            skipped = session.Skipped;
            var resumed = processed > 0;
            progress?.Report(new WordImportProgress(
                resumed ? $"正在从上次中断处继续… {processed:N0}/{keys.Count:N0}" : $"准备导入 {keys.Count:N0} 个词条…",
                processed, keys.Count, session.Added));

            var recordInfos = GetInternalField<List<RecordInfo>>(dictionary, "recordInfoList");
            var scanner = GetInternalField<FileScanner>(dictionary, "scanner");
            var meta = GetInternalField<MdictMeta>(dictionary, "meta");
            var recordStart = GetInternalField<long>(dictionary, "_recordBlockStartOffset");
            var decompress = typeof(MDict.Csharp.Models.Dict).GetMethod(
                "DecompressBuff", BindingFlags.Instance | BindingFlags.NonPublic)
                ?? throw new InvalidOperationException("当前 MDX 解析组件无法读取记录块。");

            var batch = new List<VocabularyWord>(ImportBatchSize);
            var keyIndex = checked((int)processed);
            var lastCheckpoint = processed;
            foreach (var info in recordInfos)
            {
                cancellationToken.ThrowIfCancellationRequested();
                if (keyIndex >= keys.Count) break;
                var blockEnd = info.UnpackAccumulatorOffset + info.UnpackSize;
                if (keys[keyIndex].RecordStartOffset >= blockEnd) continue;

                var packed = scanner.ReadBuffer(recordStart + info.PackAccumulateOffset, checked((int)info.PackSize));
                var unpacked = (byte[]?)decompress.Invoke(dictionary, [packed, checked((int)info.UnpackSize)])
                    ?? throw new InvalidDataException("MDX 记录块解压失败。");

                while (keyIndex < keys.Count && keys[keyIndex].RecordStartOffset < blockEnd)
                {
                    cancellationToken.ThrowIfCancellationRequested();
                    var key = keys[keyIndex++];
                    processed = keyIndex;
                    var localStart = checked((int)(key.RecordStartOffset - info.UnpackAccumulatorOffset));
                    var localEnd = checked((int)Math.Min(key.RecordEndOffset - info.UnpackAccumulatorOffset, unpacked.Length));
                    if (localStart < 0 || localStart >= localEnd || localEnd > unpacked.Length)
                    {
                        skipped++;
                    }
                    else
                    {
                        var definition = meta.Decoder.Decode(unpacked[localStart..localEnd]);
                        if (TryGetMdxLinkTarget(definition, out var target))
                        {
                            var resolved = dictionary.Lookup(target).Item2;
                            definition = string.IsNullOrWhiteSpace(resolved) ? "" : resolved;
                        }
                        var word = ConvertMdxEntry(key.KeyText, definition, track, Path.GetFileNameWithoutExtension(mdxPath));
                        if (word is null) skipped++;
                        else if (localWordKeys?.Contains(WordLibraryStore.Normalize(word.Word)) == true) duplicatesThisRun++;
                        else batch.Add(word);
                    }

                    if (batch.Count >= ImportBatchSize || processed - lastCheckpoint >= ImportBatchSize)
                    {
                        var write = store.WriteImportBatch(session, track, batch, processed, skipped);
                        addedThisRun += write.Added;
                        duplicatesThisRun += write.Duplicates;
                        batch.Clear();
                        lastCheckpoint = processed;
                        progress?.Report(new WordImportProgress(
                            $"正在自动分批导入… {processed:N0}/{keys.Count:N0}（已新增 {session.Added + addedThisRun:N0}）",
                            processed, keys.Count, session.Added + addedThisRun));
                    }
                }
            }

            if (batch.Count > 0 || processed > lastCheckpoint)
            {
                var write = store.WriteImportBatch(session, track, batch, processed, skipped);
                addedThisRun += write.Added;
                duplicatesThisRun += write.Duplicates;
            }
            store.FinishImport(session.Id, processed, skipped, true);
            return new WordImportResult(sourceName, addedThisRun, duplicatesThisRun, skipped, processed, resumed, false);
        }
        catch (OperationCanceledException)
        {
            if (session is not null) store.FinishImport(session.Id, processed, skipped, false, "用户暂停");
            throw;
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            if (session is not null) store.FinishImport(session.Id, processed, skipped, false, ex.InnerException.Message);
            throw new InvalidDataException("这个 MDX 文件无法解析：" + ex.InnerException.Message, ex.InnerException);
        }
        catch (Exception ex)
        {
            if (session is not null) store.FinishImport(session.Id, processed, skipped, false, ex.Message);
            throw;
        }
        finally
        {
            dictionary.Close();
        }
    }

    private WordImportResult ImportJsonToLibrary(
        string jsonPath,
        StudyTrack track,
        WordLibraryStore store,
        IReadOnlySet<string>? localWordKeys,
        IProgress<WordImportProgress>? progress,
        CancellationToken cancellationToken)
    {
        var sourceName = Path.GetFileName(jsonPath);
        var sourceId = CreateSourceId(jsonPath, track.Id);
        progress?.Report(new WordImportProgress("正在读取 JSON 词书…", 0, 0, 0));
        using var stream = File.OpenRead(jsonPath);
        using var document = JsonDocument.Parse(stream, new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        });
        var total = document.RootElement.ValueKind == JsonValueKind.Array ? document.RootElement.GetArrayLength() : 0;
        var session = store.BeginImport(sourceId, track.Id, jsonPath, sourceName, total);
        if (session.IsComplete)
            return new WordImportResult(sourceName, 0, 0, session.Skipped, session.Processed, false, true);

        long processed = 0;
        var skipped = session.Skipped;
        var addedThisRun = 0;
        var duplicatesThisRun = 0;
        var batch = new List<VocabularyWord>(ImportBatchSize);
        var lastCheckpoint = session.Processed;
        try
        {
            foreach (var word in EnumerateJsonWords(document.RootElement, track, Path.GetFileNameWithoutExtension(sourceName)))
            {
                cancellationToken.ThrowIfCancellationRequested();
                processed++;
                if (processed <= session.Processed) continue;
                if (word is null) skipped++;
                else if (localWordKeys?.Contains(WordLibraryStore.Normalize(word.Word)) == true) duplicatesThisRun++;
                else batch.Add(word);

                if (batch.Count >= ImportBatchSize || processed - lastCheckpoint >= ImportBatchSize)
                {
                    var write = store.WriteImportBatch(session, track, batch, processed, skipped);
                    addedThisRun += write.Added;
                    duplicatesThisRun += write.Duplicates;
                    batch.Clear();
                    lastCheckpoint = processed;
                    progress?.Report(new WordImportProgress(
                        $"正在自动分批导入… 已处理 {processed:N0} 条（已新增 {session.Added + addedThisRun:N0}）",
                        processed, total, session.Added + addedThisRun));
                }
            }
            if (batch.Count > 0 || processed > lastCheckpoint)
            {
                var write = store.WriteImportBatch(session, track, batch, processed, skipped);
                addedThisRun += write.Added;
                duplicatesThisRun += write.Duplicates;
            }
            store.FinishImport(session.Id, processed, skipped, true);
            return new WordImportResult(sourceName, addedThisRun, duplicatesThisRun, skipped, processed, session.Processed > 0, false);
        }
        catch (OperationCanceledException)
        {
            store.FinishImport(session.Id, processed, skipped, false, "用户暂停");
            throw;
        }
        catch (Exception ex)
        {
            store.FinishImport(session.Id, processed, skipped, false, ex.Message);
            throw;
        }
    }

    private static IEnumerable<VocabularyWord?> EnumerateJsonWords(JsonElement element, StudyTrack track, string sourceName, string fallbackWord = "")
    {
        if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
                foreach (var word in EnumerateJsonWords(item, track, sourceName))
                    yield return word;
            yield break;
        }
        if (element.ValueKind == JsonValueKind.String)
        {
            var parts = (element.GetString() ?? "").Split(['\t', '|'], 2, StringSplitOptions.TrimEntries);
            yield return parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[0]) && !string.IsNullOrWhiteSpace(parts[1])
                ? CreateJsonWord(track, sourceName, parts[0], parts[1])
                : null;
            yield break;
        }
        if (element.ValueKind != JsonValueKind.Object)
        {
            yield return null;
            yield break;
        }

        var explicitWord = ReadString(element, WordNames);
        if (!string.IsNullOrWhiteSpace(explicitWord) || !string.IsNullOrWhiteSpace(fallbackWord))
        {
            var meaning = ReadString(element, MeaningNames);
            if (string.IsNullOrWhiteSpace(meaning))
            {
                yield return null;
                yield break;
            }
            var word = new VocabularyWord
            {
                TrackId = track.Id,
                Word = string.IsNullOrWhiteSpace(explicitWord) ? fallbackWord : explicitWord,
                Meaning = meaning,
                Reading = ReadString(element, ["reading", "kana", "假名", "读音"]),
                Romanization = ReadString(element, ["romanization", "romaji", "罗马音"]),
                Phonetic = ReadString(element, ["phonetic", "ipa", "音标"]),
                PartOfSpeech = ReadString(element, ["partOfSpeech", "pos", "词性"]),
                Example = ReadString(element, ["example", "sentence", "例句"]),
                ExampleTranslation = ReadString(element, ["exampleTranslation", "sentenceTranslation", "例句翻译"]),
                Mnemonic = ReadString(element, ["mnemonic", "memory", "助记"]),
                Tag = ReadString(element, ["tag", "category", "标签"]),
                Difficulty = Math.Clamp(ReadInt(element, ["difficulty", "level", "难度"], 3), 1, 5),
                Phrases = new ObservableCollection<string>(ReadStrings(element, ["phrases", "collocations", "搭配"]))
            };
            if (string.IsNullOrWhiteSpace(word.Tag)) word.Tag = $"导入 · {sourceName}";
            yield return word;
            yield break;
        }

        foreach (var wrapper in WrapperNames)
        {
            if (!TryGetProperty(element, wrapper, out var nested)) continue;
            foreach (var word in EnumerateJsonWords(nested, track, sourceName)) yield return word;
            yield break;
        }

        var found = false;
        foreach (var property in element.EnumerateObject())
        {
            if (property.Value.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(property.Value.GetString()))
            {
                found = true;
                yield return CreateJsonWord(track, sourceName, property.Name, property.Value.GetString() ?? "");
            }
            else if (property.Value.ValueKind == JsonValueKind.Object)
            {
                found = true;
                foreach (var word in EnumerateJsonWords(property.Value, track, sourceName, property.Name)) yield return word;
            }
        }
        if (!found) yield return null;
    }

    private static string CreateSourceId(string filePath, string trackId)
    {
        var file = new FileInfo(filePath);
        var fingerprint = $"{Path.GetFullPath(filePath).ToUpperInvariant()}|{file.Length}|{file.LastWriteTimeUtc.Ticks}|{trackId}";
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(fingerprint))).ToLowerInvariant();
    }

    public VocabularyImportPreview ParseJson(string json, StudyTrack track, string sourceName = "JSON 词书")
    {
        using var document = JsonDocument.Parse(json, new JsonDocumentOptions
        {
            AllowTrailingCommas = true,
            CommentHandling = JsonCommentHandling.Skip
        });

        var words = new List<VocabularyWord>();
        var skipped = 0;
        VisitJson(document.RootElement, track, Path.GetFileNameWithoutExtension(sourceName), words, ref skipped);
        EnsureWithinImportLimit(words.Count);
        words = Deduplicate(words, ref skipped);
        if (words.Count == 0)
            throw new InvalidDataException("没有在 JSON 中找到可导入的词条。每个词条至少需要 word（词语）和 meaning（释义）。");

        return new VocabularyImportPreview(words, skipped, sourceName,
            "已读取 JSON 词条；支持应用导出的 Words 数组和常见 word/meaning 字段。");
    }

    private VocabularyImportPreview ParseMdd(string mddPath, StudyTrack track, IProgress<string>? progress)
    {
        var mdxPath = FindCompanionMdx(mddPath, false);
        if (string.IsNullOrWhiteSpace(mdxPath))
            throw new InvalidDataException("MDD 是词典的图片、音频等资源包。请把同名 MDX 词条文件放在同一文件夹后再导入。你的 MDD 文件不会被修改。");

        return ParseMdx(mdxPath, track, "MDD", progress);
    }

    private VocabularyImportPreview ParseCss(string cssPath, StudyTrack track, IProgress<string>? progress)
    {
        var mdxPath = FindCompanionMdx(cssPath, true);
        if (string.IsNullOrWhiteSpace(mdxPath))
            throw new InvalidDataException("CSS 是 MDX 词书的显示样式文件，本身不包含单词。请将对应 MDX 放在同一文件夹；如果该文件夹有多本词书，请直接选择正确的 MDX。");

        return ParseMdx(mdxPath, track, "CSS", progress);
    }

    private static string FindCompanionMdx(string companionPath, bool allowOnlyMdxInFolder)
    {
        var exactPath = Path.ChangeExtension(companionPath, ".mdx");
        if (File.Exists(exactPath)) return exactPath;

        var directory = Path.GetDirectoryName(companionPath) ?? "";
        var baseName = Path.GetFileNameWithoutExtension(companionPath);
        var candidates = Directory.EnumerateFiles(directory, "*.mdx").ToList();
        var matching = candidates.FirstOrDefault(x =>
            Path.GetFileNameWithoutExtension(x).Equals(baseName, StringComparison.OrdinalIgnoreCase));
        if (!string.IsNullOrWhiteSpace(matching)) return matching;
        return allowOnlyMdxInFolder && candidates.Count == 1 ? candidates[0] : "";
    }

    private VocabularyImportPreview ParseMdx(string mdxPath, StudyTrack track, string? selectedCompanion, IProgress<string>? progress)
    {
        progress?.Report("正在读取 MDX 索引…");
        var parsed = new List<VocabularyWord>();
        var skipped = 0;
        var dictionary = new MdxDict(mdxPath);
        try
        {
            var keys = GetInternalField<List<KeyWordItem>>(dictionary, "keywordList")
                .OrderBy(x => x.RecordStartOffset)
                .ToList();
            EnsureWithinImportLimit(keys.Count);
            var recordInfos = GetInternalField<List<RecordInfo>>(dictionary, "recordInfoList");
            var scanner = GetInternalField<FileScanner>(dictionary, "scanner");
            var meta = GetInternalField<MdictMeta>(dictionary, "meta");
            var recordStart = GetInternalField<long>(dictionary, "_recordBlockStartOffset");
            var decompress = typeof(MDict.Csharp.Models.Dict).GetMethod(
                "DecompressBuff", BindingFlags.Instance | BindingFlags.NonPublic)
                ?? throw new InvalidOperationException("当前 MDX 解析组件无法读取记录块。");

            var keyIndex = 0;
            for (var blockIndex = 0; blockIndex < recordInfos.Count; blockIndex++)
            {
                var info = recordInfos[blockIndex];
                var blockEnd = info.UnpackAccumulatorOffset + info.UnpackSize;
                while (keyIndex < keys.Count && keys[keyIndex].RecordStartOffset < info.UnpackAccumulatorOffset) keyIndex++;

                var packed = scanner.ReadBuffer(recordStart + info.PackAccumulateOffset, checked((int)info.PackSize));
                var unpacked = (byte[]?)decompress.Invoke(dictionary, [packed, checked((int)info.UnpackSize)])
                    ?? throw new InvalidDataException("MDX 记录块解压失败。");

                while (keyIndex < keys.Count && keys[keyIndex].RecordStartOffset < blockEnd)
                {
                    var key = keys[keyIndex++];
                    var localStart = checked((int)(key.RecordStartOffset - info.UnpackAccumulatorOffset));
                    var localEnd = checked((int)Math.Min(key.RecordEndOffset - info.UnpackAccumulatorOffset, unpacked.Length));
                    if (localStart < 0 || localStart >= localEnd || localEnd > unpacked.Length)
                    {
                        skipped++;
                        continue;
                    }

                    var definition = meta.Decoder.Decode(unpacked[localStart..localEnd]);
                    if (TryGetMdxLinkTarget(definition, out var target))
                    {
                        var resolved = dictionary.Lookup(target).Item2;
                        definition = string.IsNullOrWhiteSpace(resolved) ? "" : resolved;
                    }
                    var word = ConvertMdxEntry(key.KeyText, definition, track, Path.GetFileNameWithoutExtension(mdxPath));
                    if (word is null) skipped++;
                    else parsed.Add(word);
                }

                if (blockIndex % 8 == 0 || blockIndex == recordInfos.Count - 1)
                {
                    var percent = recordInfos.Count == 0 ? 100 : (blockIndex + 1) * 100 / recordInfos.Count;
                    progress?.Report($"正在解析 MDX 词条… {percent}%（已识别 {parsed.Count:N0} 条）");
                }
            }
        }
        catch (TargetInvocationException ex) when (ex.InnerException is not null)
        {
            throw new InvalidDataException("这个 MDX 文件无法解析：" + ex.InnerException.Message, ex.InnerException);
        }
        finally
        {
            dictionary.Close();
        }

        parsed = Deduplicate(parsed, ref skipped);
        if (parsed.Count == 0) throw new InvalidDataException("这个 MDX 中没有找到可作为单词和释义导入的词条。");
        var companionMdd = Path.ChangeExtension(mdxPath, ".mdd");
        var hasCompanionMdd = selectedCompanion == "MDD" || File.Exists(companionMdd);
        var detail = selectedCompanion switch
        {
            "CSS" => "已识别 CSS 配套样式，并从同目录匹配的 MDX 导入词条与文本释义。",
            "MDD" => "已读取 MDX 词条，并识别到配套 MDD 资源包；当前单词本导入文本释义。",
            _ when hasCompanionMdd => "已读取 MDX 词条，并识别到同名 MDD 资源包；当前单词本导入文本释义。",
            _ => "已读取 MDX 中的词条与文本释义。"
        };
        return new VocabularyImportPreview(parsed, skipped, Path.GetFileName(mdxPath), detail);
    }

    private static VocabularyWord? ConvertMdxEntry(string headword, string definition, StudyTrack track, string sourceName)
    {
        headword = WebUtility.HtmlDecode(headword ?? "").Trim();
        if (string.IsNullOrWhiteSpace(headword) || headword.StartsWith('\\') || headword.StartsWith('@') || LooksLikeResource(headword)) return null;

        var plain = CleanDefinition(definition);
        if (string.IsNullOrWhiteSpace(plain)) return null;

        var phonetic = "";
        var reading = "";
        var partOfSpeech = "";
        var meaning = plain;
        var example = "";
        if (track.Mode == LearningMode.English)
        {
            var match = Regex.Match(plain, @"/(?<ipa>[^/\r\n]{1,48})/");
            if (match.Success) phonetic = "/" + match.Groups["ipa"].Value.Trim() + "/";
            partOfSpeech = Regex.Match(plain,
                @"\b(noun|verb|adjective|adverb|pronoun|preposition|conjunction|interjection|n\.|v\.|adj\.|adv\.)\b",
                RegexOptions.IgnoreCase).Value;
        }
        else if (track.Mode == LearningMode.Japanese)
        {
            reading = ExtractMdxDataName(definition, "見出仮名").FirstOrDefault() ?? "";
            reading = Regex.Replace(reading, @"\s+", "");
            if (string.IsNullOrWhiteSpace(reading))
            {
                var match = Regex.Match(plain, @"[【\[(（](?<reading>[ぁ-んァ-ヶー・\s]{1,40})[】\])）]");
                if (match.Success) reading = Regex.Replace(match.Groups["reading"].Value, @"\s+", "");
            }

            partOfSpeech = string.Join("・", ExtractMdxDataName(definition, "品詞M").Distinct(StringComparer.Ordinal));
            var meanings = ExtractMdxDataName(definition, "語釈")
                .Where(x => !string.IsNullOrWhiteSpace(x))
                .Distinct(StringComparer.Ordinal)
                .Take(6)
                .ToList();
            if (meanings.Count > 0) meaning = string.Join("；", meanings);
            example = ExtractMdxDataName(definition, "用例").FirstOrDefault() ?? "";
        }

        return new VocabularyWord
        {
            TrackId = track.Id,
            Word = headword,
            Reading = reading,
            Phonetic = phonetic,
            PartOfSpeech = partOfSpeech,
            Meaning = Limit(meaning, 1200),
            Example = Limit(example, 500),
            Tag = $"导入 · {sourceName}",
            Difficulty = 3
        };
    }

    private static bool TryGetMdxLinkTarget(string definition, out string target)
    {
        target = "";
        if (string.IsNullOrWhiteSpace(definition)) return false;
        var clean = definition.Trim(' ', '\r', '\n', '\t', '\0');
        if (!clean.StartsWith("@@@LINK=", StringComparison.OrdinalIgnoreCase)) return false;
        target = clean[8..].Trim(' ', '\r', '\n', '\t', '\0');
        return !string.IsNullOrWhiteSpace(target);
    }

    private static IEnumerable<string> ExtractMdxDataName(string html, string dataName)
    {
        if (string.IsNullOrWhiteSpace(html)) yield break;
        var pattern = "<span\\b[^>]*\\bdata-name\\s*=\\s*(['\"])" + Regex.Escape(dataName) + "\\1[^>]*>(?<value>.*?)</span>";
        foreach (Match match in Regex.Matches(html, pattern, RegexOptions.IgnoreCase | RegexOptions.Singleline))
        {
            var value = CleanDefinition(match.Groups["value"].Value);
            if (!string.IsNullOrWhiteSpace(value)) yield return value;
        }
    }

    private static void VisitJson(JsonElement element, StudyTrack track, string sourceName,
        List<VocabularyWord> words, ref int skipped, string fallbackWord = "")
    {
        if (element.ValueKind == JsonValueKind.Array)
        {
            foreach (var item in element.EnumerateArray())
            {
                VisitJson(item, track, sourceName, words, ref skipped);
                EnsureWithinImportLimit(words.Count);
            }
            return;
        }
        if (element.ValueKind == JsonValueKind.String)
        {
            var raw = element.GetString() ?? "";
            var parts = raw.Split(['\t', '|'], 2, StringSplitOptions.TrimEntries);
            if (parts.Length == 2 && !string.IsNullOrWhiteSpace(parts[0]) && !string.IsNullOrWhiteSpace(parts[1]))
                words.Add(CreateJsonWord(track, sourceName, parts[0], parts[1]));
            else skipped++;
            EnsureWithinImportLimit(words.Count);
            return;
        }
        if (element.ValueKind != JsonValueKind.Object)
        {
            skipped++;
            return;
        }

        var explicitWord = ReadString(element, WordNames);
        if (!string.IsNullOrWhiteSpace(explicitWord) || !string.IsNullOrWhiteSpace(fallbackWord))
        {
            var meaning = ReadString(element, MeaningNames);
            if (string.IsNullOrWhiteSpace(meaning))
            {
                skipped++;
                return;
            }
            words.Add(new VocabularyWord
            {
                TrackId = track.Id,
                Word = string.IsNullOrWhiteSpace(explicitWord) ? fallbackWord : explicitWord,
                Meaning = meaning,
                Reading = ReadString(element, ["reading", "kana", "假名", "读音"]),
                Romanization = ReadString(element, ["romanization", "romaji", "罗马音"]),
                Phonetic = ReadString(element, ["phonetic", "ipa", "音标"]),
                PartOfSpeech = ReadString(element, ["partOfSpeech", "pos", "词性"]),
                Example = ReadString(element, ["example", "sentence", "例句"]),
                ExampleTranslation = ReadString(element, ["exampleTranslation", "sentenceTranslation", "例句翻译"]),
                Mnemonic = ReadString(element, ["mnemonic", "memory", "助记"]),
                Tag = ReadString(element, ["tag", "category", "标签"]),
                Difficulty = Math.Clamp(ReadInt(element, ["difficulty", "level", "难度"], 3), 1, 5),
                Phrases = new ObservableCollection<string>(ReadStrings(element, ["phrases", "collocations", "搭配"]))
            });
            if (string.IsNullOrWhiteSpace(words[^1].Tag)) words[^1].Tag = $"导入 · {sourceName}";
            EnsureWithinImportLimit(words.Count);
            return;
        }

        foreach (var wrapper in WrapperNames)
        {
            if (TryGetProperty(element, wrapper, out var nested))
            {
                VisitJson(nested, track, sourceName, words, ref skipped);
                return;
            }
        }

        var foundMapEntry = false;
        foreach (var property in element.EnumerateObject())
        {
            if (property.Value.ValueKind == JsonValueKind.String)
            {
                var meaning = property.Value.GetString() ?? "";
                if (!string.IsNullOrWhiteSpace(meaning))
                {
                    words.Add(CreateJsonWord(track, sourceName, property.Name, meaning));
                    EnsureWithinImportLimit(words.Count);
                    foundMapEntry = true;
                }
            }
            else if (property.Value.ValueKind == JsonValueKind.Object)
            {
                VisitJson(property.Value, track, sourceName, words, ref skipped, property.Name);
                foundMapEntry = true;
            }
        }
        if (!foundMapEntry) skipped++;
    }

    private static VocabularyWord CreateJsonWord(StudyTrack track, string sourceName, string word, string meaning) => new()
    {
        TrackId = track.Id,
        Word = word.Trim(),
        Meaning = meaning.Trim(),
        Tag = $"导入 · {sourceName}",
        Difficulty = 3
    };

    private static List<VocabularyWord> Deduplicate(List<VocabularyWord> source, ref int skipped)
    {
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var result = new List<VocabularyWord>(source.Count);
        foreach (var word in source)
        {
            word.Word = word.Word.Trim();
            word.Meaning = word.Meaning.Trim();
            if (string.IsNullOrWhiteSpace(word.Word) || string.IsNullOrWhiteSpace(word.Meaning) || !seen.Add(word.Word)) skipped++;
            else result.Add(word);
        }
        return result;
    }

    private static void EnsureWithinImportLimit(int count)
    {
        if (count <= MaxImportEntries) return;
        throw new InvalidDataException($"这本词书包含超过 {MaxImportEntries:N0} 个词条，已为保护程序和本地数据停止导入。请先将词书精简或拆分后再导入。");
    }

    private static T GetInternalField<T>(object instance, string name)
    {
        var field = typeof(BaseDict).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)
            ?? throw new InvalidOperationException($"MDX 解析组件缺少 {name} 字段。");
        return field.GetValue(instance) is T value
            ? value
            : throw new InvalidOperationException($"MDX 解析组件的 {name} 字段格式不兼容。");
    }

    private static string CleanDefinition(string value)
    {
        if (string.IsNullOrWhiteSpace(value)) return "";
        value = Regex.Replace(value, @"<\s*(script|style)[^>]*>.*?<\s*/\s*\1\s*>", " ", RegexOptions.IgnoreCase | RegexOptions.Singleline);
        value = Regex.Replace(value, @"<\s*(br|hr)\s*/?\s*>", "；", RegexOptions.IgnoreCase);
        value = Regex.Replace(value, @"<\s*/\s*(p|div|li|tr|section|h[1-6])\s*>", "；", RegexOptions.IgnoreCase);
        value = Regex.Replace(value, @"<[^>]+>", " ");
        value = WebUtility.HtmlDecode(value).Replace('\0', ' ');
        return Regex.Replace(value, @"\s+", " ").Trim(' ', '；');
    }

    private static bool LooksLikeResource(string value)
    {
        var extension = Path.GetExtension(value).ToLowerInvariant();
        return extension is ".css" or ".js" or ".jpg" or ".jpeg" or ".png" or ".gif" or ".svg" or ".mp3" or ".wav" or ".spx" or ".ttf" or ".woff" or ".woff2";
    }

    private static string Limit(string value, int length) => value.Length <= length ? value : value[..length].TrimEnd() + "…";

    private static string ReadString(JsonElement element, IReadOnlyList<string> names)
    {
        foreach (var name in names)
        {
            if (!TryGetProperty(element, name, out var value)) continue;
            if (value.ValueKind == JsonValueKind.String) return value.GetString()?.Trim() ?? "";
            if (value.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False) return value.ToString();
            if (value.ValueKind == JsonValueKind.Array) return string.Join("；", value.EnumerateArray().Select(x => x.ToString()).Where(x => !string.IsNullOrWhiteSpace(x)));
        }
        return "";
    }

    private static IEnumerable<string> ReadStrings(JsonElement element, IReadOnlyList<string> names)
    {
        foreach (var name in names)
        {
            if (!TryGetProperty(element, name, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Array)
                return value.EnumerateArray().Select(x => x.ToString().Trim()).Where(x => !string.IsNullOrWhiteSpace(x)).ToList();
            if (value.ValueKind == JsonValueKind.String)
                return (value.GetString() ?? "").Split(['；', ';', '|'], StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        }
        return [];
    }

    private static int ReadInt(JsonElement element, IReadOnlyList<string> names, int fallback)
    {
        foreach (var name in names)
        {
            if (!TryGetProperty(element, name, out var value)) continue;
            if (value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out var number)) return number;
            if (value.ValueKind == JsonValueKind.String && int.TryParse(value.GetString(), out number)) return number;
        }
        return fallback;
    }

    private static bool TryGetProperty(JsonElement element, string name, out JsonElement value)
    {
        foreach (var property in element.EnumerateObject())
        {
            if (property.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
            {
                value = property.Value;
                return true;
            }
        }
        value = default;
        return false;
    }
}
