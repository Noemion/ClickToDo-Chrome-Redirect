# 原理、排错与开发说明

[返回中文使用说明](../README.zh-CN.md) · [English](../README.md)

## 工作原理

```text
Click to Do → microsoft-edge: → pwahelper.exe 启动请求
  → IFEO 完整路径过滤 → 本地转发程序 → Chrome
```

Windows 的 IFEO（Image File Execution Options）配置让特定路径的 `pwahelper.exe` 启动请求交给转发程序。它不修改 HTTP/HTTPS 默认关联，不替换微软程序文件，也不修改 Chrome 设置。

对于 `bing.com` 及其子域名下的 `/search?q=...`，程序解码 `q`，再用 Chrome 的 `? 关键词` 参数请求默认搜索。普通网页和 Bing 图片搜索等其他地址仍按 URL 打开。多个人资料用户需注意：没有固定 `--profile-directory`，由 Chrome 自行选择。

该过滤器不能区分调用来源；所有针对同一路径帮助程序的启动都受影响。没有 HTTP/HTTPS 地址时会提示不支持，不会继续启动原帮助程序。

参考：[Microsoft IFEO 介绍](https://techcommunity.microsoft.com/blog/askperf/two-minute-drill-configuring-a-debugger-using-image-file-execution-options/373478)、[Chromium 搜索参数实现](https://github.com/chromium/chromium/blob/main/chrome/browser/ui/startup/startup_tab_provider.cc)。

## 配置与恢复

安装目录：`%ProgramFiles%\ClickToDoPwaRedirect\`。注册表更改范围：

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe
  UseFilter = 1
  ClickToDoChromeRedirect\
    FilterFullPath = [目标 pwahelper.exe 完整路径]
    Debugger = "[安装目录]\PwaRedirect.exe"
```

- 安装前保存原有 `UseFilter` 状态至 `state.json`；原注册表项存在时另外导出备份。
- 升级保留上一版 EXE，菜单 5 只回滚程序，菜单 2 才卸载转发。
- 卸载移除本工具过滤器，恢复未被外部更改的原配置；遇到其他软件新增的设置会保留。
- 卸载后保留停用的程序、源码、备份与日志，确认成功后可手动清理。
- 早期拆分版脚本可直接用菜单 1 升级，原有恢复记录继续保留。请勿同时运行多个安装窗口。

## 常见问题

| 现象 | 检查方式 |
| --- | --- |
| 默认浏览器是 Chrome，却打开商店 | HTTP/HTTPS 和 `microsoft-edge:` 是不同关联；目标环境中后者启动 Edge 帮助程序 |
| 仍使用 Bing | 菜单 4 日志若为 `chrome-default-search-requested`，检查 Chrome 当前个人资料的默认搜索引擎；若为 `chrome-url-launch-requested`，说明不是支持的 Bing 网页搜索格式 |
| 缺少 `pwahelper.exe` | 当前卸载状态不适用，本工具不会为此重新安装 Edge |
| 没有关联或仍打开商店 | 检查菜单 4、是否残留旧的当前用户协议覆盖，以及系统是否实际启动目标路径；旧覆盖应由原脚本撤销 |
| 测试要求普通权限 | 关闭管理员窗口后普通运行 BAT，避免使用不合预期的 Chrome 个人资料 |
| 安装因已有配置而停止 | 脚本保护未知 IFEO 调试器、过滤器及当前用户协议覆盖，不会直接覆盖它们 |
| 卸载、升级或恢复失败 | 保留 `state.json`、注册表备份和错误信息；不要盲目删除整个 `pwahelper.exe` 注册表项 |

仅安装在 `LocalAppData` 的 Chrome 暂不支持。旧 `UserChoice` 注册表值可能与实际关联不一致，不应仅凭它判断默认浏览器失效。

## 日志

`%LOCALAPPDATA%\ClickToDoPwaRedirect\status.log` 仅记录时间和调用状态，不保存 URL、搜索词或个人资料。超过约 256 KiB 后重新开始。没有遥测、常驻服务或自动更新；浏览器搜索仍会正常向所用搜索引擎发送关键词。

## 源码文件

| 文件 | 职责 |
| --- | --- |
| [`src/PwaRedirect.cs`](../src/PwaRedirect.cs) | 提取 URL、转换搜索、引用参数、启动 Chrome；包含程序自测 |
| [`src/Setup.ps1`](../src/Setup.ps1) | 环境检查、编译、安装、升级、卸载、回滚和诊断 |
| [`scripts/Launcher.bat.in`](../scripts/Launcher.bat.in) | BAT 菜单和启动模板；`.in` 是生成输入，不是安装器 |
| [`scripts/Build.ps1`](../scripts/Build.ps1) | 把源码嵌入模板，生成根目录的完整 BAT |
| [`tests/Test.ps1`](../tests/Test.ps1) | 检查生成一致性、PowerShell 语法，并运行程序和恢复测试 |
| [`tests/TestRegistry.ps1`](../tests/TestRegistry.ps1) | 在临时 HKCU 测试项中检查恢复和冲突保护，不修改真实 IFEO |

## 构建与验证

### 建议的源码阅读顺序

1. `scripts/Launcher.bat.in`：菜单如何映射到动作，BAT 如何读取自身内嵌的 PowerShell，以及退出码如何传回调用方。
2. `src/Setup.ps1`：先看动作分发，再看检查、编译和恢复函数。`state.json` 保存的是**首次安装前**的状态，升级不能覆盖成已启用转发的状态。
3. `src/PwaRedirect.cs`：按 `Main → Extract → BrowserInput → Quote → Process.Start` 理解一次转发。网址提取、搜索转换和 Windows 参数引用各自处理不同的问题。
4. `tests/TestRegistry.ps1`：五种恢复场景说明哪些设置可以删除、哪些必须保留，以及半途失败的安装如何恢复。
5. `scripts/Build.ps1` 和 `tests/Test.ps1`：理解如何生成单文件 BAT，以及如何检查生成文件和源码保持一致。

各函数和关键分支的注释解释输入输出、设计原因、边界条件及失败处理。注释使用英文；会嵌入 BAT 的源码必须保持 ASCII，以避免不同 Windows 代码页引起乱码，测试中的中文使用 C# Unicode 转义。

### 运行开发检查

版本号统一保存在根目录 `VERSION`，采用 `主版本.次版本.修订号`。构建时注入 BAT 标题、菜单、状态输出及 EXE 产品版本；Windows 文件版本追加 `.0`。修改版本后同步更新 `CHANGELOG.md` 并重新生成 BAT。仅修改源码版本号不会自动升级本机已安装的 EXE，需运行菜单 1。状态读取 EXE 文件元数据，不会执行它，也不会把脚本版本误认为已安装版本。

### 发布流程

1. 修改 `VERSION` 并添加对应的 `CHANGELOG.md` 条目。
2. 运行构建及测试，提交源码、版本文件和生成后的 BAT 到 `main`。
3. `Release` 工作流在 Windows 上验证并准备 BAT 与 SHA-256 校验文件，通过后创建对应的 `v主版本.次版本.修订号` 标签和 GitHub Release。

发布只在 `main` 上的 `VERSION` 变更时自动触发，也可以手动重试工作流。已存在的 Release 不会被覆盖；修正已发布版本应递增版本号。构建脚本自身不联网、不发布。仓库仅给发布任务授予 `contents: write` 权限；测试任务保持只读仓库权限。

修改源码后，从仓库根目录运行：

```powershell
.\scripts\Build.ps1
.\tests\Test.ps1
```

开发环境需要允许执行 `.ps1`；本项目不修改系统执行策略。提交时同步生成 BAT，不要只编辑生成文件，也不要提交 EXE、个人日志、恢复记录或注册表备份。

BAT 的 `/selftest` 参数会编译并测试网址处理和 Windows 参数引用，不安装、不打开浏览器；`/status` 只读检查配置。完整测试还创建并清理临时 HKCU 测试项。GitHub Actions 在 Windows 上自动执行相同检查。

自动测试不代表 Click to Do 端到端验证。转发和默认搜索已由目标环境用户确认；整合版安装、升级、卸载流程仍需实机回归验证。
