# Goals 网页版工作说明

先读 [README.md](README.md) 的目录表和发布流程。相对路径以本 `Web/` 目录为准。

- **前端从 `dist/index.html` 进入。** `dist/` 是直接维护的浏览器源码和静态部署目录。修改页面、交互和样式时从 `dist/app.js`、`dist/style.css` 进入，按 README 找对应功能模块。
- **Sites 打包用 `.openai/hosting.json` 和 `dist/`。** 预览用 HTTP 静态服务器，项目没有构建或包安装步骤。保留现有站点 ID、网址及访问权限。GitHub push 与 Sites 上线是两个步骤。
- **后端在 `supabase/`。** 编号 SQL 管数据库，`functions/` 管 Supabase Edge Functions。已上线的数据库结构需要变更时，写新的迁移。只改网页时，通常无需改动后端或桌面端。
- **保持 Goals 的现有布局和动效。** 沿用 `dist/style.css` 和 `dist/button-motion.js` 的样式及悬停交互。需要对照 Mac 时查看 `../Sources/CET6DesktopWidget/`。
- **验证改到的流程。** 静态预览后检查相关路由和交互。需要登录或写数据的验证使用测试账号或独立测试项目。仓库公开，提交限定在本次改动需要的路径，个人数据和服务端密钥留在本地或后端环境。
