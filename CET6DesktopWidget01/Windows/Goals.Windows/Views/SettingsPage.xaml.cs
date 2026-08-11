using System.Windows;
using System.Windows.Controls;
using System.IO;
using Goals.Windows.Services;
using Goals.Windows.ViewModels;
using Velopack;

namespace Goals.Windows.Views;

public partial class SettingsPage : UserControl
{
    private readonly MainViewModel _vm;
    private readonly AppUpdateService _updates = new();
    private UpdateInfo? _availableUpdate;
    private bool _syncing;
    private bool _updating;
    public SettingsPage(MainViewModel vm)
    {
        InitializeComponent(); _vm = vm;
        Loaded += (_, _) =>
        {
            RefreshBadge();
            ModelText.Text = _vm.DeepSeek.ModelName;
            DataPath.Text = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "GoalsStudyDesk", "study-data.json");
            WordLibraryPath.Text = _vm.Library.DataPath;
            CurrentVersionText.Text = $"当前 v{_updates.CurrentVersion}";
        };
    }
    private void RefreshBadge() { KeyBadge.Text = _vm.DeepSeek.HasKey ? "已安全配置" : "尚未配置"; Status.Text = _vm.DeepSeek.HasKey ? "已保存的密钥不会在此页面回显。输入新密钥可覆盖。" : "配置密钥后才能使用 AI 计划、补词、智能判分、翻译和写作。"; }
    private void KeyPassword_PasswordChanged(object sender, RoutedEventArgs e) { if (_syncing) return; _syncing = true; KeyVisible.Text = KeyPassword.Password; _syncing = false; }
    private void KeyVisible_TextChanged(object sender, TextChangedEventArgs e) { if (_syncing) return; _syncing = true; KeyPassword.Password = KeyVisible.Text; _syncing = false; }
    private void ShowKey_Changed(object sender, RoutedEventArgs e) { if (KeyPassword is null || KeyVisible is null) return; KeyVisible.Visibility = ShowKey.IsChecked == true ? Visibility.Visible : Visibility.Collapsed; KeyPassword.Visibility = ShowKey.IsChecked == true ? Visibility.Collapsed : Visibility.Visible; }
    private void Save_Click(object sender, RoutedEventArgs e)
    {
        try { _vm.DeepSeek.SaveKey(KeyPassword.Password); KeyPassword.Clear(); KeyVisible.Clear(); RefreshBadge(); Status.Text = "密钥已保存到 Windows 凭据管理器。"; }
        catch (Exception ex) { Status.Text = ex.Message; }
    }
    private async void Test_Click(object sender, RoutedEventArgs e)
    {
        TestButton.IsEnabled = false; Status.Text = "正在连接 DeepSeek…";
        try { Status.Text = await _vm.DeepSeek.TestAsync(); }
        catch (Exception ex) { Status.Text = ex.Message; }
        finally { TestButton.IsEnabled = true; }
    }
    private void Delete_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show("清除后 AI 功能将暂停，普通学习功能不受影响。确定继续吗？", "清除密钥", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        _vm.DeepSeek.DeleteKey(); KeyPassword.Clear(); KeyVisible.Clear(); RefreshBadge(); Status.Text = "已从 Windows 凭据管理器清除密钥。";
    }

    private async void Update_Click(object sender, RoutedEventArgs e)
    {
        if (_updating) return;

        try
        {
            if (_availableUpdate is null)
            {
                UpdateButton.IsEnabled = false;
                UpdateButton.Content = "正在检查…";
                UpdateStatus.Text = "正在连接 GitHub Releases…";

                var result = await _updates.CheckAsync();
                UpdateStatus.Text = result.Message;
                _availableUpdate = result.Update;

                if (_availableUpdate is null)
                {
                    UpdateButton.Content = "再次检查";
                    return;
                }
            }

            var version = _availableUpdate.TargetFullRelease.Version.ToString();
            UpdateButton.Content = $"安装 v{version}";
            if (MessageBox.Show(
                    $"发现 Goals v{version}。现在下载并安装吗？\n\n软件会在下载完成后自动重启，本地学习数据不会被删除。",
                    "软件更新",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Information) != MessageBoxResult.Yes)
            {
                UpdateStatus.Text = $"v{version} 已准备好，点击“安装 v{version}”即可继续。";
                return;
            }

            _updating = true;
            UpdateButton.IsEnabled = false;
            UpdateButton.Content = "正在下载…";
            UpdateProgress.Value = 0;
            UpdateProgress.Visibility = Visibility.Visible;
            UpdateStatus.Text = $"正在下载 v{version}，请不要关闭软件。";

            await _updates.DownloadAsync(_availableUpdate, percent =>
                Dispatcher.BeginInvoke(() =>
                {
                    UpdateProgress.Value = percent;
                    UpdateStatus.Text = $"正在下载 v{version}：{percent}%";
                }));

            UpdateProgress.Value = 100;
            UpdateStatus.Text = "下载完成，正在安装并重新启动…";
            _updates.ApplyAndRestart(_availableUpdate);
        }
        catch (Exception ex)
        {
            UpdateStatus.Text = $"更新失败：{ex.Message}";
            UpdateButton.Content = _availableUpdate is null ? "再次检查" : "重试安装";
        }
        finally
        {
            _updating = false;
            UpdateButton.IsEnabled = true;
        }
    }
}
