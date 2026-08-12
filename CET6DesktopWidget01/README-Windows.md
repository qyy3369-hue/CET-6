# Goals Windows 版

这是原 macOS SwiftUI 应用的 Windows 10/11 x64 原生移植版。界面采用接近 Codex 桌面端的中性色层级、左侧导航、微圆角控件和 Windows 原生标题栏。

## 安装与自动更新

正式分享给朋友时，让对方第一次运行 GitHub Releases 中的 `GoalsLifeDesk-win-Setup.exe`。安装版可以在“设置 → 软件更新”中检查新版本、显示下载进度，并在下载完成后自动安装和重启。

当前 `Windows/Release/Goals-win-x64` 是开发用便携版，可以直接运行，但便携版不具备原地自动更新能力。

更新文件默认托管于：

```text
https://github.com/qyy3369-hue/CET-6/releases
```

该仓库或后续单独建立的更新仓库必须允许朋友公开下载 Releases。不要把私人 GitHub Token 写进应用程序。

## 直接运行便携版

打开以下目录并双击 `Goals.exe`：

```text
Windows/Release/Goals-win-x64/
```

该目录是自包含便携版，不要求电脑预装 .NET。整个 `Goals-win-x64` 文件夹可以复制给其他 Windows 10/11 64 位用户。

## 学习模式

- CET-6：目标总览、计划书、今日日程、单词本、翻译训练、写作训练、词根词缀、闪卡复习、错词收藏。
- 日语 N4：目标总览、计划书、今日日程、单词本、闪卡复习、错词收藏。
- 两种语言的词库、计划、任务、收藏和复习进度相互独立。
- 可继续新建英语或日语目标，每个目标支持多张计划表。

英语闪卡正面显示单词和 IPA 音标；日语闪卡正面显示词语、假名和罗马音，提交后再显示词性、中文释义、例句和例句翻译。两种卡片共用 0–5 级间隔复习、收藏、斩词和跳过。

## DeepSeek 密钥安全

项目和发布目录不包含任何 DeepSeek 密钥，也不读取 `.env`。

在左侧进入“设置”，输入自己的密钥并保存。密钥存储于 Windows 凭据管理器的当前用户安全区，不会写入学习数据文件。设置页支持显示本次输入、保存、测试连接和清除密钥。

没有配置密钥时，目标、计划、日程、词库浏览、闪卡和错词等本地功能仍可正常使用；AI 制定计划、AI 补词、智能判分、翻译与写作会提示先设置密钥。

## 本地数据

首次启动会生成不含个人信息的 CET-6 与 JLPT N4 测试数据。运行数据位置：

```text
%LOCALAPPDATA%\GoalsStudyDesk\study-data.json
```

发布文件夹本身不保存用户的运行数据，因此升级或重新复制软件不会覆盖个人学习记录。

## 从源码构建

安装 .NET 10 SDK 后，在 PowerShell 中执行：

```powershell
.\Scripts\build_windows.ps1
```

构建脚本会运行自检并生成自包含的 `Windows/Release/Goals-win-x64`。

## 发布新版本

仓库包含 `.github/workflows/release-windows.yml`。发布稳定版本时执行：

```powershell
git tag v1.1.0
git push origin v1.1.0
```

GitHub Actions 会自动完成：

1. 还原依赖并运行回归测试。
2. 发布 Windows x64 自包含程序。
3. 生成安装器、完整更新包和增量更新包。
4. 创建 `Goals v1.1.0` GitHub Release 并上传全部更新文件。

每次版本号必须递增，例如 `1.0.0 → 1.0.1 → 1.1.0`。已经安装过 `GoalsLifeDesk-win-Setup.exe` 的用户随后可以直接在软件内完成更新。
