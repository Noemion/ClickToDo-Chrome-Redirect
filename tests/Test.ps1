# Run the repository's checks without changing the real installed redirect.
# Order matters: reject a stale distribution before exercising its embedded code.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'scripts\Build.ps1') -Check
# Query the built BAT as a user would; this mode must not require installation.
$expectedVersion = [IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
$versionOutput = & (Join-Path $root 'ClickToDo-Chrome-Redirect.bat') /version
if ($LASTEXITCODE -ne 0 -or ($versionOutput -join "`n").Trim() -cne "ClickToDo Chrome Redirect v$expectedVersion") { throw 'BAT version display does not match VERSION.' }
# Parse every maintained PowerShell file, including tests, without running each
# file as an installer. Report all parser diagnostics for the first failing file.
$scripts = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1'
foreach ($script in $scripts) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
# Test the actual user-facing BAT launcher and embedded C#, not only standalone
# source files. The child process must report failures through its exit code.
& (Join-Path $root 'ClickToDo-Chrome-Redirect.bat') /selftest
if ($LASTEXITCODE -ne 0) { throw 'Packaged BAT self-test failed.' }
# Registry recovery uses a temporary HKCU fixture and removes it afterward.
& (Join-Path $PSScriptRoot 'TestRegistry.ps1')
Write-Host 'All tests passed. The installed redirect was not modified.'
