using System.Collections.ObjectModel;
using Goals.Windows.Infrastructure;
using Goals.Windows.Models;
using Goals.Windows.Services;

namespace Goals.Windows.ViewModels;

public sealed class MainViewModel : ObservableObject
{
    private readonly AppDataStore _store;
    private readonly Dictionary<string, FlashcardProgress> _libraryProgress = new(StringComparer.Ordinal);
    private StudyTrack _currentTrack;
    private PlanSheet _currentPlan;
    private string _currentPage = "goals";

    public MainViewModel(AppState state, AppDataStore store, DeepSeekService deepSeek, WordLibraryStore library, LocalTranslationService localTranslation)
    {
        State = state;
        _store = store;
        DeepSeek = deepSeek;
        Library = library;
        LocalTranslation = localTranslation;
        _currentTrack = state.Tracks.FirstOrDefault(x => x.Id == state.CurrentTrackId) ?? state.Tracks[0];
        if (_currentTrack.Plans.Count == 0) _currentTrack.Plans.Add(new PlanSheet());
        _currentPlan = _currentTrack.Plans[0];
        if (_currentTrack.Mode is LearningMode.English or LearningMode.Japanese)
            EnsureDailyWordsInBackground();
    }

    public event EventHandler? StateChanged;
    public AppState State { get; }
    public DeepSeekService DeepSeek { get; }
    public WordLibraryStore Library { get; }
    public LocalTranslationService LocalTranslation { get; }
    public ObservableCollection<StudyTrack> Tracks => State.Tracks;

    public StudyTrack CurrentTrack
    {
        get => _currentTrack;
        set
        {
            if (value is null || !Set(ref _currentTrack, value)) return;
            State.CurrentTrackId = value.Id;
            _libraryProgress.Clear();
            if (value.Plans.Count == 0) value.Plans.Add(new PlanSheet());
            CurrentPlan = value.Plans[0];
            if (value.Mode is LearningMode.English or LearningMode.Japanese)
                EnsureDailyWordsInBackground();
            if (value.Mode == LearningMode.Japanese && CurrentPage is "translation" or "writing" or "roots")
                CurrentPage = "goals";
            if (value.Mode == LearningMode.Other && CurrentPage is "wordbooks" or "words" or "translation" or "writing" or "roots" or "flashcards" or "mistakes")
                CurrentPage = "goals";
            SaveAndRefresh();
        }
    }

    public PlanSheet CurrentPlan
    {
        get => _currentPlan;
        set
        {
            if (value is null || !Set(ref _currentPlan, value)) return;
            Refresh();
        }
    }

    public string CurrentPage
    {
        get => _currentPage;
        set { Set(ref _currentPage, value); }
    }

    public bool IsJapanese => CurrentTrack.Mode == LearningMode.Japanese;
    public bool IsOther => CurrentTrack.Mode == LearningMode.Other;
    public bool IsLanguageStudy => CurrentTrack.Mode is LearningMode.English or LearningMode.Japanese;
    public string DateLabel => DateTime.Today.ToString("yyyy-MM-dd");
    public IReadOnlyList<StudyTask> TodayTasks => State.Tasks.Where(x => x.TrackId == CurrentTrack.Id && x.Date.Date == DateTime.Today).OrderBy(x => x.Time).ToList();
    public IReadOnlyList<VocabularyWord> CurrentWords => State.Words.Where(x => x.TrackId == CurrentTrack.Id).ToList();
    public int CompletedToday => TodayTasks.Count(x => x.IsDone);
    public int TotalToday => TodayTasks.Count;
    public double CompletionPercent => TotalToday == 0 ? 0 : CompletedToday * 100d / TotalToday;

    public void Navigate(string page) => CurrentPage = page;

    public void AddTask(string title, string time = "19:30", DateTime? date = null)
    {
        if (string.IsNullOrWhiteSpace(title)) return;
        State.Tasks.Add(new StudyTask
        {
            TrackId = CurrentTrack.Id,
            PlanId = CurrentPlan.Id,
            Title = title.Trim(),
            Time = string.IsNullOrWhiteSpace(time) ? "19:30" : time.Trim(),
            Date = date?.Date ?? DateTime.Today
        });
        SaveAndRefresh();
    }

    public void ToggleTask(StudyTask task)
    {
        task.IsDone = !task.IsDone;
        SaveAndRefresh();
    }

    public void DeleteTask(StudyTask task)
    {
        State.Tasks.Remove(task);
        SaveAndRefresh();
    }

    public StudyTrack AddTrack(string title, LearningMode mode, string focus)
    {
        var track = new StudyTrack
        {
            Title = title.Trim(), Mode = mode,
            Category = mode switch
            {
                LearningMode.Japanese => "日语学习",
                LearningMode.English => "英语学习",
                _ => "自定义学习"
            },
            Focus = string.IsNullOrWhiteSpace(focus) ? "把目标拆成每天可执行、可勾选、可复盘的任务。" : focus.Trim(),
            Plans = [new PlanSheet()]
        };
        State.Tracks.Add(track);
        CurrentTrack = track;
        SaveAndRefresh();
        return track;
    }

    public bool DeleteCurrentTrack()
    {
        if (State.Tracks.Count <= 1) return false;
        var id = CurrentTrack.Id;
        State.Tracks.Remove(CurrentTrack);
        foreach (var item in State.Tasks.Where(x => x.TrackId == id).ToList()) State.Tasks.Remove(item);
        foreach (var item in State.Words.Where(x => x.TrackId == id).ToList())
        {
            State.Words.Remove(item);
            var progress = State.Progress.FirstOrDefault(x => x.WordId == item.Id);
            if (progress is not null) State.Progress.Remove(progress);
            State.FavoriteWordIds.Remove(item.Id);
        }
        Library.DeleteTrack(id);
        CurrentTrack = State.Tracks[0];
        SaveAndRefresh();
        return true;
    }

    public PlanSheet AddPlan(string title)
    {
        var plan = new PlanSheet { Title = string.IsNullOrWhiteSpace(title) ? $"计划表 {CurrentTrack.Plans.Count + 1:00}" : title.Trim() };
        CurrentTrack.Plans.Add(plan);
        CurrentPlan = plan;
        SaveAndRefresh();
        return plan;
    }

    public void SavePlan(string title, string content)
    {
        CurrentPlan.Title = string.IsNullOrWhiteSpace(title) ? CurrentPlan.Title : title.Trim();
        CurrentPlan.Content = content.Trim();
        CurrentPlan.UpdatedAt = DateTime.Now;
        SaveAndRefresh();
    }

    public void ApplyAiPlan(AiPlanResult result)
    {
        CurrentPlan.Content = result.Summary;
        CurrentPlan.UpdatedAt = DateTime.Now;
        foreach (var task in result.Tasks.Where(x => !string.IsNullOrWhiteSpace(x.Title)))
        {
            State.Tasks.Add(new StudyTask
            {
                TrackId = CurrentTrack.Id, PlanId = CurrentPlan.Id, Source = "deepseek",
                Date = DateTime.Today.AddDays(Math.Clamp(task.DayOffset, 0, 30)),
                Time = string.IsNullOrWhiteSpace(task.Time) ? "19:30" : task.Time,
                Title = task.Title.Trim()
            });
        }
        SaveAndRefresh();
    }

    public void AddWord(VocabularyWord word)
    {
        if (State.Words.Any(x => x.TrackId == word.TrackId && x.Word.Equals(word.Word, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidOperationException("这个词条已经在当前单词本中。 ");
        State.Words.Add(word);
        State.Progress.Add(new FlashcardProgress { WordId = word.Id, DueAt = DateTime.Today });
        SaveAndRefresh();
    }

    public (int Added, int Duplicates) AddWords(IEnumerable<VocabularyWord> words, StudyTrack? targetTrack = null)
    {
        var target = targetTrack ?? CurrentTrack;
        var existing = new HashSet<string>(
            State.Words.Where(x => x.TrackId == target.Id).Select(x => x.Word.Trim()),
            StringComparer.OrdinalIgnoreCase);
        var knownIds = new HashSet<string>(State.Words.Select(x => x.Id), StringComparer.OrdinalIgnoreCase);
        var added = 0;
        var duplicates = 0;
        foreach (var word in words)
        {
            word.Word = word.Word.Trim();
            word.Meaning = word.Meaning.Trim();
            if (string.IsNullOrWhiteSpace(word.Word) || string.IsNullOrWhiteSpace(word.Meaning) || !existing.Add(word.Word))
            {
                duplicates++;
                continue;
            }

            word.TrackId = target.Id;
            if (string.IsNullOrWhiteSpace(word.Id) || !knownIds.Add(word.Id))
            {
                word.Id = Guid.NewGuid().ToString("N");
                knownIds.Add(word.Id);
            }
            State.Words.Add(word);
            State.Progress.Add(new FlashcardProgress { WordId = word.Id, DueAt = DateTime.Today });
            added++;
        }
        if (added > 0) SaveAndRefresh();
        return (added, duplicates);
    }

    public void DeleteWord(VocabularyWord word)
    {
        if (WordLibraryStore.IsLibraryWord(word))
        {
            Library.SetActiveWord(word.Id, false);
            Refresh();
            return;
        }
        State.Words.Remove(word);
        var progress = State.Progress.FirstOrDefault(x => x.WordId == word.Id);
        if (progress is not null) State.Progress.Remove(progress);
        State.FavoriteWordIds.Remove(word.Id);
        SaveAndRefresh();
    }

    public FlashcardProgress ProgressFor(VocabularyWord word)
    {
        if (WordLibraryStore.IsLibraryWord(word))
        {
            if (_libraryProgress.TryGetValue(word.Id, out var stored)) return stored;
            stored = Library.GetProgress(word);
            _libraryProgress[word.Id] = stored;
            return stored;
        }
        var progress = State.Progress.FirstOrDefault(x => x.WordId == word.Id);
        if (progress is not null) return progress;
        progress = new FlashcardProgress { WordId = word.Id, DueAt = DateTime.Today };
        State.Progress.Add(progress);
        return progress;
    }

    public bool IsFavorite(VocabularyWord word) => WordLibraryStore.IsLibraryWord(word)
        ? Library.IsFavorite(word.Id)
        : State.FavoriteWordIds.Contains(word.Id);

    public void ToggleFavorite(VocabularyWord word)
    {
        if (WordLibraryStore.IsLibraryWord(word))
        {
            Library.SetFavorite(word.Id, !IsFavorite(word));
            Refresh();
            return;
        }
        if (IsFavorite(word)) State.FavoriteWordIds.Remove(word.Id);
        else State.FavoriteWordIds.Add(word.Id);
        SaveAndRefresh();
    }

    public void EnsureFavorite(VocabularyWord word)
    {
        if (IsFavorite(word)) return;
        if (WordLibraryStore.IsLibraryWord(word)) Library.SetFavorite(word.Id, true);
        else State.FavoriteWordIds.Add(word.Id);
    }

    public void SetBanished(VocabularyWord word, bool value)
    {
        ProgressFor(word).IsBanished = value;
        if (WordLibraryStore.IsLibraryWord(word))
        {
            Library.SaveProgress(ProgressFor(word));
            Refresh();
            return;
        }
        SaveAndRefresh();
    }

    public void SaveReview(VocabularyWord word)
    {
        if (WordLibraryStore.IsLibraryWord(word)) Library.SaveProgress(ProgressFor(word));
        else _store.Save(State);
        Refresh();
    }

    /// <summary>
    /// Translates Japanese text (dictionary glosses) to Chinese. Prefers the
    /// offline local model; falls back to DeepSeek when no model is available.
    /// Returns null when neither engine can serve the request.
    /// </summary>
    public async Task<TranslationResult?> TranslateJapaneseAsync(string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        if (LocalTranslation.ModelFound || LocalTranslation.IsLoaded)
        {
            try
            {
                var local = await LocalTranslation.TranslateAsync(text, cancellationToken);
                if (!string.IsNullOrWhiteSpace(local)) return new TranslationResult(local, "本地模型");
            }
            catch (OperationCanceledException) { throw; }
            catch { }
        }
        if (DeepSeek.HasKey)
        {
            try
            {
                var result = await DeepSeek.TranslateJapaneseSelectionAsync(text, cancellationToken);
                if (!string.IsNullOrWhiteSpace(result)) return new TranslationResult(result.Trim(), "DeepSeek");
            }
            catch (OperationCanceledException) { throw; }
            catch { }
        }
        return null;
    }

    public async Task<TranslationResult?> TranslateJapaneseLocalAsync(string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text)) return null;
        try
        {
            var local = await LocalTranslation.TranslateAsync(text, cancellationToken);
            if (!string.IsNullOrWhiteSpace(local)) return new TranslationResult(local, "本地模型");
        }
        catch (OperationCanceledException) { throw; }
        catch { }
        return null;
    }

    public async Task<TranslationResult?> TranslateJapaneseWithDeepSeekAsync(string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(text) || !DeepSeek.HasKey) return null;
        try
        {
            var result = await DeepSeek.TranslateJapaneseSelectionAsync(text, cancellationToken);
            if (!string.IsNullOrWhiteSpace(result)) return new TranslationResult(result.Trim(), "DeepSeek");
        }
        catch (OperationCanceledException) { throw; }
        catch { }
        return null;
    }

    public WordLibraryPage QueryVocabulary(string query, int offset = 0, int limit = WordLibraryStore.PageSize)
    {
        query = query.Trim();
        var local = CurrentWords
            .Where(x => string.IsNullOrWhiteSpace(query) || $"{x.Word} {x.Reading} {x.Romanization} {x.Meaning} {x.Tag}".Contains(query, StringComparison.OrdinalIgnoreCase))
            .OrderBy(x => x.Word, StringComparer.OrdinalIgnoreCase)
            .ToList();
        var localFavoriteCount = local.Count(IsFavorite);
        var output = new List<VocabularyWord>(limit);
        if (offset < local.Count)
            output.AddRange(local.Skip(offset).Take(limit));
        var libraryOffset = Math.Max(0, offset - local.Count);
        var remaining = limit - output.Count;
        var imported = Library.QueryWords(CurrentTrack.Id, query, libraryOffset, Math.Max(1, remaining));
        if (remaining > 0) output.AddRange(imported.Words.Take(remaining));
        return new WordLibraryPage(output, local.Count + imported.Total, localFavoriteCount + imported.FavoriteCount);
    }

    public IReadOnlyList<VocabularyWord> GetReviewWords(string filter, int limit = WordLibraryStore.ReviewBatchSize)
    {
        var now = DateTime.Now;
        var local = CurrentWords.Where(x => !ProgressFor(x).IsBanished);
        local = filter switch
        {
            "all" => local,
            "favorite" => local.Where(IsFavorite),
            "hard" => local.Where(x => x.Difficulty >= 4 || ProgressFor(x).Level == 0 && ProgressFor(x).ReviewCount > 0),
            _ => local.Where(x => ProgressFor(x).DueAt <= now).OrderBy(x => ProgressFor(x).DueAt)
        };
        var result = local.Take(limit).ToList();
        if (result.Count < limit)
            result.AddRange(Library.QueryReviewWords(CurrentTrack.Id, filter, now, limit - result.Count));
        return result;
    }

    public WordReviewSummary GetReviewSummary()
    {
        var now = DateTime.Now;
        var imported = Library.GetReviewSummary(CurrentTrack.Id, now);
        return new WordReviewSummary(
            imported.Due + CurrentWords.Count(x => !ProgressFor(x).IsBanished && ProgressFor(x).DueAt <= now),
            imported.Started + CurrentWords.Count(x => ProgressFor(x).ReviewCount > 0),
            imported.Mastered + CurrentWords.Count(x => ProgressFor(x).Level >= 5));
    }

    public IReadOnlyList<VocabularyWord> GetSpecialWords(bool banished, string query, int limit = 500)
    {
        var local = CurrentWords
            .Where(x => banished ? ProgressFor(x).IsBanished : IsFavorite(x))
            .Where(x => string.IsNullOrWhiteSpace(query) || $"{x.Word} {x.Reading} {x.Meaning}".Contains(query, StringComparison.OrdinalIgnoreCase))
            .Take(limit)
            .ToList();
        if (local.Count < limit)
            local.AddRange(Library.QuerySpecialWords(CurrentTrack.Id, banished, query, limit - local.Count));
        return local;
    }

    public IReadOnlyList<WordbookInfo> GetWordbooks() => Library.QueryWordbooks(CurrentTrack.Id);

    public WordbookEntryPage QueryWordbookEntries(string? sourceId, string query, int offset = 0, int limit = WordLibraryStore.PageSize) =>
        Library.QueryWordbookEntries(CurrentTrack.Id, sourceId, query, offset, limit, CurrentTrack.Mode == LearningMode.Japanese);

    public bool IsInStudyList(VocabularyWord word) => !WordLibraryStore.IsLibraryWord(word) || Library.IsActiveWord(word.Id);

    public void ToggleStudyList(VocabularyWord word)
    {
        if (!WordLibraryStore.IsLibraryWord(word)) return;
        Library.SetActiveWord(word.Id, !Library.IsActiveWord(word.Id));
        Refresh();
    }

    public int DailyNewWordCount => Library.GetDailyNewWordCount(CurrentTrack.Id);

    public DailyWordFillResult SetDailyNewWordCount(int count)
    {
        Library.SetDailyNewWordCount(CurrentTrack.Id, count);
        var result = Library.EnsureDailyWords(CurrentTrack.Id, DateTime.Today);
        Refresh();
        return result;
    }

    public DailyWordFillResult EnsureDailyWords()
    {
        var result = Library.EnsureDailyWords(CurrentTrack.Id, DateTime.Today);
        Refresh();
        return result;
    }

    public void EnsureDailyWordsInBackground()
    {
        var trackId = CurrentTrack.Id;
        Task.Run(() => Library.EnsureDailyWords(trackId, DateTime.Today));
    }

    public void DeleteWordbook(WordbookInfo wordbook)
    {
        Library.DeleteWordbook(wordbook.Id);
        _libraryProgress.Clear();
        Refresh();
    }

    public void SaveAndRefresh()
    {
        Refresh();
        _store.SaveAsync(State);
    }

    public void SaveNow()
    {
        _store.Save(State);
    }

    public void Refresh()
    {
        Raise(nameof(CurrentTrack));
        Raise(nameof(CurrentPlan));
        Raise(nameof(IsJapanese));
        Raise(nameof(IsOther));
        Raise(nameof(IsLanguageStudy));
        Raise(nameof(TodayTasks));
        Raise(nameof(CurrentWords));
        Raise(nameof(CompletedToday));
        Raise(nameof(TotalToday));
        Raise(nameof(CompletionPercent));
        StateChanged?.Invoke(this, EventArgs.Empty);
    }
}

public sealed record TranslationResult(string Text, string Engine);
