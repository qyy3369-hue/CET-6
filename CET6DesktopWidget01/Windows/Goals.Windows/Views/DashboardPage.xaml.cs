using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Goals.Windows.Models;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class DashboardPage : UserControl
{
    private readonly MainViewModel _vm;
    private readonly MainWindow _main;
    private bool _refreshing;

    public DashboardPage(MainViewModel vm, MainWindow main)
    {
        InitializeComponent();
        _vm = vm;
        _main = main;
        Loaded += (_, _) => Refresh();
        _vm.StateChanged += Vm_StateChanged;
        Unloaded += (_, _) => _vm.StateChanged -= Vm_StateChanged;
    }

    private void Vm_StateChanged(object? sender, EventArgs e) => Dispatcher.Invoke(Refresh);

    private void Refresh()
    {
        _refreshing = true;
        GoalList.ItemsSource = _vm.Tracks;
        GoalList.SelectedItem = _vm.CurrentTrack;
        PlanList.ItemsSource = _vm.CurrentTrack.Plans;
        PlanList.SelectedItem = _vm.CurrentPlan;
        GoalCount.Text = $"{_vm.Tracks.Count} 个";
        SelectedTitle.Text = _vm.CurrentTrack.Title;
        SelectedDescription.Text = $"{_vm.CurrentTrack.Category} · {_vm.CurrentTrack.Focus}";
        _refreshing = false;
    }

    private void GoalList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_refreshing && GoalList.SelectedItem is StudyTrack track) _vm.CurrentTrack = track;
    }

    private void GoalCard_Click(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border { Tag: StudyTrack track }) return;
        GoalList.SelectedItem = track;
        if (!ReferenceEquals(_vm.CurrentTrack, track)) _vm.CurrentTrack = track;
        e.Handled = true;
    }

    private void PlanList_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!_refreshing && PlanList.SelectedItem is PlanSheet plan) _vm.CurrentPlan = plan;
    }

    private void AddGoal_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(NewGoalTitle.Text)) { GoalStatus.Text = "请先输入目标名称。"; return; }
        var mode = (NewGoalMode.SelectedItem as ComboBoxItem)?.Tag?.ToString() switch
        {
            "Japanese" => LearningMode.Japanese,
            "Other" => LearningMode.Other,
            _ => LearningMode.English
        };
        _vm.AddTrack(NewGoalTitle.Text, mode, NewGoalFocus.Text);
        NewGoalTitle.Clear(); NewGoalFocus.Clear();
        GoalStatus.Text = "已创建并切换到新目标。";
    }

    private void DeleteGoal_Click(object sender, RoutedEventArgs e)
    {
        if (MessageBox.Show($"确定删除“{_vm.CurrentTrack.Title}”及其任务、词库和复习进度吗？", "删除目标", MessageBoxButton.YesNo, MessageBoxImage.Warning) != MessageBoxResult.Yes) return;
        GoalStatus.Text = _vm.DeleteCurrentTrack() ? "目标已删除。" : "至少需要保留一个目标。";
    }

    private void AddPlan_Click(object sender, RoutedEventArgs e)
    {
        _vm.AddPlan(NewPlanTitle.Text);
        NewPlanTitle.Clear();
    }

    private void OpenPlan_Click(object sender, RoutedEventArgs e) => _main.Navigate("plan");
    private void OpenToday_Click(object sender, RoutedEventArgs e) => _main.Navigate("today");
}
