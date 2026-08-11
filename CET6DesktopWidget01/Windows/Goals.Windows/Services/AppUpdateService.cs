using System.Reflection;
using Velopack;
using Velopack.Exceptions;
using Velopack.Sources;

namespace Goals.Windows.Services;

public sealed record AppUpdateCheckResult(
    bool CanUpdate,
    UpdateInfo? Update,
    string Message);

public sealed class AppUpdateService
{
    public const string RepositoryUrl = "https://github.com/qyy3369-hue/CET-6";
    public const string SourceOverrideEnvironmentVariable = "GOALS_UPDATE_SOURCE";

    private readonly UpdateManager _manager;

    public AppUpdateService()
    {
        var overrideSource = Environment.GetEnvironmentVariable(SourceOverrideEnvironmentVariable);
        _manager = string.IsNullOrWhiteSpace(overrideSource)
            ? new UpdateManager(new GithubSource(RepositoryUrl, accessToken: null, prerelease: false))
            : new UpdateManager(overrideSource);
    }

    public string CurrentVersion
    {
        get
        {
            var version = Assembly.GetExecutingAssembly().GetName().Version;
            return version is null ? "未知" : $"{version.Major}.{version.Minor}.{version.Build}";
        }
    }

    public async Task<AppUpdateCheckResult> CheckAsync()
    {
        try
        {
            var update = await _manager.CheckForUpdatesAsync();
            return update is null
                ? new AppUpdateCheckResult(true, null, $"当前 v{CurrentVersion} 已是最新版。")
                : new AppUpdateCheckResult(
                    true,
                    update,
                    $"发现新版本 v{update.TargetFullRelease.Version}，可以下载并安装。");
        }
        catch (NotInstalledException)
        {
            return new AppUpdateCheckResult(
                false,
                null,
                "当前运行的是便携/开发版本。请先安装一次 GoalsLifeDesk-win-Setup.exe，之后即可在软件内更新。");
        }
        catch (Exception ex)
        {
            return new AppUpdateCheckResult(false, null, $"检查更新失败：{FriendlyMessage(ex)}");
        }
    }

    public async Task DownloadAsync(UpdateInfo update, Action<int> progress)
    {
        await _manager.DownloadUpdatesAsync(update, progress);
    }

    public void ApplyAndRestart(UpdateInfo update)
    {
        _manager.ApplyUpdatesAndRestart(update);
    }

    private static string FriendlyMessage(Exception ex)
    {
        if (ex.Message.Contains("404", StringComparison.OrdinalIgnoreCase))
            return "没有找到公开的更新仓库。请确认 GitHub 仓库或 Releases 已公开。";
        if (ex.Message.Contains("rate limit", StringComparison.OrdinalIgnoreCase))
            return "GitHub 请求过于频繁，请稍后重试。";
        return ex.Message;
    }
}
