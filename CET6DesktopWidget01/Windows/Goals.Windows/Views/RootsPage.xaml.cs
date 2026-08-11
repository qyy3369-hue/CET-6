using System.Windows.Controls;

namespace Goals.Windows.Views;

public partial class RootsPage : UserControl
{
    private sealed record RootRow(string Root, string Meaning, string Examples, string Cue);
    private readonly List<RootRow> _rows =
    [
        new("spect / spic", "看", "inspect 检查 · perspective 视角 · conspicuous 显眼的", "遇到 spect 先联想看见、观察和视角。"),
        new("duc / duct", "引导；带来", "conduct 执行 · reduce 减少 · introduce 介绍", "duce/duct 常和带、引、导向某结果有关。"),
        new("form", "形状；形成", "transform 转变 · uniform 统一的 · reform 改革", "form 相关词优先抓形态和形成。"),
        new("ject", "投掷；抛出", "project 项目 · reject 拒绝 · objective 客观的", "把东西抛出去：投射、拒出、目标物。"),
        new("port", "携带；运输", "transport 运输 · import 进口 · portable 便携的", "port 常指带着走或跨区域移动。"),
        new("scrib / script", "写", "describe 描述 · manuscript 手稿 · prescription 处方", "script 看到就联想文字、记录与书写。"),
        new("bene", "好；善", "benefit 好处 · beneficial 有益的 · benevolent 仁慈的", "bene 对应 good，常表示正面作用。"),
        new("contra / counter", "反对；相反", "contrast 对比 · contradict 反驳 · counteract 抵消", "前缀表示对着来或朝相反方向。")
    ];
    public RootsPage() { InitializeComponent(); Loaded += (_, _) => RootList.ItemsSource = _rows; }
    private void Search_TextChanged(object sender, TextChangedEventArgs e) { var q = Search.Text.Trim(); RootList.ItemsSource = _rows.Where(x => string.IsNullOrWhiteSpace(q) || $"{x.Root} {x.Meaning} {x.Examples}".Contains(q, StringComparison.OrdinalIgnoreCase)); }
}
