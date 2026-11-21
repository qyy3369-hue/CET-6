# Goals 网页版

网页版是纯静态 HTML、CSS 和 JavaScript，用浏览器运行，由 Sites 托管。登录、同步、好友和 AI 请求由 Supabase 处理。[线上 Goals](https://goals-study-desk.exquisitearia2.chatgpt.site/)

## 改哪里

以下路径都相对于本目录 `CET6DesktopWidget01/Web/`。

| 路径 | 用途 |
| --- | --- |
| `dist/` | **网页版源码，也是直接上传的站点文件。** 页面入口是 `index.html`，主逻辑在 `app.js`，通用样式在 `style.css`。直接修改这里即可，无需另找 `src/` 或运行打包命令。 |
| `dist/ocr/` | 浏览器图片识词所需的 Tesseract 运行库、英文识别模型和许可证。导词流程改 `dist/vocabulary-import.js` 或 `dist/vocabulary-ocr.js`。 |
| `.openai/` | Sites 配置。`hosting.json` 绑定现有站点，并指定 `dist/` 为静态站点目录。发布时保留该配置。 |
| `supabase/` | 数据库 SQL。依文件编号记录学习同步、好友与排行、注册、工作区、单词顺序和助记缓存的变更。 |
| `supabase/functions/` | Supabase Edge Functions。`goals-enroll/` 处理注册，`goals-deepseek/` 处理 DeepSeek 设置和调用。它们有独立的部署流程。 |

网页功能入口：

| 要改的功能 | 优先看 |
| --- | --- |
| 侧栏、路由、快速搜索、单词本、闪卡、好友和设置 | `dist/app.js` |
| 布局、颜色、按钮视觉、悬停动效 | `dist/style.css`、`dist/button-motion.js` |
| 目标与日程、计划书、翻译、写作、词根词缀 | `dist/workspace.js` |
| 闪卡助记的展示、校验、缓存和预取 | `dist/flashcard-mnemonic.js`；生成请求在 `supabase/functions/goals-deepseek/` |
| 图片导词、选择识别结果、批量入库 | `dist/vocabulary-import.js`、`dist/vocabulary-ocr.js` |
| 云端连接、示例单词 | `dist/GoalsCloud.json` 仅含浏览器可用的 Supabase 地址和可发布密钥；`dist/starter-words.json` 是示例词库。 |

Mac 源码在上一级的 `Sources/CET6DesktopWidget/`，可以对照现有 UI 和交互。Windows 原生版在上一级的 `Windows/`。网页版预览和打包只依赖本目录中的静态资源与托管配置。

## 本地预览

从 Git 仓库根目录运行：

```bash
python3 -m http.server 8000 --bind 127.0.0.1 --directory CET6DesktopWidget01/Web/dist
```

然后打开 [本地预览](http://127.0.0.1:8000/)。Windows 上也可以把命令开头的 `python3` 换成 `py -3`。页面使用 ES 模块，请通过 HTTP 打开。

本地预览默认读取 `GoalsCloud.json` 中的线上 Supabase 配置。登录、修改学习记录或触发 AI 时，使用测试账号或独立测试项目。

## GitHub 与上线

1. 在 GitHub 仓库的 `CET6DesktopWidget01/Web/` 做改动，验证后提交。没有原仓库写权限时可以 fork 后开 PR。
2. GitHub 的 push 更新源码。要更新现有网址，在已连接 Sites 且对该站点有编辑权限的会话里打开现有站点源码仓库。站点 ID 在 `.openai/hosting.json`。
3. 把 GitHub 中需要发布的 `Web/dist/` 内容及相关源码变更同步到 Sites checkout 的对应路径，先核对两边的差异，保留 Sites 上其他人的改动。使用 Sites 技能的 `site-workflow.mjs` 推送和打包，静态资源取自 checkout 根目录下的 `dist/`。这个站点无需安装依赖或构建，打包时可以传 `commands: []`。
4. 调用 Sites 的保存版本和部署工具，用返回的版本 ID 发布到现有站点。沿用现有网址和访问权限。只改前端时无需部署 Supabase；SQL 或 Edge Function 的变更在所属 Supabase 项目中独立部署。

站点编辑权限和 GitHub 仓库权限各自管理。GitHub 仓库是公开的，提交时只带源码和可公开的配置。个人学习记录、`.env`、真实邀请码、DeepSeek API Key 和 Supabase 服务端密钥留在各自的本地或后端环境。
