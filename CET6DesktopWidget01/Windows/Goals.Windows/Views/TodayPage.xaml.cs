using System.Windows;
using System.Windows.Controls;
using Goals.Windows.Models;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class TodayPage : UserControl
{
    private readonly MainViewModel _vm;
    public TodayPage(MainViewModel vm)
    {
        InitializeComponent(); _vm = vm; Loaded += (_, _) => Refresh(); _vm.StateChanged += Changed; Unloaded += (_, _) => _vm.StateChanged -= Changed;
    }
    private void Changed(object? s, EventArgs e) => Dispatcher.Invoke(Refresh);
    private void Refresh() { TaskList.ItemsSource = _vm.TodayTasks; Subtitle.Text = $"{_vm.CurrentTrack.Title} · {_vm.CompletedToday}/{_vm.TotalToday} 已完成"; }
    private void Add_Click(object sender, RoutedEventArgs e) { _vm.AddTask(NewTask.Text, NewTime.Text); NewTask.Clear(); }
    private void Toggle_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is StudyTask task) _vm.ToggleTask(task); }
    private void Delete_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is StudyTask task) _vm.DeleteTask(task); }
}
