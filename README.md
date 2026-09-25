# ClickToDo Chrome Redirect

[English](README.en.md)

让 Windows 11「单击以执行」（Click to Do）的「搜索互联网」在 **Google Chrome** 中打开，并使用 **Chrome 所用个人资料的默认搜索引擎**。

面向这样一种具体环境：Edge 主程序已经卸载，但系统仍把 `microsoft-edge:` 链接交给 `pwahelper.exe`，随后打开微软商店的 Edge 安装页。本工具不重新安装 Edge，也不替换微软程序文件。

这是社区脚本，与 Microsoft、Google 或 OpenAI 无关联。不是通用的 Windows 默认浏览器修复工具。

## 快速开始

1. 下载仓库中的 **[ClickToDo-Chrome-Redirect.bat](ClickToDo-Chrome-Redirect.bat)**。在 GitHub 文件页使用 **Download raw file**，不要把网页另存为 BAT。
2. 右键 BAT，选择 **以管理员身份运行**，输入 **1** 安装或升级。
3. 关闭管理员窗口，普通双击同一个 BAT，输入 **3** 测试。
4. 实际使用 Click to Do 的「搜索互联网」，确认 Chrome 和搜索结果符合预期。

BAT 是自包含文件；使用时不需要克隆整个仓库。安装过程使用 Windows 自带的 .NET Framework C# 编译器，不下载可执行文件或第三方依赖。

| 菜单 | 功能 | 权限 |
| --- | --- | --- |
| 1 | 首次安装或升级，升级时备份上一版程序 | 管理员 |
| 2 | 卸载转发，恢复原有 IFEO 配置 | 管理员 |
| 3 | 用示例关键词测试 Chrome 默认搜索引擎 | 普通运行 |
| 4 | 查看安装配置和近期状态日志 | 普通运行 |
| 5 | 恢复升级前的上一版转发程序 | 管理员 |
| 6 | 退出 | 任意 |

如果已安装本项目早期拆分版脚本，选择 **1** 即可升级；会保留原来的卸载恢复信息。菜单 **5** 只回滚程序，不卸载转发。

## 兼容条件

- x64 Windows；目前实际验证环境为 **Windows 11 25H2，Build 26200.9457**，Click to Do **1000.26100.9457.0**。其他版本未经实机验证，ARM64 不支持。
- Chrome 已安装在系统级 `Program Files` 或 `Program Files (x86)` 中。仅安装在用户 `LocalAppData` 的 Chrome 暂不支持。
- 下列文件仍存在：`%ProgramFiles(x86)%\Microsoft\Edge\Application\pwahelper.exe`。
- 系统实际启动上述文件来处理 Click to Do 的链接。**仅仅存在文件还不够**；若系统启动其他程序，本工具不会接管。
- 安装、升级、卸载、回滚需要管理员权限；测试应在普通权限下运行。
- Windows PowerShell 5.1、.NET Framework 编译器可用。

脚本遇到既有 IFEO 调试器/过滤器、旧的当前用户 `microsoft-edge` 覆盖项或不一致的安装状态时，会停止并提示，不覆盖未知配置。

## 工作原理

```text
Click to Do → microsoft-edge: 链接 → pwahelper.exe 启动请求
    → IFEO 按完整文件路径匹配 → 本地转发程序
    → Bing /search?q=关键词：交给 Chrome 的默认搜索引擎
    → 其他 HTTP/HTTPS 地址：直接用 Chrome 打开
```

使用 Windows **Image File Execution Options（IFEO）** 的 `Debugger`、`UseFilter` 和 `FilterFullPath`，只匹配指定完整路径的 `pwahelper.exe`。不会更改 HTTP/HTTPS 默认关联，也不修改 Chrome 的搜索引擎设置。

对于 `bing.com` 及其子域名下的 `/search?q=...`，转发程序解码 `q` 参数，再以 Chrome 支持的 `? 关键词` 参数发起搜索。搜索引擎由 Chrome 选择的个人资料决定，未固定为 Google。其他 Bing 地址（包括图片搜索）和普通网页保持网址访问方式。

此过滤器按程序路径生效，**不能只区分 Click to Do**。该路径的其他 `pwahelper.exe` 调用也会进入转发程序。没有 HTTP/HTTPS 地址的调用会提示不支持，不会继续启动原帮助程序；如果影响其他功能，请卸载。

参考：[Microsoft IFEO 介绍](https://techcommunity.microsoft.com/blog/askperf/two-minute-drill-configuring-a-debugger-using-image-file-execution-options/373478)、[Chromium 命令行搜索实现](https://github.com/chromium/chromium/blob/main/chrome/browser/ui/startup/startup_tab_provider.cc)。

## 更改范围与卸载

程序、源码和恢复记录保存在：

```text
%ProgramFiles%\ClickToDoPwaRedirect\
```

注册表更改位于：

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe
  UseFilter = 1
  ClickToDoChromeRedirect\
    FilterFullPath = [指定 pwahelper.exe 的完整路径]
    Debugger = "[Program Files]\ClickToDoPwaRedirect\PwaRedirect.exe"
```

安装前记录 `UseFilter` 的原有状态；若原项存在，还导出注册表备份。升级以文件替换方式更新程序并保留上一版。卸载只移除本工具的过滤器，恢复没有被其他软件修改的原配置，保留外部新增设置。

以管理员身份运行 BAT，选择 **2** 即可停止转发。卸载后保留不再使用的程序、源码、备份和日志，便于检查；确认卸载成功后可以手动删除这些文件。不要在转发仍启用时直接删除安装目录，否则该帮助程序会无法启动。

## 日志与隐私

日志位置：`%LOCALAPPDATA%\ClickToDoPwaRedirect\status.log`。

只记录时间和调用状态，不记录网址、搜索词或浏览器个人资料。日志超过约 256 KiB 时重新开始。没有遥测、后台常驻服务或自动更新；只有启动时运行。执行搜索会像普通浏览器搜索一样把关键词发送给 Chrome 所用的搜索引擎。

## 常见问题

**为什么默认浏览器已经是 Chrome，还会出现微软商店？**

HTTP/HTTPS 默认关联与 `microsoft-edge:` 不同。目标环境中后者启动 `pwahelper.exe`，而不是 HTTP/HTTPS 的默认程序。不能仅根据遗留的 `UserChoice` 值判断默认浏览器未设置成功。

**仍然使用 Bing？**

先用菜单 4 查看日志。出现 `chrome-default-search-requested` 表示已提交默认搜索；此时检查 Chrome 所用个人资料的默认搜索引擎。出现 `chrome-url-launch-requested` 表示链接不符合支持的 Bing 网页搜索格式。多个人资料用户注意：工具没有固定 `--profile-directory`，由 Chrome 自行选择个人资料。

**缺少 pwahelper.exe、仍打开商店，或没有应用程序关联？**

菜单 4 查看文件与过滤器状态；确认使用普通权限测试。缺少文件时本工具不适用，不会为此安装 Edge。若残留旧协议覆盖，请先用其原脚本撤销。Windows 更新可能改变调用路径或行为；测试失败时可以用菜单 2 卸载，不保证所有 Windows 版本都适用。

**卸载或升级因配置被修改而停止？**

脚本会保留未知配置。请保留安装目录的 `state.json`、注册表备份及报错内容用于检查，不要盲目删除整个 `pwahelper.exe` 注册表项。不要同时运行多个安装窗口。

## 开发与验证

仓库主文件：

```text
ClickToDo-Chrome-Redirect.bat    可分发的单文件入口，由源码生成
src/PwaRedirect.cs             参数解析、Bing 搜索转换、Chrome 启动
src/Setup.ps1                  安装、升级、恢复与诊断
scripts/Launcher.bat.in        BAT 启动模板
scripts/Build.ps1              生成单文件 BAT
tests/Test.ps1                 生成一致性、语法与程序自测
```

在 Windows PowerShell 中，从仓库根目录运行：

```powershell
.\scripts\Build.ps1
.\tests\Test.ps1
```

上述开发命令需要当前环境允许执行 `.ps1` 文件；受限制的机器可以在允许脚本运行的开发环境或 GitHub Actions 中构建和测试。本项目不会修改系统执行策略。

单独运行 `ClickToDo-Chrome-Redirect.bat /selftest` 可编译并执行网址处理和 Windows 参数引用测试；`/status` 只读检查安装。完整测试还会在临时 HKCU 注册表测试项中验证恢复逻辑，并清理测试项；不会修改真实 IFEO 配置、安装转发或打开浏览器。CI 在 Windows 上执行同样的检查；系统安装/卸载和 Click to Do 的端到端行为仍需在测试机器上人工验证。

提交修改时同步生成 BAT。请勿提交程序二进制、个人日志、`state.json` 或注册表备份。初次仓库发布的完整安装管理流程尚需实机回归；转发及默认搜索功能已由目标环境用户确认可用。

## 许可证

[MIT](LICENSE)。
