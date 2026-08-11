using System.Windows;
using System.Windows.Controls;
using System.Windows.Threading;
using Goals.Windows.Infrastructure;
using Goals.Windows.Models;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class MainWindow : Window
{
    private readonly MainViewModel _vm;
    private readonly DispatcherTimer _dailyWordTimer = new() { Interval = TimeSpan.FromMinutes(1) };
    private readonly Dictionary<string, UserControl> _studyPageCache = new(StringComparer.Ordinal);
    private DateTime _lastDailyWordDate = DateTime.Today;

    public MainWindow(MainViewModel viewModel)
    {
        InitializeComponent();
        SmoothScrollBehavior.Enable(this);
        _vm = viewModel;
        DataContext = viewModel;
        _vm.StateChanged += Vm_StateChanged;
        _dailyWordTimer.Tick += (_, _) =>
        {
            if (_lastDailyWordDate == DateTime.Today || !_vm.IsLanguageStudy) return;
            _lastDailyWordDate = DateTime.Today;
            _vm.EnsureDailyWords();
        };
        Loaded += (_, _) =>
        {
            SyncChrome();
            Navigate("goals");
            _dailyWordTimer.Start();
        };
        Closed += (_, _) => { _dailyWordTimer.Stop(); _vm.StateChanged -= Vm_StateChanged; };
    }

    private void Vm_StateChanged(object? sender, EventArgs e) => Dispatcher.Invoke(SyncChrome);

    private void SyncChrome()
    {
        WordsButton.Visibility = _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        WordbooksButton.Visibility = _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        FlashcardsButton.Visibility = _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        MistakesButton.Visibility = _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        TranslationButton.Visibility = _vm.IsJapanese || _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        WritingButton.Visibility = _vm.IsJapanese || _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        RootsButton.Visibility = _vm.IsJapanese || _vm.IsOther ? Visibility.Collapsed : Visibility.Visible;
        WordsCaption.Text = _vm.IsJapanese ? "N4 词语、假名与例句" : "高频词与例句";
        ContextLabel.Text = _vm.CurrentTrack.Mode switch
        {
            LearningMode.Japanese => "JLPT N4 · 词汇 · 执行 · 复盘",
            LearningMode.Other => "自定义目标 · 计划 · 执行",
            _ => "CET-6 · 目标 · 计划 · 执行"
        };
        DateDot.Fill = _vm.IsJapanese ? (System.Windows.Media.Brush)FindResource("PlumBrush") : (System.Windows.Media.Brush)FindResource("NavyBrush");
        CompletionText.Text = $"{_vm.CompletedToday}/{_vm.TotalToday}";
        CompletionBar.Value = _vm.CompletionPercent;
        if (_vm.IsJapanese && _vm.CurrentPage is "translation" or "writing" or "roots") Navigate("goals");
        if (_vm.IsOther && _vm.CurrentPage is "wordbooks" or "words" or "translation" or "writing" or "roots" or "flashcards" or "mistakes") Navigate("goals");
    }

    private void Nav_Click(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: string page }) Navigate(page);
    }

    public void Navigate(string page, bool updateViewModel = true)
    {
        if (updateViewModel) _vm.Navigate(page);
        foreach (var button in NavPanel.Children.OfType<Button>())
            button.Tag = button.Name switch
            {
                "GoalsButton" when page == "goals" => "selected",
                "PlanButton" when page == "plan" => "selected",
                "TodayButton" when page == "today" => "selected",
                "WordbooksButton" when page == "wordbooks" => "selected",
                "WordsButton" when page == "words" => "selected",
                "TranslationButton" when page == "translation" => "selected",
                "WritingButton" when page == "writing" => "selected",
                "RootsButton" when page == "roots" => "selected",
                "FlashcardsButton" when page == "flashcards" => "selected",
                "MistakesButton" when page == "mistakes" => "selected",
                "SettingsButton" when page == "settings" => "selected",
                _ => button.Name switch
                {
                    "GoalsButton" => "goals", "PlanButton" => "plan", "TodayButton" => "today", "WordbooksButton" => "wordbooks", "WordsButton" => "words",
                    "TranslationButton" => "translation", "WritingButton" => "writing", "RootsButton" => "roots",
                    "FlashcardsButton" => "flashcards", "MistakesButton" => "mistakes", _ => "settings"
                }
            };

        PageHost.Content = page is "wordbooks" or "words" or "flashcards"
            ? GetStudyPage(page)
            : CreatePage(page);
    }

    private UserControl GetStudyPage(string page)
    {
        if (_studyPageCache.TryGetValue(page, out var cached)) return cached;
        var created = CreatePage(page);
        _studyPageCache[page] = created;
        return created;
    }

    private UserControl CreatePage(string page) => page switch
    {
            "plan" => new PlanPage(_vm, this),
            "today" => new TodayPage(_vm),
            "wordbooks" => new WordbooksPage(_vm),
            "words" => new VocabularyPage(_vm, this),
            "translation" => new AiPracticePage(_vm, false, this),
            "writing" => new AiPracticePage(_vm, true, this),
            "roots" => new RootsPage(),
            "flashcards" => new FlashcardsPage(_vm),
            "mistakes" => new MistakesPage(_vm),
            "settings" => new SettingsPage(_vm),
            _ => new DashboardPage(_vm, this)
    };
}
