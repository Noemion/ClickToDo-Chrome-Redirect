@echo off
rem Template only. Build.ps1 appends the PowerShell and C# payload below.
rem Keep variables local so running this BAT does not change the caller's session.
setlocal
rem Build.ps1 substitutes the repository VERSION; no adjacent file is needed.
set "CTD_VERSION=0.1.1"
title ClickToDo Chrome Redirect v%CTD_VERSION%
echo ClickToDo Chrome Redirect v%CTD_VERSION%
rem Noninteractive modes return an exit code without pausing for input.
if /i "%~1"=="/version" exit /b 0
if /i "%~1"=="/selftest" (set "CTD_ACTION=7" & goto run)
if /i "%~1"=="/status" (set "CTD_ACTION=4" & goto run)
if not "%~1"=="" (echo Supported arguments: /version /selftest /status & exit /b 2)
echo 1. Install or update (Run as administrator)
echo 2. Uninstall redirect (Run as administrator)
echo 3. Test default search (run normally)
echo 4. Show status
echo 5. Roll back previous program (Run as administrator)
echo 6. Exit
choice /c 123456 /n /m "Select [1-6]: "
rem CHOICE returns the one-based position of the selected key as ERRORLEVEL.
set "CTD_ACTION=%errorlevel%"
if "%CTD_ACTION%"=="6" exit /b 0
:run
rem Pass this file path through the environment rather than interpolating it
rem into PowerShell source, preserving spaces and special characters in paths.
set "CTD_SELF=%~f0"
rem Read only the payload after the exact marker line. Exit below prevents
rem cmd.exe from interpreting any PowerShell or C# lines as batch commands.
powershell.exe -NoProfile -Command "$s=[IO.File]::ReadAllText($env:CTD_SELF); & ([scriptblock]::Create(($s -split '(?m)^:POWERSHELL\r?\n',2)[1])) -Action $env:CTD_ACTION"
set "CTD_EXIT=%errorlevel%"
rem Save the payload result before PAUSE changes the process error level.
if not "%~1"=="" exit /b %CTD_EXIT%
echo.
pause
exit /b %CTD_EXIT%
:POWERSHELL
# This file is an installer payload, not the standalone distribution. Build.ps1
# injects the C# source at the marker below and appends this payload to the BAT.
# Dispatch: 1 install/update, 2 uninstall, 3 browser test, 4 read-only status,
# 5 restore previous executable, 7 isolated compilation/self-test for CI.
# Keep comments ASCII because the whole payload is embedded in an ASCII BAT.
param([ValidateSet('1','2','3','4','5','7')][string]$Action = '4')
# Treat cmdlet failures as terminating errors so later setup steps do not run
# after a failed write. Native compiler/reg.exe exit codes are checked separately.
$ErrorActionPreference = 'Stop'
# The build embeds this value; it is the downloaded BAT's version, not proof
# that the machine's installed executable has been upgraded to the same version.
$scriptVersion = '0.1.1'
$source = @'
// Forwarding pipeline: IFEO arguments -> first HTTP(S) URL -> optional Bing query
// conversion -> one quoted Chrome argument. This program runs only on demand;
// it does not watch processes, change browser preferences, or run as a service.
// Keep this source ASCII: Build.ps1 embeds it in the distributable BAT. Use C#
// Unicode escapes for non-ASCII test data rather than changing the BAT encoding.
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
// Build.ps1 injects assembly/file/product version attributes from VERSION here.
// Metadata allows status checks without executing the installed program.
[assembly: System.Reflection.AssemblyVersion("0.1.1.0")]
[assembly: System.Reflection.AssemblyFileVersion("0.1.1.0")]
[assembly: System.Reflection.AssemblyInformationalVersion("0.1.1")]
public static class PwaRedirect {
    // These Win32 imports are used only by the quoting self-test. Windows passes
    // a command-line string to a child process, so test with a real Windows parser
    // instead of assuming that placing quotes around text preserves argv.
    [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr ptr);
    /// <summary>
    /// Check that Quote produces exactly one argument with the original value.
    /// The dummy executable occupies argv[0]; our input must occupy argv[1].
    /// </summary>
    private static bool RoundTrip(string value) {
        int count;
        IntPtr argv = CommandLineToArgvW("test.exe " + Quote(value), out count);
        if (argv == IntPtr.Zero) return false;
        try { return count == 2 && Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, IntPtr.Size)) == value; }
        // CommandLineToArgvW allocates unmanaged memory owned by this caller.
        finally { LocalFree(argv); }
    }
    /// <summary>
    /// Convert a supported Bing web-search URL into Chrome's "? search terms"
    /// syntax. The caller supplies an absolute HTTP(S) URL from Extract.
    /// Return the original URL for everything else, including image searches.
    /// Chrome, not this program, selects the profile and its default engine.
    /// </summary>
    public static string BrowserInput(string url) {
        Uri uri = new Uri(url);
        // The leading dot in the suffix is a hostname boundary: accept
        // cn.bing.com, but never bing.com.evil.example or notbing.com.
        bool bing = uri.Host.Equals("bing.com", StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith(".bing.com", StringComparison.OrdinalIgnoreCase);
        if (bing && uri.AbsolutePath.TrimEnd('/').Equals("/search", StringComparison.OrdinalIgnoreCase)) {
            // Split before decoding so an encoded ampersand (%26) stays inside
            // the search term. Split each pair on its first '=' for the same reason.
            foreach (string part in uri.Query.TrimStart('?').Split('&')) {
                int eq = part.IndexOf('=');
                if (eq < 0) continue;
                // Form-style query strings use '+' for space; decode %2B only
                // afterward so a literal encoded plus sign remains a plus sign.
                string name = Uri.UnescapeDataString(part.Substring(0, eq).Replace("+", " "));
                if (!name.Equals("q", StringComparison.OrdinalIgnoreCase)) continue;
                string query = Uri.UnescapeDataString(part.Substring(eq + 1).Replace("+", " "));
                // A NUL cannot be represented in a Windows process command line.
                // Prefixing with '? ' also keeps query text such as --incognito
                // in search mode rather than presenting it as a Chrome switch.
                if (!String.IsNullOrWhiteSpace(query) && query.IndexOf('\0') < 0) return "? " + query;
            }
        }
        // Missing/empty q or a different endpoint is still a valid web link.
        return url;
    }
    /// <summary>
    /// Encode one Windows argv value, including embedded quotes and backslashes.
    /// This is process-argument quoting, not cmd.exe/PowerShell escaping: no shell
    /// is used to launch Chrome. Always quote, including empty strings.
    /// </summary>
    public static string Quote(string value) {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
        // Buffer a run of backslashes until its following character is known.
        // Before a literal quote, emit 2*n+1 backslashes; before ordinary text,
        // keep n backslashes unchanged. A final run must be doubled because it
        // immediately precedes the closing delimiter added below.
        foreach (char c in value) {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') { result.Append('\\', slashes * 2 + 1); result.Append(c); }
            else { result.Append('\\', slashes); result.Append(c); }
            slashes = 0;
        }
        result.Append('\\', slashes * 2);
        result.Append('"');
        return result.ToString();
    }
    /// <summary>
    /// Find the first absolute HTTP(S) URL in an IFEO launch command. IFEO adds
    /// the original executable path, and the helper contributes switches such as
    /// --launch-edge-store-page; none of those non-URL arguments go to Chrome.
    /// Return null for unsupported inputs, rather than executing a local path.
    /// </summary>
    public static string Extract(string[] args) {
        foreach (string arg in args) {
            string s = arg;
            // 15 is the length of "microsoft-edge:". Strip exactly one wrapper;
            // leave URL escaping intact until the search-query conversion stage.
            if (s.StartsWith("microsoft-edge:", StringComparison.OrdinalIgnoreCase)) s = s.Substring(15);
            Uri uri;
            if (Uri.TryCreate(s, UriKind.Absolute, out uri) && (uri.Scheme == "https" || uri.Scheme == "http")) return uri.AbsoluteUri;
        }
        return null;
    }
    // STA supports the Windows Forms error dialogs in this console-less EXE.
    // Runtime exit codes: 0 = launch requested, 2 = unsupported input, 3 = error.
    // Self-test exit codes 10-20 identify a failed check; no browser is opened.
    [STAThread] public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--self-test") {
            // 10-13: helper prefixes, ordinary URLs, blocked file URLs, no URL.
            // 14-17: Unicode/form decoding, hostname boundary, unrelated endpoint,
            // and a missing query. 18-20: quoting and switch-like query text.
            if (Extract(new string[]{"pwahelper.exe", "--launch-edge-store-page", "--single-argument", "microsoft-edge:https://www.google.com/search?q=a%26b"}) != "https://www.google.com/search?q=a%26b") return 10;
            if (Extract(new string[]{"--single-argument", "https://example.com/?a=1&b=2"}) != "https://example.com/?a=1&b=2") return 11;
            if (Extract(new string[]{"microsoft-edge:file:///C:/Windows/notepad.exe"}) != null) return 12;
            if (Extract(new string[]{"--launch-edge-store-page"}) != null) return 13;
            if (BrowserInput("https://www.bing.com/search?q=%E4%B8%AD%E6%96%87+a%2Bb%26c&form=test") != "? \u4e2d\u6587 a+b&c") return 14;
            if (BrowserInput("https://bing.com.evil.example/search?q=test") != "https://bing.com.evil.example/search?q=test") return 15;
            if (BrowserInput("https://www.bing.com/images/search?q=test") != "https://www.bing.com/images/search?q=test") return 16;
            if (BrowserInput("https://www.bing.com/search?form=test") != "https://www.bing.com/search?form=test") return 17;
            if (Quote("a\"b\\") != "\"a\\\"b\\\\\"") return 18;
            if (BrowserInput("https://cn.bing.com/search?q=--incognito") != "? --incognito") return 19;
            // These values must each remain a single argument after Windows
            // parsing, even when they contain whitespace or shell metacharacters.
            foreach (string sample in new string[]{"", "a b", "\u4e2d\u6587", "a\"b", "a\\", "a\\\"b", "? --incognito", "? a&b|c%PATH%", "line\nbreak"}) {
                if (!RoundTrip(sample)) return 20;
            }
            return 0;
        }
        // Keep diagnostics per user. Never log arguments, URLs, or search terms.
        // Logging is best-effort: permissions or concurrent writes must not
        // prevent a browser launch. The size threshold is approximate, not a
        // synchronized rotation scheme shared across simultaneous invocations.
        string logDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "ClickToDoPwaRedirect");
        Action<string> log = delegate(string status) {
            try {
                Directory.CreateDirectory(logDir);
                string path = Path.Combine(logDir,"status.log");
                if (File.Exists(path) && new FileInfo(path).Length > 262144) File.WriteAllText(path, "");
                File.AppendAllText(path, DateTime.Now.ToString("O") + " " + status + Environment.NewLine);
            } catch { }
        };
        log("invoked");
        string url = Extract(args);
        // Do not relaunch the original helper here: the same IFEO filter would
        // intercept that launch again, causing a forwarding loop.
        if (url == null) { log("no-supported-url"); MessageBox.Show("No HTTP/HTTPS URL found. This redirect only supports web links. Remove it using option 2 if it interferes with other Edge helper operations.", "Click to Do redirect"); return 2; }
        try {
            // Match the installer's system-wide Chrome prerequisite. Avoid a
            // PATH lookup or a fallback to the microsoft-edge protocol.
            string chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) throw new FileNotFoundException("Chrome was not found in Program Files.");
            string input = BrowserInput(url);
            // UseShellExecute=false starts Chrome directly. Quote protects the
            // one argument; cmd.exe is never involved, and no profile or engine
            // is forced. A successful Start only means the launch was requested,
            // not that the resulting page was loaded successfully.
            Process.Start(new ProcessStartInfo(chrome, Quote(input)) {UseShellExecute=false});
            log(input.StartsWith("? ") ? "chrome-default-search-requested" : "chrome-url-launch-requested");
            return 0;
        } catch (Exception e) { log("launch-failed"); MessageBox.Show(e.Message,"Click to Do redirect"); return 3; }
    }
}
'@

# Read file metadata without running the EXE. Early scripts did not write version
# resources, so report them honestly as legacy instead of borrowing this BAT's
# version. The same helper is used for the live EXE and rollback backup.
function Get-ProgramVersion([string]$Path) {
    if (!(Test-Path -LiteralPath $Path -PathType Leaf)) { return 'not installed' }
    $info = [Diagnostics.FileVersionInfo]::GetVersionInfo($Path)
    if ([string]::IsNullOrWhiteSpace($info.ProductVersion) -or $info.ProductVersion -eq '0.0.0.0') { return 'unknown (legacy build)' }
    return $info.ProductVersion
}

# Only machine-changing actions require elevation. Do not auto-elevate: the
# caller chooses the account and sees the usual Windows elevation prompt.
function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Right-click the BAT and select Run as administrator for install, update, uninstall or rollback.'
    }
}
# Check an existing file AND all existing ancestors. Reject junctions/symlinks
# so privileged writes do not follow a redirected installation path. Missing
# components are allowed because the first installation creates its directory.
# This is a preflight check, not a defense against every concurrent path change.
function Assert-RegularPath([string]$Path) {
    $cursor = $Path
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Linked path is not supported: $cursor" }
        }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }
}
# State describes the registry BEFORE the first installation, not the current
# enabled filter. Updates must preserve it for eventual uninstall. These fields
# also accept the original split-script format used before the unified BAT:
# HadKey = root existed; HadUseFilter = value existed; UseFilter = original 0/1.
function Read-InstallState {
    if (!(Test-Path -LiteralPath $statePath)) { throw 'No saved installation state found. No registry changes made.' }
    Assert-RegularPath $statePath
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.HadKey -isnot [bool] -or $state.HadUseFilter -isnot [bool] -or $null -eq $state.UseFilter -or [long]$state.UseFilter -notin @(0,1)) {
        throw 'Invalid installation state; stopping instead of guessing original registry values.'
    }
    return $state
}
# Name alone does not establish ownership. Require both expected values and no
# unknown extra values/subkeys before changing or removing this filter.
# Paths are resolved by the dispatcher and shared with these helper functions.
function Assert-OwnedFilter {
    if (!(Test-Path -LiteralPath $filter)) { throw 'Installed filter is missing.' }
    $current = Get-Item -LiteralPath $filter
    if ($current.GetValue('Debugger') -ne $debugger -or $current.GetValue('FilterFullPath') -ne $target) { throw 'Filter changed externally. Stopping to preserve external changes.' }
    if ($current.SubKeyCount -ne 0 -or @($current.GetValueNames() | Where-Object { $_ -notin @('Debugger','FilterFullPath') }).Count) { throw 'Additional filter settings found. Stopping.' }
}
# Compile to a candidate path, never over the live EXE. /target:winexe prevents
# a console flashing during normal forwarding; /platform:x64 matches our scope.
# Wait for the EXE's isolated tests before the candidate can replace live code.
function Compile-Redirect([string]$SourcePath, [string]$OutputPath) {
    Set-Content -LiteralPath $SourcePath -Value $source -Encoding UTF8
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (!(Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler was not found.' }
    & $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll ("/out:" + $OutputPath) $SourcePath
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
    # A successful compile must also carry the version shown by this installer.
    # Check both the display version and the four-part Windows file version.
    $metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($OutputPath)
    if ($metadata.ProductVersion -ne $scriptVersion -or $metadata.FileVersion -ne "$scriptVersion.0") { throw 'Compiled executable version does not match this installer.' }
    $test = Start-Process -FilePath $OutputPath -ArgumentList '--self-test' -Wait -PassThru
    if ($test.ExitCode -ne 0) { throw "Redirect self-tests failed (exit $($test.ExitCode))." }
}
# Shared by uninstall and recovery after a failed fresh installation. Only remove
# our filter; the parent IFEO key may hold settings belonging to other software.
# AllowIncomplete is reserved for immediate setup failure: either expected value
# may be absent, but no conflicting values or unknown children are accepted.
function Restore-Registration($State, [switch]$AllowIncomplete) {
    if (Test-Path -LiteralPath $filter) {
        if ($AllowIncomplete) {
            $partial = Get-Item -LiteralPath $filter
            if ($partial.SubKeyCount -ne 0 -or @($partial.GetValueNames() | Where-Object { $_ -notin @('Debugger','FilterFullPath') }).Count -or
                ($null -ne $partial.GetValue('Debugger') -and $partial.GetValue('Debugger') -ne $debugger) -or
                ($null -ne $partial.GetValue('FilterFullPath') -and $partial.GetValue('FilterFullPath') -ne $target)) { throw 'Partial filter changed externally; automatic recovery stopped.' }
        } else { Assert-OwnedFilter }
        Remove-Item -LiteralPath $filter
    }
    if (!(Test-Path -LiteralPath $key)) { return }
    if (@(Get-ChildItem -LiteralPath $key).Count -eq 0) {
        # UseFilter is shared by every child filter under this executable. Only
        # restore it when no other filters remain. A value other than our enabled
        # value (1) is treated as an external change and left untouched.
        $currentUse = (Get-Item -LiteralPath $key).GetValue('UseFilter')
        if ($null -eq $currentUse -or $currentUse -eq 1) {
            if ($State.HadUseFilter) { New-ItemProperty -LiteralPath $key -Name UseFilter -Value ([int]$State.UseFilter) -PropertyType DWord -Force | Out-Null }
            else { Remove-ItemProperty -LiteralPath $key -Name UseFilter -ErrorAction SilentlyContinue }
        } else { Write-Host 'UseFilter changed externally; current value retained.' }
        $remaining = Get-Item -LiteralPath $key
        # Delete the parent only if we originally created it and it is now empty.
        if (!$State.HadKey -and $remaining.ValueCount -eq 0 -and $remaining.SubKeyCount -eq 0) { Remove-Item -LiteralPath $key }
    } else { Write-Host 'Other filters exist; their settings and UseFilter are retained.' }
}

try {
    # Avoid 32-bit registry redirection and unsupported ARM64 compiler/runtime
    # assumptions by failing early rather than touching a different IFEO view.
    if (![Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Use 64-bit Windows PowerShell on x64 Windows.' }
    $dir = Join-Path $env:ProgramFiles 'ClickToDoPwaRedirect'
    # Keep the live program, candidate, previous program and original restore
    # state together. File.Replace below requires same-volume replacement files.
    $exe = Join-Path $dir 'PwaRedirect.exe'
    $previous = Join-Path $dir 'PwaRedirect.previous.exe'
    $candidate = Join-Path $dir 'PwaRedirect.new.exe'
    $sourcePath = Join-Path $dir 'PwaRedirect.cs'
    $statePath = Join-Path $dir 'state.json'
    $target = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\pwahelper.exe'
    # A child FilterFullPath narrows interception to this helper's exact path;
    # setting a Debugger directly on the parent would intercept by filename.
    # The native spelling is for reg.exe export; HKLM: is for PowerShell cmdlets.
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe'
    $nativeKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe'
    $filter = "$key\ClickToDoChromeRedirect"
    $debugger = '"' + $exe + '"'
    if ($Action -eq '7') {
        # CI uses a unique temporary directory and returns before any machine
        # configuration or browser-launch branch. Clean only the known test files.
        $scratch = Join-Path ([IO.Path]::GetTempPath()) ('ClickToDo-tests-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $scratch | Out-Null
        try { Compile-Redirect (Join-Path $scratch 'test.cs') (Join-Path $scratch 'test.exe'); Write-Host 'Compilation and self-tests passed. No installation or registry changes.' }
        finally {
            foreach ($name in @('test.cs','test.exe')) { $file = Join-Path $scratch $name; if (Test-Path -LiteralPath $file) { Remove-Item -LiteralPath $file } }
            if (@(Get-ChildItem -LiteralPath $scratch -Force).Count -eq 0) { Remove-Item -LiteralPath $scratch }
        }
        exit 0
    }
    if ($Action -eq '4') {
        # Diagnostics are read-only and work without elevation. File existence
        # alone is not proof that Windows actually routes a launch to the helper.
        Write-Host "Script version: $scriptVersion"
        Write-Host "Installed program version: $(Get-ProgramVersion $exe)"
        Write-Host "Previous program version: $(Get-ProgramVersion $previous)"
        Write-Host "Helper present: $(Test-Path -LiteralPath $target)"
        Write-Host "Program present: $(Test-Path -LiteralPath $exe)"
        Write-Host "Restore state present: $(Test-Path -LiteralPath $statePath)"
        Write-Host "Previous version available: $(Test-Path -LiteralPath $previous)"
        if (Test-Path -LiteralPath $filter) { Get-ItemProperty -LiteralPath $filter | Select-Object Debugger,FilterFullPath | Format-List }
        if (Test-Path -LiteralPath $key) { Write-Host "UseFilter: $((Get-Item -LiteralPath $key).GetValue('UseFilter'))" }
        $log = Join-Path $env:LOCALAPPDATA 'ClickToDoPwaRedirect\status.log'
        if (Test-Path -LiteralPath $log) { Write-Host 'Recent status (no URLs or search terms):'; Get-Content -LiteralPath $log -Tail 10 }
        exit 0
    }
    if ($Action -eq '3') {
        # A real protocol launch exercises Windows routing. Require a normal
        # user context so the test does not intentionally launch an elevated
        # browser or a different administrator account's browser profile.
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Close this elevated window and run normally to test with your usual Chrome profile.' }
        Assert-OwnedFilter
        if (!(Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $key).GetValue('UseFilter') -ne 1) { throw 'The redirect is not fully installed.' }
        Start-Process 'microsoft-edge:https://www.bing.com/search?q=Click+to+Do+default+search+test'
        Write-Host 'Check which search engine Chrome opens, then test Search the web in Click to Do.'
        Write-Host 'A successful protocol launch does not by itself prove the result is correct.'
        exit 0
    }
    # All remaining branches modify Program Files and/or machine-wide IFEO state.
    Assert-Administrator
    foreach ($path in @($dir,$exe,$previous,$candidate,$sourcePath,$statePath)) { Assert-RegularPath $path }
    if ($Action -eq '2') {
        # Remove routing before retiring state.json. Keep archived state and
        # binaries for inspection; automatic cleanup must not destroy recovery data.
        $state = Read-InstallState
        Restore-Registration $state
        Move-Item -LiteralPath $statePath -Destination (Join-Path $dir ('state.uninstalled-' + [guid]::NewGuid().ToString('N') + '.json'))
        Write-Host 'Redirect uninstalled. Original IFEO state restored where unchanged by other software.'
        Write-Host "Inactive binaries/backups remain in $dir; logs remain in LocalAppData. You may delete them manually."
        exit 0
    }
    if ($Action -eq '5') {
        # Rollback changes only the EXE, not the original registry restore state.
        # Copy the backup to a candidate first so the backup survives repeated use.
        $null = Read-InstallState; Assert-OwnedFilter
        if (!(Test-Path -LiteralPath $previous)) { throw 'No previous version exists. Rollback requires an earlier update.' }
        Copy-Item -LiteralPath $previous -Destination $candidate -Force
        [IO.File]::Replace($candidate,$exe,$null)
        Write-Host "Previous program restored: $(Get-ProgramVersion $exe). Registry configuration unchanged."
        exit 0
    }
    # From here onward Action is 1. Validate the known launch route and Chrome
    # location before compiling or writing registry configuration. An old HKCU
    # protocol override can prevent Windows from ever reaching our IFEO target.
    if (!(Test-Path -LiteralPath $target)) { throw 'pwahelper.exe not found. This Edge removal state is not supported.' }
    if (Test-Path -LiteralPath 'HKCU:\Software\Classes\microsoft-edge') { throw 'A current-user protocol override exists. Remove that experiment before installation.' }
    $chrome = @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$chrome) { throw 'A system-wide Chrome installation is required (Program Files).' }
    $update = Test-Path -LiteralPath $statePath
    if ($update) {
        # Reuse first-install state. Do not snapshot the currently enabled filter
        # as the "original" configuration, or uninstall would re-enable ourselves.
        $state = Read-InstallState; Assert-OwnedFilter
        if ((Get-Item -LiteralPath $key).GetValue('UseFilter') -ne 1 -or (Get-Item -LiteralPath $key).GetValue('Debugger')) { throw 'IFEO settings changed externally. Update stopped.' }
        if (!(Test-Path -LiteralPath $exe)) { throw 'Installed executable missing. Uninstall first, then install again.' }
    } else {
        # A fresh installation refuses competing IFEO settings rather than
        # guessing which debugger/filter should take precedence.
        $hadKey = Test-Path -LiteralPath $key; $hadUse = $false; $use = 0
        if ($hadKey) {
            $current = Get-Item -LiteralPath $key
            if (($current.GetValueNames() -contains 'Debugger') -or $current.SubKeyCount -gt 0) { throw 'Existing IFEO debugger/filters found. Installation stopped to avoid conflicts.' }
            $hadUse = $current.GetValueNames() -contains 'UseFilter'
            if ($hadUse) {
                if ($current.GetValueKind('UseFilter') -ne [Microsoft.Win32.RegistryValueKind]::DWord) { throw 'Unexpected UseFilter registry type.' }
                $use = [int]$current.GetValue('UseFilter')
                if ($use -notin @(0,1)) { throw 'Unexpected UseFilter value.' }
            }
        }
        $state = [pscustomobject]@{ HadKey=$hadKey; HadUseFilter=$hadUse; UseFilter=$use }
    }
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    # No redirect is enabled until the candidate compiles and passes its tests.
    Compile-Redirect $sourcePath $candidate
    if ($update) {
        # When binary bytes match, leave the previous-version backup intact.
        # Otherwise replace the live file while saving its prior bytes for menu 5.
        if ((Get-FileHash -LiteralPath $candidate).Hash -eq (Get-FileHash -LiteralPath $exe).Hash) { Remove-Item -LiteralPath $candidate; Write-Host 'Installed program matches this build.' }
        else { [IO.File]::Replace($candidate,$exe,$previous); Write-Host 'Updated. Option 5 restores the previous program.' }
    } else {
        # Export existing machine settings as an extra manual recovery artifact.
        # Automated recovery uses the smaller state.json, not a blanket import
        # that could overwrite changes made later by unrelated software.
        if ($state.HadKey) {
            $exportPath = Join-Path $dir ('ifeo-before-' + [guid]::NewGuid().ToString('N') + '.reg')
            & reg.exe export $nativeKey $exportPath /y
            if ($LASTEXITCODE -ne 0) { throw 'Registry backup failed.' }
        }
        if (Test-Path -LiteralPath $exe) { [IO.File]::Replace($candidate,$exe,$previous) }
        else { Move-Item -LiteralPath $candidate -Destination $exe }
        # Persist original-state information before the first registry mutation.
        # The live executable must also exist before Windows can route to it.
        $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        try {
            New-Item -Path $filter -Force | Out-Null
            New-ItemProperty -LiteralPath $filter -Name FilterFullPath -Value $target -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath $filter -Name Debugger -Value $debugger -PropertyType String -Force | Out-Null
            # Enable path filtering after the child values have been populated.
            New-ItemProperty -LiteralPath $key -Name UseFilter -Value 1 -PropertyType DWord -Force | Out-Null
            Assert-OwnedFilter
        } catch {
            # Fresh-install registry writes are multiple operations, not one
            # transaction. Undo a partially populated filter when safe; if that
            # fails, retain state.json/backups and report the original failure.
            $installFailure = $_
            try {
                Restore-Registration $state -AllowIncomplete
                Move-Item -LiteralPath $statePath -Destination (Join-Path $dir ('state.failed-' + [guid]::NewGuid().ToString('N') + '.json'))
            } catch { Write-Host 'Automatic registry recovery failed. Retain state.json and registry backups for manual recovery.' }
            throw $installFailure
        }
        Write-Host 'Installed successfully.'
    }
    Write-Host "Installed program version: $(Get-ProgramVersion $exe)"
    Write-Host 'Bing web searches use the Chrome profile default search engine; normal URLs are unchanged.'
    Write-Host 'Close this elevated window. Run normally, choose 3, then test Click to Do itself.'
# Surface errors in the BAT window and return a failing exit code to callers/CI.
} catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
