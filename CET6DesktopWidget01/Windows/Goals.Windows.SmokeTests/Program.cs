using System.IO;
using Goals.Windows.Models;
using Goals.Windows.Services;
using Goals.Windows.ViewModels;
using MDict.Csharp.Models;

static void Assert(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException("SELF TEST FAILED: " + message);
    Console.WriteLine("PASS  " + message);
}

if (args.Length >= 1 && args[0] == "--mdx-api")
{
    foreach (var method in typeof(MdxDict).GetMethods(System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.DeclaredOnly))
        Console.WriteLine($"{method.ReturnType} {method.Name}({string.Join(", ", method.GetParameters().Select(x => $"{x.ParameterType.Name} {x.Name}"))})");
    return;
}

if (args.Length >= 3 && args[0] == "--mdx-lookup")
{
    var dictionary = new MdxDict(Path.GetFullPath(args[1]));
    try
    {
        foreach (var term in args.Skip(2))
        {
            var result = dictionary.Lookup(term);
            Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { term, result.Item1, result.Item2 }));
            if (result.Item2?.StartsWith("@@@LINK=", StringComparison.OrdinalIgnoreCase) == true)
            {
                var target = result.Item2[8..].Trim(' ', '\r', '\n', '\t', '\0');
                var resolved = dictionary.Lookup(target);
                Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { target, resolved.Item1, resolved.Item2 }));
            }
        }
    }
    finally { dictionary.Close(); }
    return;
}

if (args.Length >= 3 && args[0] == "--mdx-benchmark")
{
    var dictionary = new MdxDict(Path.GetFullPath(args[1]));
    using var sourceLibrary = new WordLibraryStore(Path.GetFullPath(args[2]));
    var terms = sourceLibrary.QueryWordbookEntries("japanese-n4", null, "", 0, 1_000).Entries.Select(x => x.Word.Word).ToList();
    var timer = System.Diagnostics.Stopwatch.StartNew();
    var resolvedCount = 0;
    try
    {
        foreach (var term in terms)
        {
            var result = dictionary.Lookup(term);
            if (result.Item2?.StartsWith("@@@LINK=", StringComparison.OrdinalIgnoreCase) != true) continue;
            var target = result.Item2[8..].Trim(' ', '\r', '\n', '\t', '\0');
            if (!string.IsNullOrWhiteSpace(dictionary.Lookup(target).Item2)) resolvedCount++;
        }
    }
    finally { dictionary.Close(); }
    timer.Stop();
    Console.WriteLine($"resolved={resolvedCount} seconds={timer.Elapsed.TotalSeconds:F3}");
    return;
}

if (args.Length >= 3 && args[0] == "--wordbook-probe")
{
    var selectedPath = Path.GetFullPath(args[1]);
    var probeDirectory = Path.GetFullPath(args[2]);
    Directory.CreateDirectory(probeDirectory);
    var probeState = DefaultDataFactory.Create();
    var probeTrackId = args.Length >= 4 ? args[3] : "cet6";
    var probeTrack = probeState.Tracks.Single(x => x.Id == probeTrackId);
    var probeImporter = new VocabularyImportService();
    using var probeLibrary = new WordLibraryStore(probeDirectory);
    var lastReported = 0L;
    var probeProgress = new InlineProgress<WordImportProgress>(value =>
    {
        if (value.Processed - lastReported < 25_000 && value.Total > 0 && value.Processed < value.Total) return;
        lastReported = value.Processed;
        Console.WriteLine($"PROGRESS {value.Processed:N0}/{value.Total:N0} added={value.Added:N0}");
    });
    var timer = System.Diagnostics.Stopwatch.StartNew();
    var probeResult = await probeImporter.ImportToLibraryAsync(selectedPath, probeTrack, probeLibrary, null, probeProgress);
    timer.Stop();
    var books = probeLibrary.QueryWordbooks(probeTrack.Id);
    var fill = probeLibrary.EnsureDailyWords(probeTrack.Id, DateTime.Today);
    var focused = probeLibrary.QueryWords(probeTrack.Id, "", 0, WordLibraryStore.PageSize);
    var due = probeLibrary.QueryReviewWords(probeTrack.Id, "due", DateTime.Now, WordLibraryStore.ReviewBatchSize);
    var firstPage = probeLibrary.QueryWordbookEntries(probeTrack.Id, books.Single().Id, "", 0, WordLibraryStore.PageSize, probeTrack.Mode == LearningMode.Japanese);
    var process = System.Diagnostics.Process.GetCurrentProcess();
    Console.WriteLine($"RESULT source={probeResult.SourceName} processed={probeResult.Processed:N0} added={probeResult.Added:N0} duplicates={probeResult.Duplicates:N0} skipped={probeResult.Skipped:N0}");
    Console.WriteLine($"RESULT seconds={timer.Elapsed.TotalSeconds:F2} peak_mb={process.PeakWorkingSet64 / 1024d / 1024d:F1} db_mb={new FileInfo(probeLibrary.DataPath).Length / 1024d / 1024d:F1}");
    Console.WriteLine($"RESULT books={books.Count} book_words={books.Single().WordCount:N0} daily_added={fill.AddedNow} focused={focused.Total} flashcards={due.Count} page={firstPage.Entries.Count}");
    Assert(books.Count == 1 && books[0].WordCount == probeResult.Added, "real CSS/MDX import is represented as one complete wordbook");
    Assert(fill.AddedNow == 20 && focused.Total == 20 && due.Count == 20, "real wordbook contributes exactly 20 daily words to the study list and flashcards");
    Assert(firstPage.Entries.Count == WordLibraryStore.PageSize, "real wordbook page is read without loading the entire dictionary");
    if (probeTrack.Mode == LearningMode.Japanese)
    {
        var greeting = probeLibrary.QueryWordbookEntries(probeTrack.Id, books.Single().Id, "挨拶", 0, 10, true).Entries.FirstOrDefault(x => x.Word.Word == "挨拶");
        Assert(greeting is not null && greeting.Word.Reading == "あいさつ", "Japanese MDX link resolves to the real headword reading");
        Assert(greeting is not null && !greeting.Word.Meaning.StartsWith("参见：", StringComparison.Ordinal) && greeting.Word.Meaning.Contains("人と会", StringComparison.Ordinal), "Japanese MDX link resolves to the real dictionary definition");
        var dha = probeLibrary.QueryWordbookEntries(probeTrack.Id, books.Single().Id, "DHA", 0, 10, true).Entries.FirstOrDefault(x => x.Word.Word == "DHA");
        Assert(dha is not null && dha.Word.Reading == "ディーエイチエー" && dha.Word.Meaning.Contains("イワシ", StringComparison.Ordinal), "Latin abbreviations in a Japanese dictionary display their real Japanese reading and definition");
        Assert(probeLibrary.QueryWordbookEntries(probeTrack.Id, books.Single().Id, "@smk8-", 0, 1, true).Total == 0, "internal MDX record identifiers are excluded from the wordbook");
        Assert(firstPage.Entries[0].Word.Word.Length > 0 && firstPage.Entries[0].Word.Word[0] > 127, "Japanese wordbook browsing prioritizes headwords that begin in native script");
    }
    return;
}

if (args.Length >= 3 && args[0] == "--wordbook-inspect")
{
    using var inspectLibrary = new WordLibraryStore(Path.GetFullPath(args[1]));
    Console.WriteLine($"daily={inspectLibrary.GetDailyNewWordCount(args[2])} books={inspectLibrary.QueryWordbooks(args[2]).Count} active={inspectLibrary.QueryWords(args[2], "", 0, 100).Total}");
    return;
}

if (args.Length >= 4 && args[0] == "--wordbook-query")
{
    using var queryLibrary = new WordLibraryStore(Path.GetFullPath(args[1]));
    var queryTrackId = args[2];
    var query = args[3];
    var book = queryLibrary.QueryWordbooks(queryTrackId).Single();
    var page = queryLibrary.QueryWordbookEntries(queryTrackId, book.Id, query, 0, 20, true);
    foreach (var entry in page.Entries)
        Console.WriteLine(System.Text.Json.JsonSerializer.Serialize(new { entry.Word.Word, entry.Word.Reading, entry.Word.Meaning }));
    return;
}

if (args.Length >= 3 && args[0] == "--wordbook-delete-probe")
{
    using var deleteLibrary = new WordLibraryStore(Path.GetFullPath(args[1]));
    var deleteTrackId = args[2];
    var book = deleteLibrary.QueryWordbooks(deleteTrackId).Single();
    var timer = System.Diagnostics.Stopwatch.StartNew();
    deleteLibrary.DeleteWordbook(book.Id);
    timer.Stop();
    Assert(deleteLibrary.QueryWordbooks(deleteTrackId).Count == 0, "large wordbook is deleted as one transaction");
    Console.WriteLine($"DELETE seconds={timer.Elapsed.TotalSeconds:F2} words={book.WordCount:N0}");
    return;
}

var state = DefaultDataFactory.Create();
Assert(state.Tracks.Count >= 2, "at least two learning tracks");
Assert(typeof(AppState).GetProperty("WidgetEnabled") is null, "floating widget state has been removed");
Assert(typeof(MainViewModel).GetProperty("Speech") is null, "speech service has been removed from the application model");
Assert(AppUpdateService.RepositoryUrl == "https://github.com/qyy3369-hue/CET-6", "installed updates use the configured GitHub Releases repository");
Assert(AppUpdateService.SourceOverrideEnvironmentVariable == "GOALS_UPDATE_SOURCE", "update source can be overridden for offline end-to-end testing");
var wordbooksXaml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "WordbooksPage.xaml"));
Assert(wordbooksXaml.Contains("StatusLabel, Mode=OneWay", StringComparison.Ordinal), "wordbook completion status is rendered with a read-only binding");
Assert(wordbooksXaml.Contains("Word.Example", StringComparison.Ordinal) &&
       wordbooksXaml.Contains("Word.ExampleTranslation", StringComparison.Ordinal),
    "wordbook browsing cards show the same example and translation fields as the focused vocabulary list");
Assert(wordbooksXaml.Contains("<ColumnDefinition Width=\"220\"/>", StringComparison.Ordinal) &&
       wordbooksXaml.Contains("FontSize=\"23\"", StringComparison.Ordinal),
    "wordbook browsing cards use the same information hierarchy as the focused vocabulary list");
Assert(wordbooksXaml.Contains("JapaneseText_SelectionChanged", StringComparison.Ordinal) &&
       wordbooksXaml.Contains("DeepSeek 选中翻译", StringComparison.Ordinal),
    "Japanese definitions in wordbooks can be selected for automatic DeepSeek translation");
Assert(typeof(DeepSeekService).GetMethod("TranslateJapaneseSelectionAsync") is not null,
    "DeepSeek provides a dedicated Japanese-to-Chinese selection translation request");
var vocabularyXaml = File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Fixtures", "VocabularyPage.xaml"));
Assert(vocabularyXaml.Contains("全选本页", StringComparison.Ordinal) &&
       vocabularyXaml.Contains("DeleteSelected_Click", StringComparison.Ordinal) &&
       vocabularyXaml.Contains("WordSelectionCheckBox_Changed", StringComparison.Ordinal),
    "vocabulary pages support selecting the current page and bulk deletion");
Assert(!vocabularyXaml.Contains("☆/★ 收藏", StringComparison.Ordinal) &&
       vocabularyXaml.Contains("Content=\"☆\"", StringComparison.Ordinal),
    "vocabulary favorites use one star button instead of a two-star label");
var japaneseTextDetector = typeof(Goals.Windows.Views.WordbooksPage).GetMethod("ContainsJapaneseText",
    System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
Assert(japaneseTextDetector?.Invoke(null, ["日本語"]) is true &&
       japaneseTextDetector.Invoke(null, ["English"]) is false,
    "automatic selection translation is limited to Japanese text");
Exception? runParentError = null;
var runParentResolved = false;
var scrollWithRunIsSafe = false;
var runParentThread = new Thread(() =>
{
    try
    {
        var text = new System.Windows.Controls.TextBlock();
        var run = new System.Windows.Documents.Run("删除");
        text.Inlines.Add(run);
        var method = typeof(Goals.Windows.Views.WordbooksPage).GetMethod("GetInteractionParent",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
        runParentResolved = ReferenceEquals(method?.Invoke(null, [run]), text);
        var scrollMethod = typeof(Goals.Windows.Infrastructure.SmoothScrollBehavior).GetMethod("FindScrollableViewer",
            System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static);
        scrollWithRunIsSafe = scrollMethod?.Invoke(null, [run, null]) is null;
    }
    catch (Exception ex) { runParentError = ex; }
});
runParentThread.SetApartmentState(ApartmentState.STA);
runParentThread.Start();
runParentThread.Join();
Assert(runParentError is null && runParentResolved,
    "wordbook card clicks safely traverse inline Run text inside buttons");
Assert(runParentError is null && scrollWithRunIsSafe,
    "smooth scrolling safely handles inline Run text in imported wordbook cards");
var scrollType = typeof(Goals.Windows.Infrastructure.SmoothScrollBehavior);
var scrollDistanceFactor = (double)(scrollType.GetField("WheelDistanceFactor", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)?.GetRawConstantValue() ?? 0d);
var scrollAnimationMilliseconds = (int)(scrollType.GetField("ScrollAnimationMilliseconds", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Static)?.GetRawConstantValue() ?? 0);
Assert(scrollDistanceFactor == 0.86 && scrollAnimationMilliseconds == 130,
    "all pages use the lighter unified smooth-scroll response");
var english = state.Tracks.Single(x => x.Id == "cet6");
var japanese = state.Tracks.Single(x => x.Id == "japanese-n4");
Assert(english.Mode == LearningMode.English, "CET-6 track is English");
Assert(japanese.Mode == LearningMode.Japanese, "N4 track is Japanese");
var custom = new StudyTrack { Title = "阅读计划", Mode = LearningMode.Other };
Assert(custom.ModeLabel == "其他 · 自定义", "custom learning type is available");
Assert(state.Words.Count(x => x.TrackId == english.Id) >= 20, "English sample vocabulary is populated");
Assert(state.Words.Where(x => x.TrackId == english.Id).All(x => !string.IsNullOrWhiteSpace(x.Phonetic)), "English flashcards include phonetic transcription");
Assert(state.Words.Count(x => x.TrackId == japanese.Id) >= 30, "Japanese N4 sample vocabulary is populated");
Assert(state.Words.Where(x => x.TrackId == japanese.Id).All(x => !string.IsNullOrWhiteSpace(x.Reading) && !string.IsNullOrWhiteSpace(x.Romanization)), "Japanese cards include kana and romanization");
Assert(state.Tasks.Any(x => x.TrackId == english.Id && x.Date.Date == DateTime.Today), "English today schedule exists");
Assert(state.Tasks.Any(x => x.TrackId == japanese.Id && x.Date.Date == DateTime.Today), "Japanese today schedule exists");

var importer = new VocabularyImportService();
var jsonPreview = importer.ParseJson("""
[
  { "word": "図書館", "reading": "としょかん", "romanization": "toshokan", "meaning": "图书馆", "partOfSpeech": "名词", "difficulty": 2 },
  { "term": "約束", "kana": "やくそく", "translation": "约定；承诺", "tag": "N4 日常" }
]
""", japanese, "sample.json");
Assert(jsonPreview.Words.Count == 2, "JSON wordbook import recognizes common field names");
Assert(jsonPreview.Words[0].TrackId == japanese.Id && jsonPreview.Words[0].Reading == "としょかん", "JSON import targets the selected track and keeps Japanese reading");

var wrappedPreview = importer.ParseJson("""
{ "Words": [ { "Word": "resilient", "Meaning": "有韧性的", "Phonetic": "/rɪˈzɪliənt/" } ] }
""", english, "goals-export.json");
Assert(wrappedPreview.Words.Count == 1 && wrappedPreview.Words[0].Phonetic == "/rɪˈzɪliənt/", "JSON import accepts an exported Words wrapper");

var mdxFixture = Path.Combine(AppContext.BaseDirectory, "Fixtures", "import-smoke.mdx");
var mdxPreview = await importer.ReadAsync(mdxFixture, english);
Assert(mdxPreview.Words.Count == 2, "MDX wordbook import enumerates all dictionary entries");
Assert(mdxPreview.Words.Any(x => x.Word == "apple" && x.Meaning.Contains("苹果") && x.Phonetic == "/ˈæpl/"), "MDX import converts HTML definitions and retains phonetic transcription");
var mddFixture = Path.Combine(AppContext.BaseDirectory, "Fixtures", "import-smoke.mdd");
var mddPreview = await importer.ReadAsync(mddFixture, japanese);
Assert(mddPreview.Words.Count == 2 && mddPreview.Detail.Contains("MDD"), "MDD selection pairs with the same-name MDX word entries");
var cssFixture = Path.Combine(AppContext.BaseDirectory, "Fixtures", "import-smoke.css");
var cssPreview = await importer.ReadAsync(cssFixture, english);
Assert(cssPreview.Words.Count == 2 && cssPreview.Detail.Contains("CSS"), "CSS selection pairs with the same-name MDX word entries");
var oversizedJson = "[" + string.Join(",", Enumerable.Range(0, VocabularyImportService.MaxImportEntries + 1)
    .Select(i => $"{{\"word\":\"word-{i}\",\"meaning\":\"meaning-{i}\"}}")) + "]";
var oversizedStopped = false;
try { importer.ParseJson(oversizedJson, english, "oversized.json"); }
catch (InvalidDataException ex) { oversizedStopped = ex.Message.Contains("停止导入"); }
Assert(oversizedStopped, "oversized wordbook import is stopped before data is written");

var automaticImportDirectory = Path.Combine(Path.GetTempPath(), "goals-word-library-test-" + Guid.NewGuid().ToString("N"));
Directory.CreateDirectory(automaticImportDirectory);
try
{
    var automaticJsonPath = Path.Combine(automaticImportDirectory, "large.json");
    var automaticJson = "[" + string.Join(",", Enumerable.Range(0, VocabularyImportService.MaxImportEntries + 1)
        .Select(i => $"{{\"word\":\"auto-{i}\",\"meaning\":\"meaning-{i}\"}}")) + "]";
    await File.WriteAllTextAsync(automaticJsonPath, automaticJson);
    using var library = new WordLibraryStore(automaticImportDirectory);
    var automaticResult = await importer.ImportToLibraryAsync(automaticJsonPath, english, library, null);
    Assert(automaticResult.Added == VocabularyImportService.MaxImportEntries + 1, "large JSON wordbook is automatically imported in batches without a whole-book limit");
    var importedBooks = library.QueryWordbooks(english.Id);
    Assert(importedBooks.Count == 1 && importedBooks[0].WordCount == VocabularyImportService.MaxImportEntries + 1, "complete imported dictionary is listed in the wordbook module");
    var bookPage = library.QueryWordbookEntries(english.Id, importedBooks[0].Id, "", 0, WordLibraryStore.PageSize);
    Assert(bookPage.Total == VocabularyImportService.MaxImportEntries + 1 && bookPage.Entries.Count == WordLibraryStore.PageSize, "large wordbook is stored on disk and read one page at a time");
    Assert(library.QueryWords(english.Id, "", 0, WordLibraryStore.PageSize).Total == 0, "imported dictionary entries do not flood the focused study list");
    var firstDailyFill = library.EnsureDailyWords(english.Id, DateTime.Today);
    Assert(firstDailyFill.AddedNow == 20 && library.QueryWords(english.Id, "", 0, 100).Total == 20, "default daily rule adds exactly 20 new words to the focused study list");
    Assert(library.EnsureDailyWords(english.Id, DateTime.Today).AddedNow == 0, "daily rule does not add the same quota twice after restart");
    library.SetDailyNewWordCount(english.Id, 30);
    Assert(library.EnsureDailyWords(english.Id, DateTime.Today).AddedNow == 10, "raising today's daily quota immediately fills only the difference");
    var manualCandidate = library.QueryWordbookEntries(english.Id, importedBooks[0].Id, "", 30, 1).Entries[0].Word;
    library.SetActiveWord(manualCandidate.Id, true);
    Assert(library.QueryWords(english.Id, "", 0, 100).Total == 31, "lighting a wordbook star manually adds that word to the study list");
    library.SetActiveWord(manualCandidate.Id, false);
    Assert(library.QueryWords(english.Id, "", 0, 100).Total == 30, "dimming a wordbook star removes that word without deleting the wordbook entry");
    Assert(library.QueryReviewWords(english.Id, "due", DateTime.Now, 200).Count == 30, "flashcards are sourced only from the focused study list");
    var repeatedResult = await importer.ImportToLibraryAsync(automaticJsonPath, english, library, null);
    Assert(repeatedResult.AlreadyComplete, "selecting an already completed wordbook does not import it twice");
    library.DeleteWordbook(importedBooks[0].Id);
    Assert(library.QueryWordbooks(english.Id).Count == 0 && library.QueryWords(english.Id, "", 0, 100).Total == 0, "deleting a wordbook removes its entries from the library and focused study list");

    var resumableJsonPath = Path.Combine(automaticImportDirectory, "resumable.json");
    var resumableJson = "[" + string.Join(",", Enumerable.Range(0, 2_501)
        .Select(i => $"{{\"word\":\"resume-{i}\",\"meaning\":\"meaning-{i}\"}}")) + "]";
    await File.WriteAllTextAsync(resumableJsonPath, resumableJson);
    using var pause = new CancellationTokenSource();
    var pauseProgress = new InlineProgress<WordImportProgress>(value =>
    {
        if (value.Processed >= VocabularyImportService.ImportBatchSize) pause.Cancel();
    });
    try { await importer.ImportToLibraryAsync(resumableJsonPath, japanese, library, null, pauseProgress, pause.Token); }
    catch (OperationCanceledException) { }
    var resumedResult = await importer.ImportToLibraryAsync(resumableJsonPath, japanese, library, null);
    Assert(resumedResult.Resumed && resumedResult.Processed == 2_501, "paused import resumes automatically from its last committed batch");
    Assert(library.QueryWordbookEntries(japanese.Id, null, "", 0, 1).Total == 2_501, "resumed import stores every wordbook entry exactly once");
    Assert(library.EnsureDailyWords(japanese.Id, DateTime.Today).AddedNow == 20, "resumed wordbook also follows the daily focused-word quota");
}
finally
{
    Microsoft.Data.Sqlite.SqliteConnection.ClearAllPools();
    Directory.Delete(automaticImportDirectory, true);
}

var progress = new FlashcardProgress { DueAt = DateTime.Today };
var beforeCorrect = DateTime.Now;
FlashcardScheduler.MarkCorrect(progress);
Assert(progress.Level == 1 && progress.DueAt >= beforeCorrect.AddMinutes(29) && progress.DueAt <= DateTime.Now.AddMinutes(31), "level 1 review uses the Mac 30-minute interval");
FlashcardScheduler.MarkIncorrect(progress);
Assert(progress.Level == 0 && progress.DueAt <= DateTime.Now && progress.DueAt >= DateTime.Now.AddSeconds(-2), "incorrect review resets level and becomes immediately due");

var curve = new FlashcardProgress();
var expectedHours = new[] { 0.5, 12d, 72d, 168d, 360d };
foreach (var expectedHoursFromNow in expectedHours)
{
    var before = DateTime.Now;
    FlashcardScheduler.MarkCorrect(curve);
    var actualHours = (curve.DueAt - before).TotalHours;
    Assert(Math.Abs(actualHours - expectedHoursFromNow) < 0.02, $"memory curve level {curve.Level} interval is {expectedHoursFromNow:g} hours");
}

var credentials = new WindowsCredentialStore();
const string temporary = "goals-temporary-credential-self-test";
credentials.Save(temporary);
Assert(credentials.Read() == temporary, "credential round-trip through Windows Credential Manager");
credentials.Delete();
Assert(credentials.Read() is null, "temporary credential is securely deleted");

Console.WriteLine("SELF TESTS COMPLETE");

file sealed class InlineProgress<T>(Action<T> callback) : IProgress<T>
{
    public void Report(T value) => callback(value);
}
