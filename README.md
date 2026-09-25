# ClickToDo Chrome Redirect

[简体中文](README.zh-CN.md)

[Releases](https://github.com/Noemion/ClickToDo-Chrome-Redirect/releases) · [Current source version](VERSION) · [Changelog](CHANGELOG.md)

Open Windows 11 **Click to Do → Search the web** in **Chrome with its default search engine**, instead of the Edge Microsoft Store page after Edge is uninstalled.

## Quick start

**Download only `ClickToDo-Chrome-Redirect.bat` from [Releases](https://github.com/Noemion/ClickToDo-Chrome-Redirect/releases). No other repository files are required.** Each release includes a SHA-256 checksum and a matching Git tag. The [main-branch BAT](https://github.com/Noemion/ClickToDo-Chrome-Redirect/raw/refs/heads/main/ClickToDo-Chrome-Redirect.bat) may include changes not yet released.

1. Right-click the BAT → **Run as administrator** → choose **1** to install.
2. Close that window, run the BAT normally → choose **3** to test.
3. Use Click to Do's **Search the web** and confirm the result.

Choose **1** again to update, or **2** to uninstall. Setup downloads no additional dependencies and does not reinstall Edge.

The startup banner shows the script version. Option **4** shows the installed program version separately; `/version` prints only the banner. Older unversioned installs show `unknown (legacy build)` until upgraded with option 1.

| Option | Action | Permissions |
| --- | --- | --- |
| 1 | Install / update | Administrator |
| 2 | Uninstall redirect | Administrator |
| 3 | Test default search | Normal |
| 4 | Show status | Normal |
| 5 | Restore the program from before the last update | Administrator |
| 6 | Exit | Either |

## Requirements

- **x64 Windows 11**, with system-wide Chrome in Program Files.
- Edge is removed, but `%ProgramFiles(x86)%\Microsoft\Edge\Application\pwahelper.exe` remains and is actually launched by Click to Do.
- Windows PowerShell 5.1 and the built-in .NET Framework C# compiler.

Forwarding and default search were verified on **Windows 11 25H2 (26200.9457) / Click to Do 1000.26100.9457.0**. Other versions are unverified; ARM64 is unsupported.

**Note:** Other launches of that exact helper path are intercepted too; uninstall if this disrupts other features. The search engine comes from the profile Chrome selects. Ordinary URLs are opened unchanged. Windows updates may change compatibility.

## Repository guide

| File / directory | Purpose |
| --- | --- |
| `ClickToDo-Chrome-Redirect.bat` | **Complete tool; the only file end users need** |
| `src/` | Forwarder and setup source code |
| `scripts/` | Build script and launcher template |
| `tests/` | Argument handling, artifact consistency and recovery tests |
| `.github/workflows/` | Automated checks and versioned release publishing |
| `docs/` | Implementation, troubleshooting and development notes |
| `README.md` / `README.zh-CN.md` | English / Chinese usage guides |
| `CHANGELOG.md` / `LICENSE` | Version history / MIT license |
| `VERSION` | Single source of the build version |
| `.gitignore` / `.gitattributes` | Git exclusions / line-ending rules |

The BAT embeds the source and does not depend on the other files at runtime. Installed files and restore state live in `%ProgramFiles%\ClickToDoPwaRedirect\`. **Uninstall through the menu before deleting that directory.** Keep the BAT for future management.

## More information

- [Technical and development notes (Chinese)](docs/DEVELOPMENT.md)
- [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/Noemion/ClickToDo-Chrome-Redirect/issues) · [MIT license](LICENSE)

Independent community project, not affiliated with Microsoft, Google or OpenAI.
