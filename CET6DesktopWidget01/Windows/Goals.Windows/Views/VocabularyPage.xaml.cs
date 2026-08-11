using System.Windows;
using System.Windows.Controls;
using Goals.Windows.Models;
using Goals.Windows.Services;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class VocabularyPage : UserControl
{
    private const int VocabularyPageSize = 12;
    private readonly MainViewModel _vm;
    private readonly MainWindow _main;
    private readonly HashSet<string> _selectedWordIds = new(StringComparer.Ordinal);
    private IReadOnlyList<VocabularyWord> _visibleWords = [];
    private int _page;
    private bool _syncingSelection;
    private bool _isBulkDeleting;
    private bool _isStateSubscribed;
    private CancellationTokenSource? _selectionTranslationCancellation;
    private string _lastSelectedJapanese = "";
    private int _translationRequestVersion;

    public VocabularyPage(MainViewModel vm, MainWindow main)
    {
        InitializeComponent();
        _vm = vm;
        _main = main;
        Focusable = true;
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

        // Let the navigation shell paint before querying the local word database.
        await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.Render);
        if (!IsLoaded) return;
        Refresh();
        Focus();
    }

    private void Page_Unloaded(object sender, RoutedEventArgs e)
    {
        if (_isStateSubscribed)
        {
            _vm.StateChanged -= Changed;
            _isStateSubscribed = false;
        }
        _selectionTranslationCancellation?.Cancel();
        _selectionTranslationCancellation?.Dispose();
        _selectionTranslationCancellation = null;
    }

    private void Changed(object? sender, EventArgs e) => Dispatcher.Invoke(() =>
    {
        if (!_isBulkDeleting) Refresh();
    });

    private void Refresh()
    {
        var query = SearchBox.Text?.Trim() ?? "";
        var result = _vm.QueryVocabulary(query, _page * VocabularyPageSize, VocabularyPageSize);
        var pageCount = Math.Max(1, (int)Math.Ceiling(result.Total / (double)VocabularyPageSize));
        if (_page >= pageCount)
        {
            _page = pageCount - 1;
            result = _vm.QueryVocabulary(query, _page * VocabularyPageSize, VocabularyPageSize);
        }
        _visibleWords = result.Words;
        _selectedWordIds.IntersectWith(_visibleWords.Select(word => word.Id));
        WordList.ItemsSource = result.Words;
        Subtitle.Text = _vm.IsJapanese
            ? "当前重点词 · JLPT N4 假名、罗马音与例句 · 闪卡只从这里取词"
            : "当前重点词 · CET-6 音标、搭配与例句 · 闪卡只从这里取词";
        Status.Text = $"单词本共 {result.Total:N0} 词 · 收藏 {result.FavoriteCount:N0} 词 · 本页 {result.Words.Count} 词";
        PageText.Text = $"第 {_page + 1:N0} / {pageCount:N0} 页";
        PreviousPageButton.IsEnabled = _page > 0;
        NextPageButton.IsEnabled = _page + 1 < pageCount;
        WordInput.ToolTip = _vm.IsJapanese ? "输入汉字或假名，例如：連絡" : "输入英文，例如：consecutive";
        UpdateSelectionControls();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!IsLoaded) return;
        _page = 0;
        _selectedWordIds.Clear();
        Refresh();
    }

    private async void AddButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(WordInput.Text)) { Status.Text = "请先输入词语。"; return; }
        AddButton.IsEnabled = false;
        Status.Text = "DeepSeek 正在补全词条…";
        try
        {
            var word = await _vm.DeepSeek.LookupWordAsync(_vm.CurrentTrack, WordInput.Text);
            _vm.AddWord(word);
            WordInput.Clear();
            Status.Text = "词条已加入当前单词本和闪卡队列。";
        }
        catch (Exception ex)
        {
            Status.Text = ex.Message;
            if (!_vm.DeepSeek.HasKey) _main.Navigate("settings");
        }
        finally { AddButton.IsEnabled = true; }
    }

    private void PreviousPage_Click(object sender, RoutedEventArgs e)
    {
        if (_page <= 0) return;
        _page--;
        _selectedWordIds.Clear();
        Refresh();
    }

    private void NextPage_Click(object sender, RoutedEventArgs e)
    {
        _page++;
        _selectedWordIds.Clear();
        Refresh();
    }

    private void FavoriteButton_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not VocabularyWord word) return;
        var favorite = _vm.IsFavorite(word);
        button.Content = favorite ? "★" : "☆";
        button.Foreground = favorite ? System.Windows.Media.Brushes.Black : System.Windows.Media.Brushes.DimGray;
        button.ToolTip = favorite ? "已收藏，点击取消收藏" : "收藏";
    }

    private void Favorite_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not VocabularyWord word) return;
        _vm.ToggleFavorite(word);
    }

    private void WordSelectionCheckBox_Loaded(object sender, RoutedEventArgs e)
    {
        if (sender is not CheckBox checkBox || checkBox.Tag is not VocabularyWord word) return;
        _syncingSelection = true;
        checkBox.IsChecked = _selectedWordIds.Contains(word.Id);
        _syncingSelection = false;
    }

    private void WordSelectionCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (_syncingSelection || (sender as CheckBox)?.Tag is not VocabularyWord word) return;
        if ((sender as CheckBox)?.IsChecked == true) _selectedWordIds.Add(word.Id);
        else _selectedWordIds.Remove(word.Id);
        UpdateSelectionControls();
    }

    private void SelectAllCheckBox_Changed(object sender, RoutedEventArgs e)
    {
        if (_syncingSelection) return;
        var select = SelectAllCheckBox.IsChecked == true;
        foreach (var word in _visibleWords)
        {
            if (select) _selectedWordIds.Add(word.Id);
            else _selectedWordIds.Remove(word.Id);
        }
        Refresh();
    }

    private void UpdateSelectionControls()
    {
        _syncingSelection = true;
        SelectAllCheckBox.IsChecked = _visibleWords.Count > 0 && _visibleWords.All(word => _selectedWordIds.Contains(word.Id));
        _syncingSelection = false;
        DeleteSelectedButton.IsEnabled = _selectedWordIds.Count > 0;
        DeleteSelectedButton.Content = _selectedWordIds.Count == 0 ? "删除所选" : $"删除所选（{_selectedWordIds.Count}）";
    }

    private void DeleteSelected_Click(object sender, RoutedEventArgs e)
    {
        var selected = _visibleWords.Where(word => _selectedWordIds.Contains(word.Id)).ToList();
        if (selected.Count == 0) return;
        var message = $"从单词本移除选中的 {selected.Count} 个词吗？" + Environment.NewLine + Environment.NewLine +
                      "来自词书的词会保留在词书中，只是不再进入单词本和闪卡。";
        if (MessageBox.Show(Window.GetWindow(this), message, "批量删除", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;

        _isBulkDeleting = true;
        DeleteSelectedButton.IsEnabled = false;
        try
        {
            foreach (var word in selected) _vm.DeleteWord(word);
            Status.Text = $"已从单词本移除 {selected.Count} 个词。";
        }
        finally
        {
            _selectedWordIds.Clear();
            _isBulkDeleting = false;
            Refresh();
        }
    }

    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is VocabularyWord word &&
            MessageBox.Show($"从单词本删除“{word.Word}”？", "删除词条", MessageBoxButton.YesNo) == MessageBoxResult.Yes)
        {
            _selectedWordIds.Remove(word.Id);
            _vm.DeleteWord(word);
        }
    }

    private async void JapaneseText_SelectionChanged(object sender, RoutedEventArgs e)
    {
        if (!_vm.IsJapanese || sender is not TextBox textBox) return;
        var selected = textBox.SelectedText.Trim();
        if (string.IsNullOrWhiteSpace(selected) || !ContainsJapaneseText(selected) || selected == _lastSelectedJapanese) return;

        _lastSelectedJapanese = selected;
        _selectionTranslationCancellation?.Cancel();
        var cancellation = new CancellationTokenSource();
        _selectionTranslationCancellation = cancellation;
        var requestVersion = ++_translationRequestVersion;

        SelectionTranslationPanel.Visibility = Visibility.Visible;
        SelectedJapaneseText.Text = $"日文：{selected}";
        SelectedTranslationText.Text = _vm.DeepSeek.HasKey
            ? "正在通过 DeepSeek 翻译…"
            : "尚未配置 DeepSeek 密钥，请先到“设置”页面保存密钥。";
        if (!_vm.DeepSeek.HasKey) return;

        try
        {
            await Task.Delay(360, cancellation.Token);
            var translation = await _vm.DeepSeek.TranslateJapaneseSelectionAsync(selected, cancellation.Token);
            if (cancellation.IsCancellationRequested || requestVersion != _translationRequestVersion) return;
            SelectedTranslationText.Text = $"中文：{translation.Trim()}";
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            if (requestVersion == _translationRequestVersion) SelectedTranslationText.Text = ex.Message;
        }
    }

    private void CloseSelectionTranslation_Click(object sender, RoutedEventArgs e)
    {
        _translationRequestVersion++;
        _selectionTranslationCancellation?.Cancel();
        SelectionTranslationPanel.Visibility = Visibility.Collapsed;
        _lastSelectedJapanese = "";
    }

    private static bool ContainsJapaneseText(string value) => value.Any(character =>
        character is >= '\u3040' and <= '\u30ff' ||
        character is >= '\u3400' and <= '\u9fff' ||
        character is '\u3005' or '\u3006' or '\u3007');
}
