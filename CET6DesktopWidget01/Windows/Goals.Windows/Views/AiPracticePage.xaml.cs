using System.Windows;
using System.Windows.Controls;
using Goals.Windows.ViewModels;

namespace Goals.Windows.Views;

public partial class AiPracticePage : UserControl
{
    private readonly MainViewModel _vm; private readonly bool _writing; private readonly MainWindow _main;
    public AiPracticePage(MainViewModel vm, bool writing, MainWindow main)
    {
        InitializeComponent(); _vm = vm; _writing = writing; _main = main;
        TitleText.Text = writing ? "写作训练" : "翻译训练";
        Subtitle.Text = writing ? "150–200 词范文与结构注释" : "中译英、英文润色与易错提示";
        Prompt.Tag = writing ? "输入主题、提示句或六级写作原题" : "输入一句中文或英文，AI 会翻译或润色";
        Status.Text = "结果只保存在当前页面；请勿输入敏感信息。";
    }
    private async void Generate_Click(object sender, RoutedEventArgs e)
    {
        if (string.IsNullOrWhiteSpace(Prompt.Text)) { Status.Text = "请先输入训练内容。"; return; }
        GenerateButton.IsEnabled = false; Status.Text = "DeepSeek 正在生成…";
        try { Output.Text = _writing ? await _vm.DeepSeek.WriteEssayAsync(Prompt.Text) : await _vm.DeepSeek.TranslateAsync(Prompt.Text); Status.Text = "生成完成。"; }
        catch (Exception ex) { Status.Text = ex.Message; if (!_vm.DeepSeek.HasKey) _main.Navigate("settings"); }
        finally { GenerateButton.IsEnabled = true; }
    }
}
