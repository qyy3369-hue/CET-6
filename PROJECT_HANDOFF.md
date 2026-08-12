# Goals 学习计划中心：Agent 交接文档

最后更新：2026-08-12  
当前 Windows 正式版本：`v1.1.0`  
仓库：<https://github.com/qyy3369-hue/CET-6>（已公开）  
最新版 Release：<https://github.com/qyy3369-hue/CET-6/releases/tag/v1.1.0>

## 1. 项目定位

这是一个最初在 macOS 上开发的学习计划和 CET-6 复习应用。当前工作重点是 Windows WPF 版本，并在保留原版学习流程的基础上加入日语 JLPT N4 模式。

Windows 项目目录：

```text
CET6DesktopWidget01/Windows/
├─ Goals.Windows/             # WPF 主程序
├─ Goals.Windows.SmokeTests/  # 无 UI 回归/冒烟测试
├─ QA/                        # 本地 QA 资料，当前未纳入 Git
└─ Release/                   # 本地发布产物，已被 .gitignore 排除
```

主要技术栈：

- C# / .NET 10 / WPF
- SQLite（`Microsoft.Data.Sqlite`）存储大词书
- `MDict.Csharp` 解析 MDX/MDD
- Velopack 安装、检测更新和增量更新
- DeepSeek API 用于计划生成、补词、评分及日文划词翻译
- `Microsoft.ML.OnnxRuntime` 本地跑日→中翻译模型（离线）
- 本地翻译模型为 OPUS-MT ja→zh（Marian）导出的 int8 ONNX，约 236MB，见第 2.7–2.8 节

## 2. 已经完成的主要功能

### 2.1 Windows 迁移与界面

- 已完成可正常运行的 Windows WPF 客户端。
- UI 已改为接近 Codex 的简洁风格：轻微圆角、浅色背景、克制的边框，不再模仿 macOS 红绿灯。
- 已删除桌面小窗及相关功能。
- 已删除所有发音按钮和语音服务；英语闪卡显示音标，日语显示假名和罗马音。
- 输入框、按钮悬停、尖锐边角、部分乱码区块、任务完成样式等做过多轮修复。
- 所有页面启用统一平滑滚动，代码在 `Infrastructure/SmoothScrollBehavior.cs`。当前参数偏灵敏、低阻尼，修改时需要全局一致。

### 2.2 学习目标

已有三类学习目标：

- 英语 / CET-6
- 日语 / JLPT N4
- 其他（自定义目标）

目标总览中的大目标卡片本身可以直接点击切换目标，不应再额外增加一个重复选择器。

日语目标保留：

- 目标总览
- 计划书
- 今日日程
- 词书
- 单词本
- 闪卡复习
- 错词收藏
- 设置

日语目标不显示：翻译训练、写作训练、词根词缀。

“其他”类型只保留通用的目标、计划和日程能力，不显示语言专属模块。

### 2.3 计划和今日日程

- 支持手动创建目标、计划表和每日任务。
- DeepSeek 可生成计划及拆解日程。
- 今日任务完成后，时间和任务文字显示删除线与弱化状态。
- 已按用户要求移除额外的“已完成”徽章方块，只保留清晰的完成视觉和撤销按钮。

### 2.4 词书与导入

左侧独立“词书”模块用于管理完整词典，导入功能都集中在这里。

支持：

- JSON
- MDX
- MDD（作为 MDX 的资源伴随文件自动匹配）
- CSS（作为词典样式伴随文件自动匹配）

大词书不会整体写入 `study-data.json`，而是存入 SQLite 并分页查询，避免几十万词拖垮启动。

当前重要逻辑：

- 每天默认从词书抽取 20 个尚未进入单词本的词。
- 用户可把每日数量设为 `0–200`；当天调高会立即补足差额，重启不会重复抽取。
- 词书右侧只有一个星星：点亮即加入单词本，熄灭即移出单词本。
- 移出单词本不会删除词书原始词条，也不会抹掉历史复习记录。
- 可删除整本词书；删除时才移除该词书及其关联的学习词条。
- 大文件分批写入并记录断点，暂停后选择同一文件可继续导入。
- 导入逻辑修复过 MDX 内部链接、日语释义解析、异常弹窗连锁触发和错误词头展示。
- 词书条目展示层级已尽量与单词本一致：词头、读音/罗马音、词性、释义、例句、翻译、标签。

导入测试样本位于：

```text
CET6DesktopWidget01/Windows/Goals.Windows.SmokeTests/Fixtures/
```

用户曾用以下大词典实际测试，但这些文件不在仓库中：

```text
D:\BaiduNetdiskDownload\smk8.mdx
D:\BaiduNetdiskDownload\smk8.css
```

### 2.5 单词本

单词本是用户当前重点背诵集合，不是完整词典。

- 闪卡只从单词本取词。
- 单词本支持搜索、12 词一页的分页。
- 支持勾选、多选、“全选本页”和批量删除。
- 收藏按钮必须只有一个星星：收藏为黑色实心 `★`，未收藏为白色/灰色空心 `☆`。
- 删除导入词时只是从单词本移除，词条仍留在词书中。
- 支持通过 DeepSeek 补全并添加单个词条。

### 2.6 日文划词翻译

词书和单词本都支持：鼠标选中日文释义或例句后，自动翻译成中文。**默认走本地模型（离线）**，本地翻不出时才回退 DeepSeek。

实现位置：

- `Services/DeepSeekService.cs`
- `Services/LocalTranslationService.cs`（本地离线模型）
- `Views/WordbooksPage.xaml(.cs)`
- `Views/VocabularyPage.xaml(.cs)`

行为约束：

- 只在日语目标中触发。
- 只有选中文本含日文字符时才触发。
- 约 360ms 防抖，连续选择会取消上一次请求。
- 没有本地模型也没有 API 密钥时在页面内提示，不弹出连续错误窗口。
- 翻译结果显示在页面内可关闭的面板中。

### 2.7 本地离线翻译（OPUS-MT ja→zh）

为满足「免费、离线、断网可用」的日→中释义翻译，程序捆绑了一个专用 NMT 模型，通过 OnnxRuntime 本地推理：

- 模型：`shun89/opus-mt-ja-zh`（Marian），Apache-2.0，导出为 ONNX 后做 int8 动态量化，共约 236MB。
- 文件位于 `Windows/Goals.Windows/Models/opus-mt-ja-zh/`（`encoder_model.onnx`、`decoder_model.onnx`、`decoder_with_past_model.onnx`、`source_vocab.json`、`target_vocab.json`）。该目录已被 `.gitignore` 排除，不随源码提交。
- 运行时解析顺序：程序目录 `Models/` → `%LOCALAPPDATA%\GoalsStudyDesk\Models\`。没有模型时翻译提示缺失，不崩溃。
- 结果缓存于内存和 `%LOCALAPPDATA%\GoalsStudyDesk\translation-cache.db`，相同释义第二次点击即时返回。

核心实现：

- `Services/LocalTranslationService.cs`：对外服务（懒加载、串行推理、缓存、质检），并含 `LooksLikeJapanese`（需含假名才算日文，避免把中文当日语）。
- `Services/OnnxSeq2SeqTranslator.cs`：ONNX encoder + 贪心 decoder（带 KV 缓存），I/O 名从运行时元数据动态解析。
- `Services/UnigramTokenizer.cs`：SentencePiece Unigram 分词器（Viterbi 编码、`▁`→空格解码），词表由 Python 从模型的 `spiece.model` 导出成 JSON，保证与参考分词一致。
- 推理前清洗输入：剥离 `①-⑩` 义项编号；以「こと。」结尾时先剥掉名词化结尾。
- 两道质检防线，翻坏的结果直接判定失败（回退 DeepSeek 或提示「本地模型无法翻译此释义」），绝不把错误译文端给用户：
  1. 输出仍含假名（模型复述了日文没翻译）。
  2. 输出退化循环（如「油油油…」）。

翻译流程（闪卡答题后 / 词书与单词本每行释义旁）：

1. 点「译为中文」→ 本地模型翻译，结果标注「（本地模型）」。
2. 不满意 → 按钮变「用 DeepSeek 重译」→ 点击调 DeepSeek（需配置密钥），结果标注「（DeepSeek）」。
3. 本地翻不出的词 → 直接提示「本地模型无法翻译此释义」，按钮即「用 DeepSeek 重译」。

`MainViewModel` 提供三个方法：`TranslateJapaneseLocalAsync`（仅本地）、`TranslateJapaneseWithDeepSeekAsync`（仅 DeepSeek）、`TranslateJapaneseAsync`（本地优先、失败回退 DeepSeek，用于划词翻译）。

### 2.8 翻译模型选型结论（重要，避免重复试错）

已实测三种候选，结论是**没有小型免费离线模型能可靠翻译日语词典释义**：

- Qwen2.5 0.5B / 1.5B（LLM，GGUF + LLamaSharp）：对碎片化释义要么复述日文、要么翻反语义，已弃用。
- NLLB-200-distilled-600M：更差，连基础句子都错、还幻觉网页文案，已弃用。
- **OPUS-MT ja→zh（当前采用）**：对常见整句类释义翻译良好（实测 5/6 以上可用），但生僻词/碎片名词短语（如「かす」=残渣）会翻错。当前方案对这类词安全失败并引导 DeepSeek 重译。

另：理想的日汉专用模型 `staka/fugumt-ja-zh` 在 Hugging Face 被作者设成需要登录（401），无法下载；`zh-ja` 同理。若日后可访问，值得换回它。

### 2.9 闪卡复习

需要保持接近最初 Mac 版的流程：

1. 显示词，用户输入释义并按回车或提交。
2. 无论答对或答错，都先显示完整词条详情。
3. 答对：再次回车进入下一张。
4. 答错：进入纠错阶段，必须重新输入一次正确核心释义；确认后才能进入下一张。
5. 错词自动进入错词收藏，并立即到期等待再复习。
6. 正确答案按记忆曲线安排下次复习。

当前记忆间隔位于 `Services/FlashcardScheduler.cs`：

```text
等级 1：30 分钟
等级 2：12 小时
等级 3：3 天
等级 4：7 天
等级 5：15 天
```

闪卡已删除发音功能，并支持音标/假名、收藏、斩词、跳过、上一张以及键盘回车流程。

闪卡详情区的「译为中文」按钮只出现在**答题后**（输入答案展开详情时），绝不出现在出题面——闪卡相当于考试，不能把答案提前放在卷子上。点按钮走第 2.7 节的「本地优先、DeepSeek 重译」流程。

## 3. 性能优化现状

用户的 MDX 词书可达几十万词，曾导致点击“词书 / 单词本 / 闪卡”后等待很久。

已经完成：

- `MainWindow` 缓存词书、单词本、闪卡三个高频页面，重复切换不重新构建整个 UI。
- 三个页面在 `Loaded/Unloaded` 时重新订阅/取消状态事件，避免缓存页面失去更新响应。
- 词书查询放到后台任务中，先渲染页面和“正在加载”状态，再返回分页数据。
- 闪卡队列和统计查询放到后台任务中，并用请求版本号丢弃过期结果。
- 单词本先让页面渲染，再查询当前 12 个词；其数据量来自重点词集合，通常远小于完整词书。
- SQLite 词书始终分页，`WordLibraryStore.PageSize = 80`；闪卡每批最多 200。

继续优化时建议优先做：

- 给后台查询加显式异常捕获和页面内错误提示，避免 `async void` 或 fire-and-forget 异常难以追踪。
- 检查 `MainViewModel` 在后台线程调用时的线程安全，最好把纯数据库查询接口与 UI 状态变更进一步分离。
- 对搜索框增加 200–350ms 防抖，避免每输入一个字就执行 `COUNT + SELECT`。
- 若大词书第一页仍慢，可为 `words(track_id, headword)`、`imports(track_id)`、`active_words(word_id)` 等实际查询路径复核索引和 SQLite 查询计划。
- 可加入轻量骨架屏或首屏 12–20 条渐进展示，但不要一次把整本词典载入内存。

## 4. 数据与隐私

不要把用户个人数据、词库数据库或 API 密钥提交到仓库或 Release。

运行数据存放在：

```text
%LOCALAPPDATA%\GoalsStudyDesk\study-data.json
%LOCALAPPDATA%\GoalsStudyDesk\word-library.db
%LOCALAPPDATA%\GoalsStudyDesk\translation-cache.db   # 本地翻译结果缓存
```

本地翻译模型（`Models/opus-mt-ja-zh/`，约 236MB）位于程序目录，已被 `.gitignore` 排除；`%LOCALAPPDATA%\GoalsStudyDesk\Models\` 是用户手动后放的兜底位置。

DeepSeek 密钥：

- 不在源码、JSON 数据或发布目录中。
- 使用 Windows Credential Manager 保存。
- 设置页面可保存、测试和清除密钥。
- `Services/WindowsCredentialStore.cs` 负责读写。

发布包不包含上述运行数据。便携版与安装版在同一 Windows 用户下会读取同一 `%LOCALAPPDATA%` 数据目录。

如果 `study-data.json` 损坏，程序会把它改名备份为带时间戳的 `.broken-*` 文件，然后生成测试数据；不要在未询问用户的情况下主动删除这些文件。

## 5. 构建与测试

当前机器曾使用临时 .NET SDK：

```text
C:\Users\33924\AppData\Local\Temp\goals-windows-build-sdk\dotnet.exe
```

2026-08-12 发布 `v1.1.0` 时复核：`%LOCALAPPDATA%\Microsoft\dotnet\dotnet.exe` 已不存在；当前可用 SDK 是上面的临时 .NET 10.0.400。机器原装的 `C:\Program Files\dotnet\dotnet.exe` 只有运行时、没有 SDK。普通安装了 .NET 10 SDK 的环境可直接使用 `dotnet`。

本地翻译模型的下载/再生成脚本：

```powershell
powershell -ExecutionPolicy Bypass -File CET6DesktopWidget01\Scripts\fetch_translation_model.ps1
```

脚本会检查 `Models/opus-mt-ja-zh/` 是否齐备；缺失时调用同仓库的 `Scripts/export_translation_model.py`，从固定模型提交导出 ONNX、执行 int8 动态量化并生成词表 JSON。它不再依赖 `D:\CET-6\_nmt_work` 中的私有转换脚本。

首次准备模型导出环境：

```powershell
python -m pip install -r CET6DesktopWidget01\Scripts\translation_model_requirements.txt
powershell -ExecutionPolicy Bypass -File CET6DesktopWidget01\Scripts\fetch_translation_model.ps1
```

GitHub Actions 会自动完成上述 Python 依赖安装和模型生成；模型二进制不进入 Git，只随便携版、安装包和 Velopack 更新包分发。

在安装了 .NET 10 SDK 的普通环境中可直接使用 `dotnet`。

构建：

```powershell
dotnet build CET6DesktopWidget01\Windows\Goals.Windows\Goals.Windows.csproj -c Release
```

回归测试：

```powershell
dotnet run --project CET6DesktopWidget01\Windows\Goals.Windows.SmokeTests\Goals.Windows.SmokeTests.csproj -c Release
```

自包含便携版：

```powershell
dotnet publish CET6DesktopWidget01\Windows\Goals.Windows\Goals.Windows.csproj `
  -c Release -r win-x64 --self-contained true `
  -p:PublishSingleFile=true `
  -p:IncludeNativeLibrariesForSelfExtract=true `
  -p:Version=1.1.0 `
  -o CET6DesktopWidget01\Windows\Release\Goals-win-x64
```

（`Goals.Windows.csproj` 当前 `Version=1.1.0`；发版时按需同步。`Models/opus-mt-ja-zh/` 经 csproj 的 `Content Include="Models\opus-mt-ja-zh\**"` 拷入发布目录，ONNX + onnxruntime 原生库都会随包分发。）

### 5.1 日常迭代：重新编译并打开

每次改动代码/界面后，按此流程让改动真实生效（用户非常在意这一点，且禁止运行时热重载）：

```powershell
# 1) 关闭正在运行的 Goals（带窗口的实例）
#    任务管理器结束，或用 PowerShell：
Get-Process Goals | Where-Object MainWindowHandle -ne 0 | Stop-Process -Force

# 2) 重新编译 + 冒烟测试 + 发布自包含便携版（一条命令完成）
.\CET6DesktopWidget01\Scripts\build_windows.ps1

# 3) 打开便携版验证
& 'CET6DesktopWidget01\Windows\Release\Goals-win-x64\Goals.exe'
```

要点与踩坑：

- 必须**先关掉运行中的实例再发布**：Windows 会锁住正在运行的 exe，且运行中的旧实例内存里还是旧代码，不重启看不到新改动。
- 只关 `Path` 精确等于便携版路径的 Goals 进程；历史上出现过无窗口的残留 Goals 进程（提权、无法被杀），它不影响重新启动新实例，可忽略。
- `build_windows.ps1` 内部顺序：跑 SmokeTests 回归 → `dotnet publish` 到 `Windows/Release/Goals-win-x64`。
- 本机 `dotnet` 需要用户级 SDK（见上文）；命令里用 `%LOCALAPPDATA%\Microsoft\dotnet\dotnet.exe` 或把该目录加进 `PATH`。
- 若只改了 C#/XAML 而不涉及模型，不必重跑 `fetch_translation_model.ps1`；模型已随发布目录打包。

本机便携版常用位置：

```text
D:\CET-6\CET-6\CET-6\CET6DesktopWidget01\Windows\Release\Goals-win-x64\Goals.exe
```

桌面快捷方式：

```text
C:\Users\33924\OneDrive\Desktop\Goals 学习计划中心.lnk
```

发布前若需要关闭程序，只能关闭 `Path` 精确等于上述便携版路径的 `Goals` 进程，不要误杀其他同名进程。

## 6. GitHub Release 与自动更新

自动发布工作流：

```text
.github/workflows/release-windows.yml
```

工作流会在推送 `vX.Y.Z` 标签时：

1. 安装 .NET 10。
2. 安装 Python 3.12 和 `Scripts/translation_model_requirements.txt` 中固定的模型导出依赖。
3. 运行 `Scripts/fetch_translation_model.ps1`，由 `Scripts/export_translation_model.py` 从固定 Hugging Face 提交导出 OPUS-MT ja→zh ONNX，并动态量化为 int8。
4. 恢复 .NET 依赖并运行回归测试。
5. 发布包含 5 个本地模型必需文件的 win-x64 自包含应用。
6. 安装 Velopack CLI 1.2.0，并下载上一版更新元数据。
7. 生成 Setup、full nupkg、delta nupkg、便携包、`RELEASES` 和 `releases.win.json`。
8. 创建公开 GitHub Release 并上传全部更新资产。

应用检查更新地址写在：

```text
Services/AppUpdateService.cs
https://github.com/qyy3369-hue/CET-6
```

注意：

- 只有通过 `GoalsLifeDesk-win-Setup.exe` 安装的版本可以使用 Velopack 应用内更新。
- 直接复制到桌面的便携版不能原地自动更新，会提示先安装安装版。
- 仓库必须公开，否则同学的客户端在没有 GitHub 私有令牌时无法读取 Release。
- 每次发版必须递增版本号并推送新标签；只在本地生成 Setup 不等于已经发布。
- **重要：`Models/`（含 ONNX 模型）已被 `.gitignore` 排除**。不要提交模型二进制。工作流已在全新 checkout 中自动导出并量化模型；修改模型脚本或依赖后，必须重新验证干净导出能生成 `encoder_model.onnx`、`decoder_model.onnx`、`decoder_with_past_model.onnx`、`source_vocab.json`、`target_vocab.json`。

经过 `v1.1.0` 实际验证的推荐发布流程：

```powershell
# 1. 先运行回归测试和 Release 构建
dotnet run --project CET6DesktopWidget01\Windows\Goals.Windows.SmokeTests\Goals.Windows.SmokeTests.csproj -c Release
dotnet build CET6DesktopWidget01\Windows\Goals.Windows\Goals.Windows.csproj -c Release

# 2. 从 main 建独立发布分支，只显式暂存 Windows/发布文件
git switch -c agent/release-windows-X.Y.Z
git add <明确属于本次 Windows 修改和发布工作流的文件>
git diff --cached --check
git commit -m "Release Windows Goals X.Y.Z"
git push -u origin agent/release-windows-X.Y.Z

# 3. 创建 PR，核对 changed files 后合并到 main；再同步 main
git switch main
git fetch origin main --tags
git merge --ff-only origin/main

# 4. 标签必须指向合并后的 main，且不能复用旧标签
git tag -a vX.Y.Z origin/main -m "Goals Windows X.Y.Z"
git push origin vX.Y.Z
```

随后必须等待 GitHub Actions 成功，并验证 Release 不是 draft/prerelease，且存在以下 6 类资产：

```text
GoalsLifeDesk-X.Y.Z-full.nupkg
GoalsLifeDesk-X.Y.Z-delta.nupkg
GoalsLifeDesk-win-Setup.exe
GoalsLifeDesk-win-Portable.zip
RELEASES
releases.win.json
```

最后实际下载 `releases.win.json` 并确认：HTTP 200、版本为 `X.Y.Z`、同时存在 Full/Delta、文件大小大于 0、SHA256 不为空。只看到 GitHub Actions 绿色还不够；完成资产和元数据检查才算发布成功。

## 7. 当前 Git 状态与安全警告

Windows v1.1.0 已通过 PR #1 合并到 `main` 并发布：

```text
4e7d847 Release Windows Goals 1.1.0
PR:      https://github.com/qyy3369-hue/CET-6/pull/1
Actions: https://github.com/qyy3369-hue/CET-6/actions/runs/31607580390
Release: https://github.com/qyy3369-hue/CET-6/releases/tag/v1.1.0
```

`v1.1.0` 发布验证结果：

- GitHub Actions 的模型导出、回归测试、应用发布、Velopack 打包、Release 上传和工作流 Artifact 全部成功。
- 本地与 CI 均完成 58 项回归测试；本地 Release 构建为 0 警告、0 错误。
- 干净环境导出的 5 个 int8 ONNX/词表必需文件合计约 238MB，与本地发布模型规模一致。
- `releases.win.json` 可公开下载（HTTP 200），版本为 `1.1.0`，同时包含 Full 和 Delta，大小均大于 0 且 SHA256 完整。

`v1.1.0` Release 主要资产（十进制 MB）：

```text
GoalsLifeDesk-1.1.0-full.nupkg    218.6 MB
GoalsLifeDesk-1.1.0-delta.nupkg   162.3 MB
GoalsLifeDesk-win-Portable.zip     218.6 MB
GoalsLifeDesk-win-Setup.exe        223.1 MB
releases.win.json                  512 B
RELEASES                           84 B
```

从 `v1.0.9` 通过设置页更新时通常下载约 162.3MB 的 delta 包；全新安装使用约 223.1MB 的 Setup。两者都包含本地 OPUS-MT 模型，不需要用户另行下载模型。

当前工作区仍有属于用户的未提交 Mac 修改、若干数据文件删除记录和其他未跟踪文件。它们不是 Windows v1.1.0 发布的一部分。

2026-08-12 的 Windows 改动（本地 OPUS-MT ONNX 翻译、词书/单词本/闪卡交互、设置页模型状态、模型导出脚本和 CI 发布流程）已经包含在 `v1.1.0`。模型二进制仍在 gitignore 内，由 GitHub Actions 发布时可复现生成并打包。

接手 Agent 必须遵守：

- 不要运行 `git reset --hard`。
- 不要运行 `git checkout -- .`。
- 不要默认执行 `git add -A`。
- 不要恢复、删除、提交或改写现有 Mac 端改动，除非用户明确要求。
- 发布 Windows 更新时只暂存明确的 Windows 文件和必要工作流文件。
- `CET6DesktopWidget01/Windows/Release/`、`bin/`、`obj/` 已被 `.gitignore` 排除。
- 不要提交 `%LOCALAPPDATA%\GoalsStudyDesk` 中的任何内容。

建议开始工作前运行：

```powershell
git status --short
git diff -- CET6DesktopWidget01/Windows
```

## 8. 关键源码导航

```text
Goals.Windows/
├─ App.xaml                         # 全局颜色、按钮、输入框、卡片等样式
├─ Program.cs                       # Velopack 启动钩子
├─ Models/AppState.cs               # 目标、计划、任务、单词、进度模型
├─ ViewModels/MainViewModel.cs      # 主业务协调层
├─ Services/AppDataStore.cs         # 小型 JSON 状态
├─ Services/WordLibraryStore.cs     # SQLite 大词书、收藏、进度、每日抽词
├─ Services/VocabularyImportService.cs # JSON/MDX/MDD/CSS 导入
├─ Services/DeepSeekService.cs      # AI 请求与日文划词翻译
├─ Services/LocalTranslationService.cs # 本地 ONNX 翻译（懒加载、缓存、质检、LooksLikeJapanese）
├─ Services/OnnxSeq2SeqTranslator.cs # OPUS-MT ONNX 贪心解码
├─ Services/UnigramTokenizer.cs     # SentencePiece Unigram 分词（JSON 词表）
├─ Services/FlashcardScheduler.cs   # 记忆曲线
├─ Services/AppUpdateService.cs     # GitHub Release / Velopack 更新
├─ Infrastructure/SmoothScrollBehavior.cs # 全局滚动体验
└─ Views/
   ├─ MainWindow.*                  # 导航、页面缓存、目标模式可见性
   ├─ DashboardPage.*               # 目标总览及目标卡片切换
   ├─ PlanPage.*                    # 计划书
   ├─ TodayPage.*                   # 今日日程
   ├─ WordbooksPage.*               # 词书、导入、每日抽词、每行释义翻译按钮
   ├─ VocabularyPage.*              # 单词本、分页、多选删除、每行释义翻译按钮
   ├─ FlashcardsPage.*              # 闪卡答题与纠错状态机（答题后翻译按钮）
   ├─ MistakesPage.*                # 错词与收藏管理
   └─ SettingsPage.*                # DeepSeek 密钥、更新、本地翻译模型状态卡片
```

## 9. 用户非常在意的产品细节

- 界面必须一眼能看懂各区域用途，不能只有空输入框没有标签或说明。
- 目标切换优先通过目标总览里的大卡片直接点击。
- 不要重新加入发音按钮或桌面小窗。
- 不要用 macOS 红绿灯；保持 Codex 式微圆角和克制配色。
- 收藏只能显示一个星星；状态用实心/空心和颜色区分。
- 完成任务使用删除线等视觉，不要额外放“已完成”徽章。
- 列表滚动手感必须全局一致。
- 大词库功能必须分页/后台加载，不能在 UI 线程遍历几十万词。
- 错误应显示为一个可理解的页面内状态，严禁重复弹出几十个错误窗口。
- 闪卡回车流程是核心功能，每次改动后必须手工测试答对、答错、纠错和进入下一张。
- 闪卡「译为中文」按钮只能出现在答题后，不能放在出题面。
- 本地翻译宁可提示「无法翻译」，也不把质检未通过的（含假名/循环重复）译文端给用户；不满意可点「用 DeepSeek 重译」。
- 词书/单词本释义旁有翻译按钮；两页词条字体较大（词头 22、释义 15 等），单词本选中行整行高亮，词书星形带「加入/已加入」文字。
- 发布给同学的版本不得包含开发者个人数据或 DeepSeek 密钥。

## 10. 建议下一步

1. 在安装版 `v1.0.9` 上实际执行一次设置页更新到 `v1.1.0`，确认下载、应用更新和重启完整闭环。
2. 配置 DeepSeek 密钥后实测「用 DeepSeek 重译」路径，确认生僻词能正确翻译。
3. 若日后能访问 `staka/fugumt-ja-zh`（当前被作者设成需登录），考虑换回该专用日汉模型，其碎片化释义质量应显著优于 OPUS-MT。
4. 建立一套 WPF UI 自动化测试，特别覆盖闪卡回车状态机、目标卡片切换和批量删除。
5. 给词书与闪卡的后台加载补充异常提示、取消令牌和耗时日志。
6. 统一整理仍可能受系统编码影响的中文资源，逐步迁移到资源字典，避免控制台/源码工具显示乱码。
7. 后续版本从 `v1.1.1` 开始递增，并始终验证 GitHub Release 中存在完整 Velopack 资产和正确的 `releases.win.json`。
