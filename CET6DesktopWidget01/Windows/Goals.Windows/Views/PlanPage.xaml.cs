using System.Windows;
using System.Windows.Controls;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class PlanPage : UserControl
{
    private readonly MainViewModel _vm;
    private readonly MainWindow _main;
    public PlanPage(MainViewModel vm, MainWindow main)
    {
        InitializeComponent(); _vm = vm; _main = main;
        Loaded += (_, _) => { PlanTitle.Text = _vm.CurrentPlan.Title; PlanContent.Text = _vm.CurrentPlan.Content; };
    }

    private void Save_Click(object sender, RoutedEventArgs e)
    {
        _vm.SavePlan(PlanTitle.Text, PlanContent.Text); SaveStatus.Text = "已保存并同步。";
    }

    private async void AiButton_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(AiBackground.Text)) { AiStatus.Text = "请先描述你的时间、期限或薄弱项。"; return; }
        AiButton.IsEnabled = false; AiStatus.Text = "DeepSeek 正在生成 7 天计划…";
        try
        {
            var result = await _vm.DeepSeek.GeneratePlanAsync(_vm.CurrentTrack, AiBackground.Text);
            _vm.ApplyAiPlan(result); PlanContent.Text = result.Summary; AiStatus.Text = $"已生成并同步 {result.Tasks.Count} 项日程。";
        }
        catch (Exception ex) { AiStatus.Text = ex.Message; }
        finally { AiButton.IsEnabled = true; }
    }

    private void Today_Click(object sender, RoutedEventArgs e) => _main.Navigate("today");
}
