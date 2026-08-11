using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Goals.Windows.Models;
using Goals.Windows.Services;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class FlashcardsPage : UserControl
{
    private enum ReviewPhase { Answering, CorrectDetail, WrongCorrection, CorrectionComplete }

    private readonly MainViewModel _vm;
    private List<VocabularyWord> _queue = [];
    private int _index;
    private string _filter = "due";
    private string _trackId = "";
    private bool _isJudging;
    private bool? _judgmentCorrect;
    private bool _isStateSubscribed;
    private int _queueLoadVersion;
    private ReviewPhase _phase = ReviewPhase.Answering;
    private VocabularyWord? Current => _queue.Count == 0 ? null : _queue[Math.Clamp(_index, 0, _queue.Count - 1)];

    public FlashcardsPage(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        AddHandler(Keyboard.PreviewKeyDownEvent, new KeyEventHandler(Page_PreviewKeyDown), true);
        Loaded += Page_Loaded;
        Unloaded += Page_Unloaded;
    }

    private async void Page_Loaded(object sender, RoutedEventArgs e)
    {
        if (!_isStateSubscribed)
        {
            _vm.StateChanged += Changed;
            _isStateSubscribed = true;
        }
        _trackId = _vm.CurrentTrack.Id;
        await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Render);
        if (IsLoaded) _ = RefreshQueueAsync();
    }

    private void Page_Unloaded(object sender, RoutedEventArgs e)
    {
        _queueLoadVersion++;
        if (_isStateSubscribed)
        {
            _vm.StateChanged -= Changed;
            _isStateSubscribed = false;
        }
    }

    private void Changed(object? s, EventArgs e)
    {
        if (_trackId != _vm.CurrentTrack.Id)
            Dispatcher.Invoke(() => { _trackId = _vm.CurrentTrack.Id; _ = RefreshQueueAsync(); });
        else
            Dispatcher.Invoke(UpdateStats);
    }

    private async Task RefreshQueueAsync()
    {
        var requestVersion = ++_queueLoadVersion;
        ReviewStatus.Text = "正在加载复习队列…";
        await Dispatcher.InvokeAsync(() => { }, DispatcherPriority.Render);
        var filter = _filter;
        var queue = await Task.Run(() => _vm.GetReviewWords(filter).ToList());
        if (!IsLoaded || requestVersion != _queueLoadVersion) return;
        _queue = queue;
        _index = 0;
        ShowCurrent();
        var summary = await Task.Run(_vm.GetReviewSummary);
        if (!IsLoaded || requestVersion != _queueLoadVersion) return;
        DueCount.Text = summary.Due.ToString("N0");
        StartedCount.Text = summary.Started.ToString("N0");
        MasteredCount.Text = summary.Mastered.ToString("N0");
    }

    private void ShowCurrent()
    {
        _phase = ReviewPhase.Answering;
        _judgmentCorrect = null;
        _isJudging = false;
        AnswerDetails.Visibility = Visibility.Collapsed;
        AnswerEntryPanel.Visibility = Visibility.Visible;
        CorrectionEntryPanel.Visibility = Visibility.Collapsed;
        AnswerBox.Clear();
        CorrectionBox.Clear();
        ReviewStatus.Text = "";
        SubmitButton.Content = "➤ 提交判分";
        AdvanceButton.Content = "› 跳过";
        AdvanceButton.IsEnabled = true;
        ShortcutHint.Text = "回车：提交答案";

        var word = Current;
        var available = word is not null;
        EmptyText.Visibility = available ? Visibility.Collapsed : Visibility.Visible;
        WordText.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
        SubmitButton.IsEnabled = available;
        AnswerBox.IsEnabled = available;
        FavoriteButton.IsEnabled = available;
        AnswerEntryPanel.Visibility = available ? Visibility.Visible : Visibility.Collapsed;
        AdvanceButton.IsEnabled = available;
        if (word is null)
        {
            PronunciationLabel.Text = PronunciationText.Text = RomanizationText.Text = TagText.Text = QueueInfo.Text = "";
            return;
        }

        var progress = _vm.ProgressFor(word);
        WordText.Text = word.Word;
        PronunciationLabel.Text = _vm.IsJapanese ? "假名 / 罗马音" : "音标";
        PronunciationText.Text = _vm.IsJapanese ? word.Reading : word.Phonetic;
        RomanizationText.Text = _vm.IsJapanese ? word.Romanization : word.PartOfSpeech;
        MeaningText.Text = $"{word.PartOfSpeech}  {word.Meaning}";
        MnemonicText.Text = string.IsNullOrWhiteSpace(word.Mnemonic) ? "" : $"助记：{word.Mnemonic}";
        MnemonicText.Visibility = string.IsNullOrWhiteSpace(word.Mnemonic) ? Visibility.Collapsed : Visibility.Visible;
        ExampleText.Text = word.Example;
        ExampleText.Visibility = string.IsNullOrWhiteSpace(word.Example) ? Visibility.Collapsed : Visibility.Visible;
        ExampleTranslationText.Text = word.ExampleTranslation;
        ExampleTranslationText.Visibility = string.IsNullOrWhiteSpace(word.ExampleTranslation) ? Visibility.Collapsed : Visibility.Visible;
        PhrasesText.Text = word.Phrases.Count == 0 ? "" : string.Join(" · ", word.Phrases);
        PhrasesText.Visibility = word.Phrases.Count == 0 ? Visibility.Collapsed : Visibility.Visible;
        TagText.Text = word.Tag;
        QueueInfo.Text = $"{_index + 1} / {_queue.Count}  ·  {word.Tag}  ·  等级 {progress.Level}/5";
        FavoriteButton.Content = _vm.IsFavorite(word) ? "★ 取消收藏" : "☆ 收藏";
        FocusLater(AnswerBox);
    }

    private void UpdateStats()
    {
        var summary = _vm.GetReviewSummary();
        DueCount.Text = summary.Due.ToString("N0");
        StartedCount.Text = summary.Started.ToString("N0");
        MasteredCount.Text = summary.Mastered.ToString("N0");
    }

    private async void Page_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        var key = e.Key == Key.System ? e.SystemKey : e.Key;
        var isEnter = key is Key.Enter or Key.Return || e.ImeProcessedKey is Key.Enter or Key.Return;
        if (!isEnter || _isJudging || Keyboard.FocusedElement is Button) return;

        e.Handled = true;
        switch (_phase)
        {
            case ReviewPhase.Answering:
                await SubmitAnswer();
                break;
            case ReviewPhase.WrongCorrection:
                ConfirmCorrection();
                break;
            case ReviewPhase.CorrectDetail:
            case ReviewPhase.CorrectionComplete:
                AdvanceAfterReview();
                break;
        }
    }

    private async void Submit_Click(object sender, RoutedEventArgs e) => await SubmitAnswer();
    private void Correction_Click(object sender, RoutedEventArgs e) => ConfirmCorrection();

    private async Task SubmitAnswer()
    {
        var word = Current;
        if (word is null || _phase != ReviewPhase.Answering || _isJudging) return;
        var answer = AnswerBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(answer))
        {
            ReviewStatus.Text = "请输入中文含义，或输入、表示不认识。";
            FocusLater(AnswerBox);
            return;
        }

        _isJudging = true;
        SubmitButton.IsEnabled = false;
        ReviewStatus.Text = "正在按核心义项判分…";
        var unknown = answer is "、" or ",";
        var correct = !unknown && LocalMatch(word.Meaning, answer);
        var reason = correct ? "已命中标准释义中的核心义项。" : unknown ? "你已用、标记为不认识。" : "本地未命中核心义项。";

        if (!correct && !unknown && _vm.DeepSeek.HasKey)
        {
            try
            {
                correct = await _vm.DeepSeek.JudgeAnswerAsync(word, answer);
                reason = correct ? "智能判分确认命中核心义项。" : "智能判分未命中核心义项。";
            }
            catch { reason = "智能判分不可用，本地也未命中核心义项。"; }
        }

        ApplyJudgment(word, correct, reason);
    }

    private void ApplyJudgment(VocabularyWord word, bool correct, string reason)
    {
        var progress = _vm.ProgressFor(word);
        if (correct)
            FlashcardScheduler.MarkCorrect(progress);
        else
        {
            FlashcardScheduler.MarkIncorrect(progress);
            _vm.EnsureFavorite(word);
        }

        _isJudging = false;
        _judgmentCorrect = correct;
        _phase = correct ? ReviewPhase.CorrectDetail : ReviewPhase.WrongCorrection;
        AnswerDetails.Visibility = Visibility.Visible;
        AnswerEntryPanel.Visibility = Visibility.Collapsed;
        JudgmentText.Text = correct ? "✓ 回答正确" : "× 回答错误";
        JudgmentText.Foreground = correct ? new SolidColorBrush(Color.FromRgb(45, 111, 85)) : new SolidColorBrush(Color.FromRgb(165, 46, 46));
        JudgmentBadge.Background = correct ? new SolidColorBrush(Color.FromRgb(231, 241, 235)) : new SolidColorBrush(Color.FromRgb(248, 232, 232));

        if (correct)
        {
            CorrectionEntryPanel.Visibility = Visibility.Collapsed;
            ReviewStatus.Text = $"{reason} 下次复习：{FormatReviewTime(progress.DueAt)}";
            AdvanceButton.Content = "› 继续";
            AdvanceButton.IsEnabled = true;
            ShortcutHint.Text = "详情已展开 · 按回车进入下一词";
            FocusLater(AdvanceButton);
        }
        else
        {
            CorrectionEntryPanel.Visibility = Visibility.Visible;
            CorrectionBox.Clear();
            ReviewStatus.Text = $"{reason} 等级已重置为 0，并加入错词收藏；请重新输入一个正确释义。";
            AdvanceButton.Content = "› 先复述";
            AdvanceButton.IsEnabled = false;
            ShortcutHint.Text = "看着详情重新输入一个正确释义，再按回车确认";
            FocusLater(CorrectionBox);
        }

        _vm.SaveReview(word);
        UpdateStats();
    }

    private void ConfirmCorrection()
    {
        var word = Current;
        if (word is null || _phase != ReviewPhase.WrongCorrection) return;
        if (!LocalMatch(word.Meaning, CorrectionBox.Text))
        {
            ReviewStatus.Text = "还没有命中卡片中的核心含义，请看一遍详情后重新输入。";
            FocusLater(CorrectionBox);
            return;
        }

        _phase = ReviewPhase.CorrectionComplete;
        CorrectionEntryPanel.Visibility = Visibility.Collapsed;
        ReviewStatus.Text = "复述完成；继续后这个词会移到本轮队列末尾再次回炉。";
        AdvanceButton.Content = "› 继续";
        AdvanceButton.IsEnabled = true;
        ShortcutHint.Text = "复述已完成 · 按回车继续";
        FocusLater(AdvanceButton);
    }

    private async void Advance_Click(object sender, RoutedEventArgs e)
    {
        switch (_phase)
        {
            case ReviewPhase.Answering:
                if (string.IsNullOrWhiteSpace(AnswerBox.Text)) SkipCurrentCard();
                else await SubmitAnswer();
                break;
            case ReviewPhase.WrongCorrection:
                ConfirmCorrection();
                break;
            case ReviewPhase.CorrectDetail:
            case ReviewPhase.CorrectionComplete:
                AdvanceAfterReview();
                break;
        }
    }

    private void AdvanceAfterReview()
    {
        if (_queue.Count == 0) return;
        var reviewed = Current;
        if (_filter == "due" && reviewed is not null)
        {
            var oldIndex = _index;
            _queue.RemoveAt(oldIndex);
            if (_judgmentCorrect == false) _queue.Add(reviewed);
            if (_queue.Count == 0) _index = 0;
            else if (oldIndex >= _queue.Count) _index = 0;
            else _index = oldIndex;
        }
        else
        {
            _index = (_index + 1) % _queue.Count;
        }
        ShowCurrent();
        UpdateStats();
    }

    private static bool LocalMatch(string expected, string answer)
    {
        static string Clean(string value) => new(value.Where(c => !char.IsWhiteSpace(c) && !"，,；;。.!！？?的了".Contains(c)).ToArray());
        var a = Clean(answer.Trim());
        if (a.Length == 0) return false;
        return expected.Split(['；', ';', '，', ',', '、'], StringSplitOptions.RemoveEmptyEntries)
            .Select(Clean)
            .Any(x => x.Equals(a, StringComparison.OrdinalIgnoreCase)
                      || a.Length >= 2 && x.Contains(a, StringComparison.OrdinalIgnoreCase)
                      || x.Length >= 2 && a.Contains(x, StringComparison.OrdinalIgnoreCase));
    }

    private static string FormatReviewTime(DateTime dueAt)
    {
        if (dueAt.Date == DateTime.Today) return $"今天 {dueAt:HH:mm}";
        if (dueAt.Date == DateTime.Today.AddDays(1)) return $"明天 {dueAt:HH:mm}";
        return dueAt.ToString("yyyy-MM-dd HH:mm");
    }

    private void FocusLater(Control control) => Dispatcher.BeginInvoke(DispatcherPriority.Input, new Action(() => control.Focus()));
    private void Filter_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is string filter) { _filter = filter; _ = RefreshQueueAsync(); } }
    private void Previous_Click(object sender, RoutedEventArgs e) { if (_queue.Count == 0) return; _index = (_index - 1 + _queue.Count) % _queue.Count; ShowCurrent(); }
    private void SkipCurrentCard() { if (_queue.Count == 0) return; _index = (_index + 1) % _queue.Count; ShowCurrent(); }
    private void Favorite_Click(object sender, RoutedEventArgs e) { if (Current is { } word) { _vm.ToggleFavorite(word); FavoriteButton.Content = _vm.IsFavorite(word) ? "★ 取消收藏" : "☆ 收藏"; } }
    private void Banish_Click(object sender, RoutedEventArgs e)
    {
        if (Current is not { } word) return;
        _vm.SetBanished(word, true);
        _queue.Remove(word);
        if (_index >= _queue.Count) _index = 0;
        ShowCurrent();
        ReviewStatus.Text = "词条已斩除，可在错词收藏中恢复。";
        UpdateStats();
    }
}
