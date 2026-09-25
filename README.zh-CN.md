# ClickToDo Chrome Redirect

[English](README.md)

[正式发布](https://github.com/Noemion/ClickToDo-Chrome-Redirect/releases) · [当前源码版本](VERSION) · [更新日志](CHANGELOG.md)

让 Windows 11「单击以执行」的「搜索互联网」使用 **Chrome 及其默认搜索引擎**，解决卸载 Edge 后跳转微软商店的问题。

## 使用方法

**普通用户只需从 [Releases 发布页](https://github.com/Noemion/ClickToDo-Chrome-Redirect/releases) 下载 `ClickToDo-Chrome-Redirect.bat`，其他仓库文件不用下载。** 每版附 SHA-256 校验值，并对应一个 Git 标签。[主分支 BAT](https://github.com/Noemion/ClickToDo-Chrome-Redirect/raw/refs/heads/main/ClickToDo-Chrome-Redirect.bat) 可能包含尚未发布的修改。

1. 右键 BAT → **以管理员身份运行** → 选择 **1** 安装。
2. 关闭窗口，普通双击 BAT → 选择 **3** 测试。
3. 在 Click to Do 中使用「搜索互联网」，确认结果。

升级也选 **1**；卸载选 **2**。安装无需下载额外依赖，也不会重新安装 Edge。

启动时显示脚本版本；选 **4** 可另外查看已安装程序的版本，`/version` 可单独打印版本。旧程序没有版本信息时显示 `unknown (legacy build)`，选择 1 升级后即可显示。

| 选项 | 功能 | 运行权限 |
| --- | --- | --- |
| 1 | 安装 / 升级 | 管理员 |
| 2 | 卸载转发 | 管理员 |
| 3 | 测试默认搜索 | 普通运行 |
| 4 | 查看状态 | 普通运行 |
| 5 | 回滚到升级前的程序 | 管理员 |
| 6 | 退出 | 任意 |

## 适用条件

- **x64 Windows 11**，Chrome 安装在系统级 `Program Files` 目录中。
- Edge 已卸载，但仍保留 `%ProgramFiles(x86)%\Microsoft\Edge\Application\pwahelper.exe`，且 Click to Do 实际调用它。
- Windows PowerShell 5.1 和系统自带的 .NET Framework C# 编译器可用。

转发和默认搜索功能已在 **Windows 11 25H2（26200.9457）/ Click to Do 1000.26100.9457.0** 上验证。其他版本未经实机验证，ARM64 暂不支持。

**注意：** 本工具也会接管该路径下 `pwahelper.exe` 的其他启动用途；影响其他功能时请卸载。搜索引擎取决于 Chrome 使用的个人资料；普通网页链接仍按原网址打开。Windows 更新可能改变兼容性。

## 目录说明

| 文件 / 目录 | 用途 |
| --- | --- |
| `ClickToDo-Chrome-Redirect.bat` | **完整工具，普通用户只需这个文件** |
| `src/` | 转发程序和安装逻辑的源码 |
| `scripts/` | 将源码生成完整 BAT 的工具和模板 |
| `tests/` | 参数处理、生成一致性和恢复逻辑测试 |
| `.github/workflows/` | GitHub 上运行的自动检查和版本发布 |
| `docs/` | 原理、排错和开发说明 |
| `README.md` / `README.zh-CN.md` | 英文 / 中文使用说明 |
| `CHANGELOG.md` / `LICENSE` | 版本记录 / MIT 许可证 |
| `VERSION` | 构建版本号的统一来源 |
| `.gitignore` / `.gitattributes` | Git 忽略规则 / 文件换行规则 |

BAT 已包含源码，运行时不依赖其他仓库文件。安装后的程序和恢复记录在 `%ProgramFiles%\ClickToDoPwaRedirect\`；**请先用菜单卸载，再删除安装目录**。建议保留下载的 BAT，方便以后管理。

## 更多说明

- [原理、常见问题与开发说明](docs/DEVELOPMENT.md)
- [版本记录](CHANGELOG.md) · [反馈问题](https://github.com/Noemion/ClickToDo-Chrome-Redirect/issues) · [MIT 许可证](LICENSE)

社区项目，与 Microsoft、Google 或 OpenAI 无关联。
