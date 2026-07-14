# CET6DesktopWidget01

多目标 Mac 桌面计划小组件。原来的 CET-6 词汇、翻译、写作训练继续保留，计划系统已经扩展为可管理生活里的多个目标、多个模式和多张计划表。

已完成：

- 桌面悬浮小组件空壳
- 小组件位于普通窗口下方，不会一直挡住其他页面
- 点击小组件空白区域打开主学习窗口
- 本地 JSON 数据保存
- 今日任务展示
- 输入任意任务并立即显示、保存
- 主学习窗口：左侧分类区，右侧具体内容区
- 目标总览：同时管理多个生活目标
- 每个目标可拥有多张计划表，并可切换查看
- 计划书输入后自动生成日程卡片并同步到对应目标
- 单词本、词根词缀、闪卡复习、错词收藏页面

运行：

```bash
swift run
```

生成 Mac 应用：

```bash
./Scripts/build_app.sh
open Build/CET6DesktopWidget.app
```

数据文件：

```text
Data/study_tasks.json
Data/goal_plans01.json
Data/custom_words01.json
Data/word_import_state01.json
```

每日抽词：

App 启动后会在每天 07:30 自动检查 `Data/word_import_state01.json`。如果当天还没有导入，就从上级目录的 `词汇.txt` 抽取 20 个未导入过的单词，调用 `.env` 中的 DeepSeek API 补全音标、词性、例句、释义、短语和助记，再写入 `Data/custom_words01.json` 供单词本和闪卡复习使用。

下一步建议：

- 为每个目标增加颜色或图标
- 增加周视图和月视图
- 增加记忆曲线和复习提醒
