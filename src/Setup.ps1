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
$scriptVersion = '__PROJECT_VERSION__'
# EMBED_SOURCE

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
