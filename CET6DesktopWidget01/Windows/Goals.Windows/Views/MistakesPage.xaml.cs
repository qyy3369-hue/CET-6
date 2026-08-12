using System.Windows;
using System.Windows.Controls;
using Goals.Windows.Models;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class MistakesPage : UserControl
{
    private readonly MainViewModel _vm; private string _mode = "favorites"; private string _track = "";
    private int _refreshRequestVersion;
    public MistakesPage(MainViewModel vm) { InitializeComponent(); _vm = vm; Loaded += (_, _) => { _track = _vm.CurrentTrack.Id; Refresh(); }; _vm.StateChanged += Changed; Unloaded += (_, _) => _vm.StateChanged -= Changed; }
    private void Changed(object? s, EventArgs e) => Dispatcher.Invoke(() => { if (_track != _vm.CurrentTrack.Id) _track = _vm.CurrentTrack.Id; Refresh(); });
    private void Refresh() => _ = RefreshAsync();
    private async Task RefreshAsync()
    {
        var requestVersion = ++_refreshRequestVersion;
        var q = Search.Text?.Trim() ?? "";
        var banished = _mode == "banished";
        IReadOnlyList<VocabularyWord> words;
        try { words = await Task.Run(() => _vm.GetSpecialWords(banished, q)); }
        catch { return; }
        if (!IsLoaded || requestVersion != _refreshRequestVersion) return;
        List.ItemsSource = words; Status.Text = banished ? $"{words.Count} 个已斩词 · 点击恢复后重新进入闪卡队列" : $"{words.Count} 个收藏错词 · 再次点击可取消收藏";
    }
    private void Mode_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is string mode) { _mode = mode; Refresh(); } }
    private void Search_TextChanged(object sender, TextChangedEventArgs e) { if (IsLoaded) Refresh(); }
    private void Action_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is not VocabularyWord word) return; if (_mode == "banished") _vm.SetBanished(word, false); else _vm.ToggleFavorite(word); Refresh(); }
}
