$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
& (Join-Path $root 'scripts\Build.ps1') -Check
$scripts = Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1'
foreach ($script in $scripts) {
    $tokens = $null; $parseErrors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($script.FullName,[ref]$tokens,[ref]$parseErrors)
    if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
}
& (Join-Path $root 'ClickToDo-Chrome-Redirect.bat') /selftest
if ($LASTEXITCODE -ne 0) { throw 'Packaged BAT self-test failed.' }
& (Join-Path $PSScriptRoot 'TestRegistry.ps1')
Write-Host 'All tests passed. The installed redirect was not modified.'
