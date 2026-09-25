# ClickToDo Chrome Redirect

[简体中文](README.md)

Open Windows 11 **Click to Do → Search the web** in **Chrome with its default search engine**, instead of the Edge Microsoft Store page after Edge is uninstalled.

## Quick start

**Download only [ClickToDo-Chrome-Redirect.bat](https://github.com/Noemion/ClickToDo-Chrome-Redirect/raw/refs/heads/main/ClickToDo-Chrome-Redirect.bat). No other repository files are required.**

1. Right-click the BAT → **Run as administrator** → choose **1** to install.
2. Close that window, run the BAT normally → choose **3** to test.
3. Use Click to Do's **Search the web** and confirm the result.

Choose **1** again to update, or **2** to uninstall. Setup downloads no additional dependencies and does not reinstall Edge.

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
| `.github/workflows/` | Automated checks running on GitHub |
| `docs/` | Implementation, troubleshooting and development notes |
| `README.md` / `README.en.md` | Chinese / English usage guides |
| `CHANGELOG.md` / `LICENSE` | Version history / MIT license |
| `.gitignore` / `.gitattributes` | Git exclusions / line-ending rules |

The BAT embeds the source and does not depend on the other files at runtime. Installed files and restore state live in `%ProgramFiles%\ClickToDoPwaRedirect\`. **Uninstall through the menu before deleting that directory.** Keep the BAT for future management.

## More information

- [Technical and development notes (Chinese)](docs/DEVELOPMENT.md)
- [Changelog](CHANGELOG.md) · [Report an issue](https://github.com/Noemion/ClickToDo-Chrome-Redirect/issues) · [MIT license](LICENSE)

Independent community project, not affiliated with Microsoft, Google or OpenAI.
