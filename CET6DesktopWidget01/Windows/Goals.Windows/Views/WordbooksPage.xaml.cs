using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Media3D;
using System.Windows.Threading;
using Goals.Windows.Models;
using Goals.Windows.Services;
using Goals.Windows.ViewModels;
using Microsoft.Win32;

namespace Goals.Windows.Views;

public partial class WordbooksPage : UserControl
{
    private readonly MainViewModel _vm;
    private readonly VocabularyImportService _importer = new();
    private CancellationTokenSource? _importCancellation;
    private CancellationTokenSource? _selectionTranslationCancellation;
    private string _trackId = "";
    private string? _sourceId;
    private int _page;
    private bool _syncingBooks;
    private string? _statusMessage;
    private string _lastSelectedJapanese = "";
    private int _translationRequestVersion;
    private bool _isStateSubscribed;
    private int _refreshRequestVersion;
    private readonly Dictionary<string, bool> _rowTranslateUsedDeepSeek = [];
    private readonly DispatcherTimer _searchDebounce = new() { Interval = TimeSpan.FromMilliseconds(300) };

    public WordbooksPage(MainViewModel vm)
    {
        InitializeComponent();
        _vm = vm;
        _searchDebounce.Tick += (_, _) =>
        {
            _searchDebounce.Stop();
            _page = 0;
            Refresh();
        };
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
        DailyCountBox.Text = _vm.DailyNewWordCount.ToString();
        StatusText.Text = "正在加载词书…";
        await Dispatcher.InvokeAsync(() => { }, System.Windows.Threading.DispatcherPriority.Render);
        if (IsLoaded) Refresh();
    }

    private void Page_Unloaded(object sender, RoutedEventArgs e)
    {
        _searchDebounce.Stop();
        if (_isStateSubscribed)
        {
            _vm.StateChanged -= Changed;
            _isStateSubscribed = false;
        }
            _importCancellation?.Cancel();
            _selectionTranslationCancellation?.Cancel();
            _selectionTranslationCancellation?.Dispose();
            _selectionTranslationCancellation = null;
    }

    private void Changed(object? sender, EventArgs e) => Dispatcher.Invoke(() =>
    {
        if (_trackId != _vm.CurrentTrack.Id)
        {
            _trackId = _vm.CurrentTrack.Id;
            _sourceId = null;
            _page = 0;
            _statusMessage = null;
            DailyCountBox.Text = _vm.DailyNewWordCount.ToString();
        }
        Refresh();
    });

    private void Refresh() => _ = RefreshAsync();

    private async Task RefreshAsync()
    {
        var requestVersion = ++_refreshRequestVersion;
        _rowTranslateUsedDeepSeek.Clear();
        var trackId = _trackId;
        var sourceId = _sourceId;
        var query = SearchBox.Text?.Trim() ?? "";
        var page = _page;
        var isJapanese = _vm.CurrentTrack.Mode == LearningMode.Japanese;
        if (_importCancellation is null) StatusText.Text = "正在读取词书…";
        RefreshingBar.Visibility = Visibility.Visible;

        var snapshot = await Task.Run(() =>
        {
            var books = _vm.Library.QueryWordbooks(trackId);
            var result = _vm.Library.QueryWordbookEntries(trackId, sourceId, query, page * WordLibraryStore.PageSize, WordLibraryStore.PageSize, isJapanese);
            var pageCount = Math.Max(1, (int)Math.Ceiling(result.Total / (double)WordLibraryStore.PageSize));
            if (page >= pageCount)
            {
                page = pageCount - 1;
                result = _vm.Library.QueryWordbookEntries(trackId, sourceId, query, page * WordLibraryStore.PageSize, WordLibraryStore.PageSize, isJapanese);
            }
            return (books, result, page, pageCount);
        });
        if (!IsLoaded || requestVersion != _refreshRequestVersion || trackId != _trackId) return;
        RefreshingBar.Visibility = Visibility.Collapsed;

        var books = snapshot.books;
        _page = snapshot.page;
        _syncingBooks = true;
        BookList.ItemsSource = books;
        BookList.SelectedItem = string.IsNullOrWhiteSpace(_sourceId) ? null : books.FirstOrDefault(x => x.Id == _sourceId);
        _syncingBooks = false;
        BookCountText.Text = books.Count == 0 ? "尚未导入词书" : $"{books.Count} 本 · 共 {books.Sum(x => x.WordCount):N0} 词";
        DeleteBookButton.IsEnabled = BookList.SelectedItem is WordbookInfo;

        var result = snapshot.result;
        var pageCount = snapshot.pageCount;
        EntryList.ItemsSource = result.Entries;
        var selected = books.FirstOrDefault(x => x.Id == _sourceId);
        EntryTitle.Text = selected is null ? "全部词书中的词" : selected.Name;
        PageText.Text = $"{result.Total:N0} 词 · 第 {_page + 1:N0}/{pageCount:N0} 页";
        PreviousPageButton.IsEnabled = _page > 0;
        NextPageButton.IsEnabled = _page + 1 < pageCount;
        if (_importCancellation is null)
            StatusText.Text = _statusMessage ?? (books.Count == 0
                ? "先导入一本词书；完成后每天会自动把设定数量的新词加入单词本。"
                : $"每日自动加入 {_vm.DailyNewWordCount} 词 · 当前词书已选 {books.Sum(x => x.ActiveCount):N0} 词进入单词本");
    }

    private void BookList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_syncingBooks || !IsLoaded) return;
        _sourceId = (BookList.SelectedItem as WordbookInfo)?.Id;
        _page = 0;
        Refresh();
    }

    private void BookCard_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        for (var element = e.OriginalSource as DependencyObject; element is not null && !ReferenceEquals(element, sender); element = GetInteractionParent(element))
            if (element is Button) return;
        if ((sender as FrameworkElement)?.Tag is not WordbookInfo book) return;
        BookList.SelectedItem = book;
    }

    private static DependencyObject? GetInteractionParent(DependencyObject element)
    {
        if (element is ContentElement content)
            return ContentOperations.GetParent(content) ?? (content as FrameworkContentElement)?.Parent;
        if (element is Visual or Visual3D)
            return VisualTreeHelper.GetParent(element);
        return LogicalTreeHelper.GetParent(element);
    }

    private void ShowAllBooks_Click(object sender, RoutedEventArgs e)
    {
        _sourceId = null;
        _page = 0;
        Refresh();
    }

    private void SearchBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (!IsLoaded) return;
        _searchDebounce.Stop();
        _searchDebounce.Start();
    }

    private void PreviousPage_Click(object sender, RoutedEventArgs e) { if (_page > 0) { _page--; Refresh(); } }
    private void NextPage_Click(object sender, RoutedEventArgs e) { _page++; Refresh(); }

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
        var canTranslate = _vm.LocalTranslation.ModelFound || _vm.LocalTranslation.IsLoaded || _vm.DeepSeek.HasKey;
        SelectedTranslationText.Text = canTranslate
            ? "正在翻译…"
            : "暂无可用翻译：需要本地模型或 DeepSeek 密钥。";
        if (!canTranslate) return;

        try
        {
            await Task.Delay(360, cancellation.Token);
            var result = await _vm.TranslateJapaneseAsync(selected, cancellation.Token);
            if (cancellation.IsCancellationRequested || requestVersion != _translationRequestVersion) return;
            SelectedTranslationText.Text = result is null
                ? "暂时无法翻译，请检查本地模型或 DeepSeek 密钥。"
                : $"中文：{result.Text}（{result.Engine}）";
        }
        catch (OperationCanceledException) { }
        catch (Exception ex)
        {
            if (ex is ObjectDisposedException || requestVersion != _translationRequestVersion) return;
            SelectedTranslationText.Text = ex.Message;
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

    private void StudyStar_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as Button)?.Tag is not WordbookEntry entry) return;
        _statusMessage = entry.IsActive ? $"“{entry.Word.Word}”已从单词本移除；历史复习记录仍保留。" : $"“{entry.Word.Word}”已加入单词本和闪卡队列。";
        _vm.ToggleStudyList(entry.Word);
    }

    private async void TranslateRow_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button button || button.Tag is not VocabularyWord word) return;
        var root = FindRowRoot(button);
        var rowText = root?.FindName("RowTranslation") as TextBlock;
        var useDeepSeek = _rowTranslateUsedDeepSeek.TryGetValue(word.Id, out var used) && used;
        button.IsEnabled = false;
        button.Content = "翻译中…";
        if (rowText is not null)
        {
            rowText.Visibility = Visibility.Visible;
            rowText.Text = "正在翻译…";
        }
        try
        {
            var result = useDeepSeek
                ? await _vm.TranslateJapaneseWithDeepSeekAsync(word.Meaning)
                : await _vm.TranslateJapaneseLocalAsync(word.Meaning);
            _rowTranslateUsedDeepSeek[word.Id] = true;
            if (rowText is not null)
                rowText.Text = result is null
                    ? (useDeepSeek ? "DeepSeek 未能翻译（未配置密钥或失败）。" : "本地模型无法翻译此释义。")
                    : $"中文：{result.Text}（{result.Engine}）";
            button.Content = useDeepSeek ? "重译" : "用 DeepSeek 重译";
        }
        catch (Exception ex)
        {
            if (rowText is not null) rowText.Text = "翻译失败：" + ex.Message;
        }
        finally
        {
            button.IsEnabled = true;
        }
    }

    private static FrameworkElement? FindRowRoot(object source)
    {
        var current = source as DependencyObject;
        while (current is not null)
        {
            if (current is FrameworkElement { Name: "RowBorder" } element) return element;
            current = VisualTreeHelper.GetParent(current);
        }
        return null;
    }

    private void SaveDailyCount_Click(object sender, RoutedEventArgs e)
    {
        if (!int.TryParse(DailyCountBox.Text.Trim(), out var count) || count is < 0 or > 200)
        {
            _statusMessage = "每日数量请输入 0–200 之间的整数。设置为 0 可关闭自动抽词。";
            StatusText.Text = _statusMessage;
            return;
        }
        var result = _vm.SetDailyNewWordCount(count);
        DailyCountBox.Text = result.Goal.ToString();
        _statusMessage = result.AddedNow > 0
            ? $"已保存：每天自动加入 {result.Goal} 词；今天立即补入 {result.AddedNow} 词。"
            : $"已保存：每天自动加入 {result.Goal} 词；今天不需要再补词。";
        Refresh();
    }

    private async void Import_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "选择要导入的本地词书",
            Filter = "支持的词书 (*.json;*.mdx;*.mdd;*.css)|*.json;*.mdx;*.mdd;*.css|JSON 词书 (*.json)|*.json|MDict 词典与资源 (*.mdx;*.mdd;*.css)|*.mdx;*.mdd;*.css",
            CheckFileExists = true,
            Multiselect = false
        };
        var owner = Window.GetWindow(this);
        if (dialog.ShowDialog(owner) != true) return;
        var target = _vm.CurrentTrack;
        var confirmation = $"把“{Path.GetFileName(dialog.FileName)}”导入到“{target.Title}”的词书库吗？\n\n" +
                           "导入后不会一次性塞进单词本：程序只会按每日设置自动选词，也可以手动点亮五角星。\n" +
                           "文件会按 1,000 条一批保存，可随时暂停并从断点继续；原文件不会被修改。";
        if (MessageBox.Show(owner, confirmation, "导入词书", MessageBoxButton.YesNo, MessageBoxImage.Question) != MessageBoxResult.Yes) return;

        ImportButton.IsEnabled = false;
        CancelImportButton.Visibility = Visibility.Visible;
        ImportProgressBar.Visibility = Visibility.Visible;
        ImportProgressBar.IsIndeterminate = true;
        _importCancellation = new CancellationTokenSource();
        ImportFileText.Text = $"正在读取：{Path.GetFileName(dialog.FileName)}";
        try
        {
            var progress = new Progress<WordImportProgress>(value =>
            {
                StatusText.Text = value.Message;
                ImportProgressBar.IsIndeterminate = value.Total <= 0;
                if (value.Total > 0)
                {
                    ImportProgressBar.Maximum = value.Total;
                    ImportProgressBar.Value = Math.Min(value.Processed, value.Total);
                }
                ImportFileText.Text = value.Total > 0
                    ? $"{Path.GetFileName(dialog.FileName)} · {value.Processed:N0}/{value.Total:N0} · 已保存 {value.Added:N0}"
                    : $"{Path.GetFileName(dialog.FileName)} · 已处理 {value.Processed:N0} · 已保存 {value.Added:N0}";
            });
            var result = await _importer.ImportToLibraryAsync(dialog.FileName, target, _vm.Library, null, progress, _importCancellation.Token);
            var daily = _vm.EnsureDailyWords();
            _sourceId = _vm.GetWordbooks().FirstOrDefault(x => x.Name == result.SourceName)?.Id;
            _page = 0;
            ImportFileText.Text = result.AlreadyComplete
                ? $"已导入过：{result.SourceName}"
                : $"完成：{result.SourceName} · 新增 {result.Added:N0} · 重复 {result.Duplicates:N0}";
            _statusMessage = result.AlreadyComplete
                ? "这本词书已经完整导入，无需重复处理。"
                : $"词书导入完成，共处理 {result.Processed:N0} 条；今天自动加入单词本 {daily.AddedNow:N0} 词。";
            Refresh();
        }
        catch (OperationCanceledException)
        {
            ImportFileText.Text = $"已暂停：{Path.GetFileName(dialog.FileName)}";
            _statusMessage = "已完成批次均已保存；再次选择同一文件会从断点继续。";
            StatusText.Text = _statusMessage;
        }
        catch (Exception ex)
        {
            ImportFileText.Text = $"导入失败：{Path.GetFileName(dialog.FileName)}";
            _statusMessage = ex.Message;
            StatusText.Text = _statusMessage;
            MessageBox.Show(owner, ex.Message, "无法导入词书", MessageBoxButton.OK, MessageBoxImage.Warning);
        }
        finally
        {
            _importCancellation?.Dispose();
            _importCancellation = null;
            CancelImportButton.Visibility = Visibility.Collapsed;
            ImportProgressBar.Visibility = Visibility.Collapsed;
            ImportButton.IsEnabled = true;
        }
    }

    private void CancelImport_Click(object sender, RoutedEventArgs e)
    {
        StatusText.Text = "正在保存当前批次并暂停…";
        _importCancellation?.Cancel();
    }

    private async void DeleteBookCard_Click(object sender, RoutedEventArgs e)
    {
        if ((sender as FrameworkElement)?.Tag is WordbookInfo book)
            await DeleteBookAsync(book);
    }

    private async void DeleteBook_Click(object sender, RoutedEventArgs e)
    {
        if (BookList.SelectedItem is not WordbookInfo book) return;
        await DeleteBookAsync(book);
    }

    private async Task DeleteBookAsync(WordbookInfo book)
    {
        var message = $"删除词书“{book.Name}”吗？\n\n将删除其中 {book.WordCount:N0} 个词，并把其中已选的 {book.ActiveCount:N0} 个词从单词本和闪卡中移除。此操作不会删除原始文件。";
        if (MessageBox.Show(Window.GetWindow(this), message, "删除词书", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        DeleteBookButton.IsEnabled = false;
        BookList.IsEnabled = false;
        StatusText.Text = $"正在删除“{book.Name}”及其单词本、闪卡关联…";
        try
        {
            await Task.Run(() => _vm.DeleteWordbook(book));
            _sourceId = null;
            _page = 0;
            _statusMessage = $"已从应用中删除词书“{book.Name}”；原始文件仍在原位置。";
            Refresh();
        }
        catch (Exception ex)
        {
            _statusMessage = $"删除失败：{ex.Message}";
            StatusText.Text = _statusMessage;
        }
        finally
        {
            BookList.IsEnabled = true;
        }
    }
}
