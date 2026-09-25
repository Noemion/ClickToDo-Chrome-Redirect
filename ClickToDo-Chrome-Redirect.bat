@echo off
setlocal
title ClickToDo Chrome Redirect
if /i "%~1"=="/selftest" (set "CTD_ACTION=7" & goto run)
if /i "%~1"=="/status" (set "CTD_ACTION=4" & goto run)
if not "%~1"=="" (echo Supported arguments: /selftest /status & exit /b 2)
echo ClickToDo Chrome Redirect
echo 1. Install or update (Run as administrator)
echo 2. Uninstall redirect (Run as administrator)
echo 3. Test default search (run normally)
echo 4. Show status
echo 5. Roll back previous program (Run as administrator)
echo 6. Exit
choice /c 123456 /n /m "Select [1-6]: "
set "CTD_ACTION=%errorlevel%"
if "%CTD_ACTION%"=="6" exit /b 0
:run
set "CTD_SELF=%~f0"
powershell.exe -NoProfile -Command "$s=[IO.File]::ReadAllText($env:CTD_SELF); & ([scriptblock]::Create(($s -split '(?m)^:POWERSHELL\r?\n',2)[1])) -Action $env:CTD_ACTION"
set "CTD_EXIT=%errorlevel%"
if not "%~1"=="" exit /b %CTD_EXIT%
echo.
pause
exit /b %CTD_EXIT%
:POWERSHELL
param([ValidateSet('1','2','3','4','5','7')][string]$Action = '4')
$ErrorActionPreference = 'Stop'
$source = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using System.Windows.Forms;
public static class PwaRedirect {
    [DllImport("shell32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    private static extern IntPtr CommandLineToArgvW(string command, out int count);
    [DllImport("kernel32.dll")]
    private static extern IntPtr LocalFree(IntPtr ptr);
    private static bool RoundTrip(string value) {
        int count;
        IntPtr argv = CommandLineToArgvW("test.exe " + Quote(value), out count);
        if (argv == IntPtr.Zero) return false;
        try { return count == 2 && Marshal.PtrToStringUni(Marshal.ReadIntPtr(argv, IntPtr.Size)) == value; }
        finally { LocalFree(argv); }
    }
    public static string BrowserInput(string url) {
        Uri uri = new Uri(url);
        bool bing = uri.Host.Equals("bing.com", StringComparison.OrdinalIgnoreCase) || uri.Host.EndsWith(".bing.com", StringComparison.OrdinalIgnoreCase);
        if (bing && uri.AbsolutePath.TrimEnd('/').Equals("/search", StringComparison.OrdinalIgnoreCase)) {
            foreach (string part in uri.Query.TrimStart('?').Split('&')) {
                int eq = part.IndexOf('=');
                if (eq < 0) continue;
                string name = Uri.UnescapeDataString(part.Substring(0, eq).Replace("+", " "));
                if (!name.Equals("q", StringComparison.OrdinalIgnoreCase)) continue;
                string query = Uri.UnescapeDataString(part.Substring(eq + 1).Replace("+", " "));
                if (!String.IsNullOrWhiteSpace(query) && query.IndexOf('\0') < 0) return "? " + query;
            }
        }
        return url;
    }
    public static string Quote(string value) {
        StringBuilder result = new StringBuilder("\"");
        int slashes = 0;
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
    public static string Extract(string[] args) {
        foreach (string arg in args) {
            string s = arg;
            if (s.StartsWith("microsoft-edge:", StringComparison.OrdinalIgnoreCase)) s = s.Substring(15);
            Uri uri;
            if (Uri.TryCreate(s, UriKind.Absolute, out uri) && (uri.Scheme == "https" || uri.Scheme == "http")) return uri.AbsoluteUri;
        }
        return null;
    }
    [STAThread] public static int Main(string[] args) {
        if (args.Length == 1 && args[0] == "--self-test") {
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
            foreach (string sample in new string[]{"", "a b", "\u4e2d\u6587", "a\"b", "a\\", "a\\\"b", "? --incognito", "? a&b|c%PATH%", "line\nbreak"}) {
                if (!RoundTrip(sample)) return 20;
            }
            return 0;
        }
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
        if (url == null) { log("no-supported-url"); MessageBox.Show("No HTTP/HTTPS URL found. This redirect only supports web links. Remove it using option 2 if it interferes with other Edge helper operations.", "Click to Do redirect"); return 2; }
        try {
            string chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) chrome = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "Google\\Chrome\\Application\\chrome.exe");
            if (!File.Exists(chrome)) throw new FileNotFoundException("Chrome was not found in Program Files.");
            string input = BrowserInput(url);
            Process.Start(new ProcessStartInfo(chrome, Quote(input)) {UseShellExecute=false});
            log(input.StartsWith("? ") ? "chrome-default-search-requested" : "chrome-url-launch-requested");
            return 0;
        } catch (Exception e) { log("launch-failed"); MessageBox.Show(e.Message,"Click to Do redirect"); return 3; }
    }
}
'@

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (!([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Right-click the BAT and select Run as administrator for install, update, uninstall or rollback.'
    }
}
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
function Read-InstallState {
    if (!(Test-Path -LiteralPath $statePath)) { throw 'No saved installation state found. No registry changes made.' }
    Assert-RegularPath $statePath
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    if ($state.HadKey -isnot [bool] -or $state.HadUseFilter -isnot [bool] -or $null -eq $state.UseFilter -or [long]$state.UseFilter -notin @(0,1)) {
        throw 'Invalid installation state; stopping instead of guessing original registry values.'
    }
    return $state
}
function Assert-OwnedFilter {
    if (!(Test-Path -LiteralPath $filter)) { throw 'Installed filter is missing.' }
    $current = Get-Item -LiteralPath $filter
    if ($current.GetValue('Debugger') -ne $debugger -or $current.GetValue('FilterFullPath') -ne $target) { throw 'Filter changed externally. Stopping to preserve external changes.' }
    if ($current.SubKeyCount -ne 0 -or @($current.GetValueNames() | Where-Object { $_ -notin @('Debugger','FilterFullPath') }).Count) { throw 'Additional filter settings found. Stopping.' }
}
function Compile-Redirect([string]$SourcePath, [string]$OutputPath) {
    Set-Content -LiteralPath $SourcePath -Value $source -Encoding UTF8
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
    if (!(Test-Path -LiteralPath $compiler)) { throw '.NET Framework C# compiler was not found.' }
    & $compiler /nologo /target:winexe /platform:x64 /reference:System.Windows.Forms.dll ("/out:" + $OutputPath) $SourcePath
    if ($LASTEXITCODE -ne 0) { throw 'Compilation failed.' }
    $test = Start-Process -FilePath $OutputPath -ArgumentList '--self-test' -Wait -PassThru
    if ($test.ExitCode -ne 0) { throw "Redirect self-tests failed (exit $($test.ExitCode))." }
}
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
        $currentUse = (Get-Item -LiteralPath $key).GetValue('UseFilter')
        if ($null -eq $currentUse -or $currentUse -eq 1) {
            if ($State.HadUseFilter) { New-ItemProperty -LiteralPath $key -Name UseFilter -Value ([int]$State.UseFilter) -PropertyType DWord -Force | Out-Null }
            else { Remove-ItemProperty -LiteralPath $key -Name UseFilter -ErrorAction SilentlyContinue }
        } else { Write-Host 'UseFilter changed externally; current value retained.' }
        $remaining = Get-Item -LiteralPath $key
        if (!$State.HadKey -and $remaining.ValueCount -eq 0 -and $remaining.SubKeyCount -eq 0) { Remove-Item -LiteralPath $key }
    } else { Write-Host 'Other filters exist; their settings and UseFilter are retained.' }
}

try {
    if (![Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') { throw 'Use 64-bit Windows PowerShell on x64 Windows.' }
    $dir = Join-Path $env:ProgramFiles 'ClickToDoPwaRedirect'
    $exe = Join-Path $dir 'PwaRedirect.exe'
    $previous = Join-Path $dir 'PwaRedirect.previous.exe'
    $candidate = Join-Path $dir 'PwaRedirect.new.exe'
    $sourcePath = Join-Path $dir 'PwaRedirect.cs'
    $statePath = Join-Path $dir 'state.json'
    $target = Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\pwahelper.exe'
    $key = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe'
    $nativeKey = 'HKLM\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Image File Execution Options\pwahelper.exe'
    $filter = "$key\ClickToDoChromeRedirect"
    $debugger = '"' + $exe + '"'
    if ($Action -eq '7') {
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
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if (([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { throw 'Close this elevated window and run normally to test with your usual Chrome profile.' }
        Assert-OwnedFilter
        if (!(Test-Path -LiteralPath $exe) -or (Get-Item -LiteralPath $key).GetValue('UseFilter') -ne 1) { throw 'The redirect is not fully installed.' }
        Start-Process 'microsoft-edge:https://www.bing.com/search?q=Click+to+Do+default+search+test'
        Write-Host 'Check which search engine Chrome opens, then test Search the web in Click to Do.'
        Write-Host 'A successful protocol launch does not by itself prove the result is correct.'
        exit 0
    }
    Assert-Administrator
    foreach ($path in @($dir,$exe,$previous,$candidate,$sourcePath,$statePath)) { Assert-RegularPath $path }
    if ($Action -eq '2') {
        $state = Read-InstallState
        Restore-Registration $state
        Move-Item -LiteralPath $statePath -Destination (Join-Path $dir ('state.uninstalled-' + [guid]::NewGuid().ToString('N') + '.json'))
        Write-Host 'Redirect uninstalled. Original IFEO state restored where unchanged by other software.'
        Write-Host "Inactive binaries/backups remain in $dir; logs remain in LocalAppData. You may delete them manually."
        exit 0
    }
    if ($Action -eq '5') {
        $null = Read-InstallState; Assert-OwnedFilter
        if (!(Test-Path -LiteralPath $previous)) { throw 'No previous version exists. Rollback requires an earlier update.' }
        Copy-Item -LiteralPath $previous -Destination $candidate -Force
        [IO.File]::Replace($candidate,$exe,$null)
        Write-Host 'Previous program restored. Registry configuration unchanged.'
        exit 0
    }
    if (!(Test-Path -LiteralPath $target)) { throw 'pwahelper.exe not found. This Edge removal state is not supported.' }
    if (Test-Path -LiteralPath 'HKCU:\Software\Classes\microsoft-edge') { throw 'A current-user protocol override exists. Remove that experiment before installation.' }
    $chrome = @((Join-Path $env:ProgramFiles 'Google\Chrome\Application\chrome.exe'),(Join-Path ${env:ProgramFiles(x86)} 'Google\Chrome\Application\chrome.exe')) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (!$chrome) { throw 'A system-wide Chrome installation is required (Program Files).' }
    $update = Test-Path -LiteralPath $statePath
    if ($update) {
        $state = Read-InstallState; Assert-OwnedFilter
        if ((Get-Item -LiteralPath $key).GetValue('UseFilter') -ne 1 -or (Get-Item -LiteralPath $key).GetValue('Debugger')) { throw 'IFEO settings changed externally. Update stopped.' }
        if (!(Test-Path -LiteralPath $exe)) { throw 'Installed executable missing. Uninstall first, then install again.' }
    } else {
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
    Compile-Redirect $sourcePath $candidate
    if ($update) {
        if ((Get-FileHash -LiteralPath $candidate).Hash -eq (Get-FileHash -LiteralPath $exe).Hash) { Remove-Item -LiteralPath $candidate; Write-Host 'Installed program matches this build.' }
        else { [IO.File]::Replace($candidate,$exe,$previous); Write-Host 'Updated. Option 5 restores the previous program.' }
    } else {
        if ($state.HadKey) {
            $exportPath = Join-Path $dir ('ifeo-before-' + [guid]::NewGuid().ToString('N') + '.reg')
            & reg.exe export $nativeKey $exportPath /y
            if ($LASTEXITCODE -ne 0) { throw 'Registry backup failed.' }
        }
        if (Test-Path -LiteralPath $exe) { [IO.File]::Replace($candidate,$exe,$previous) }
        else { Move-Item -LiteralPath $candidate -Destination $exe }
        $state | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8
        try {
            New-Item -Path $filter -Force | Out-Null
            New-ItemProperty -LiteralPath $filter -Name FilterFullPath -Value $target -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath $filter -Name Debugger -Value $debugger -PropertyType String -Force | Out-Null
            New-ItemProperty -LiteralPath $key -Name UseFilter -Value 1 -PropertyType DWord -Force | Out-Null
            Assert-OwnedFilter
        } catch {
            $installFailure = $_
            try {
                Restore-Registration $state -AllowIncomplete
                Move-Item -LiteralPath $statePath -Destination (Join-Path $dir ('state.failed-' + [guid]::NewGuid().ToString('N') + '.json'))
            } catch { Write-Host 'Automatic registry recovery failed. Retain state.json and registry backups for manual recovery.' }
            throw $installFailure
        }
        Write-Host 'Installed successfully.'
    }
    Write-Host 'Bing web searches use the Chrome profile default search engine; normal URLs are unchanged.'
    Write-Host 'Close this elevated window. Run normally, choose 3, then test Click to Do itself.'
} catch { Write-Host ('ERROR: ' + $_.Exception.Message) -ForegroundColor Red; exit 1 }
