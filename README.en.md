# ClickToDo Chrome Redirect

[简体中文](README.md)

Open Windows 11 **Click to Do → Search the web** in Google Chrome, using the default search engine of the profile Chrome selects.

This targets a specific state: Edge is uninstalled, but `microsoft-edge:` still launches `pwahelper.exe`, which opens the Edge Microsoft Store page. It does not reinstall Edge, replace Microsoft executables, change HTTP/HTTPS associations, or change Chrome settings. This is an independent community tool, not affiliated with Microsoft, Google or OpenAI.

## Use

Download the raw **[ClickToDo-Chrome-Redirect.bat](ClickToDo-Chrome-Redirect.bat)** file. It contains the setup code and C# source; no repository checkout or dependency download is required.

| Option | Action | Run as administrator? |
| --- | --- | --- |
| 1 | Install or update | Yes |
| 2 | Uninstall the redirect | Yes |
| 3 | Test the default search engine | No |
| 4 | Show configuration and recent status | No |
| 5 | Restore the program from before the last update | Yes |
| 6 | Exit | Either |

After installation, close the elevated window, run normally, choose 3, and test Click to Do itself. A successful process launch is not proof that the correct results opened. Early versions of this project's separate scripts can be upgraded with option 1 while retaining their original uninstall state.

## Requirements and scope

- x64 Windows. User-confirmed forwarding environment: Windows 11 25H2, build 26200.9457; Click to Do 1000.26100.9457.0. Other versions are unverified; ARM64 is unsupported.
- System-wide Chrome in Program Files or Program Files (x86), not a user-only LocalAppData installation.
- `%ProgramFiles(x86)%\Microsoft\Edge\Application\pwahelper.exe` exists **and is the helper actually launched by the system**.
- Windows PowerShell 5.1 and the Windows .NET Framework C# compiler.
- Administrator rights for setup changes.

The script uses a full-path IFEO filter to redirect that helper's launch. Other calls to that exact helper path are also intercepted. Calls without an HTTP/HTTPS URL show an unsupported-operation message instead of running the original helper. Uninstall if this disrupts other uses. No background service is installed.

Only `bing.com` and its subdomains with path `/search` and a nonempty `q` parameter become default-engine searches. The query is decoded and passed using Chrome's `? search terms` command-line support. Other URLs, including Bing image search, are opened unchanged. Chrome chooses the profile; this tool does not force a profile or a particular engine.

References: [Microsoft IFEO overview](https://techcommunity.microsoft.com/blog/askperf/two-minute-drill-configuring-a-debugger-using-image-file-execution-options/373478), [Chromium search argument implementation](https://github.com/chromium/chromium/blob/main/chrome/browser/ui/startup/startup_tab_provider.cc).

## Changes and recovery

Files are installed under `%ProgramFiles%\ClickToDoPwaRedirect`. The only registry area changed is:

```text
HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe
```

Setup saves the original `UseFilter` state, exports an existing registry key, and creates the `ClickToDoChromeRedirect` filter with `FilterFullPath` and `Debugger`. Unknown pre-existing filters/debuggers and current-user protocol overrides cause setup to stop. Updates save the previous executable; option 5 restores that executable without removing the filter.

Option 2 removes the owned filter and restores original settings where they have not been changed externally. Unused files, backups and logs remain for inspection and can be deleted manually afterward. Do not delete the installed executable while the filter remains active. Do not run simultaneous setup windows. If recovery stops, preserve `state.json`, registry backups and the error text instead of deleting the entire IFEO key.

Status is stored at `%LOCALAPPDATA%\ClickToDoPwaRedirect\status.log`. It contains timestamps and outcomes, not URLs, queries or profile information, and resets after approximately 256 KiB. There is no telemetry or automatic updating. Searches naturally send terms to the engine Chrome uses.

If results still use Bing, check option 4: `chrome-default-search-requested` means Chrome's selected profile decides the engine; `chrome-url-launch-requested` means the URL was not a supported Bing web-search URL. Missing helpers or changed Windows launch behavior are not fixed by this tool. Windows updates can change compatibility.

## Build and test

```powershell
.\scripts\Build.ps1
.\tests\Test.ps1
```

These development commands require an environment that permits `.ps1` execution. Use an authorized development environment or GitHub Actions if local script execution is restricted. The project does not change the system execution policy.

Edit `src/PwaRedirect.cs`, `src/Setup.ps1` and `scripts/Launcher.bat.in`, then regenerate the tracked BAT. `/selftest` runs the packaged program's compilation and URL/Windows-argument tests without installing or opening Chrome; `/status` is read-only. Full tests also exercise recovery against a temporary HKCU fixture and clean it up, never modifying the real IFEO configuration. GitHub Actions validates the generated artifact and runs these tests on Windows.

The consolidated install/update/uninstall management flow still needs manual regression on a test machine; successful forwarding/default search was confirmed with the earlier scripts. CI does not claim to test Click to Do or make system registry changes. Do not commit binaries, personal logs, registry backups or installation state.

## License

[MIT](LICENSE).
