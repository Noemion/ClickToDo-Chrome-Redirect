param([switch]$Check)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = [IO.File]::ReadAllText((Join-Path $root 'src\PwaRedirect.cs'))
$setup = [IO.File]::ReadAllText((Join-Path $root 'src\Setup.ps1'))
$embedded = '$source = @' + "'`n" + $source.TrimEnd() + "`n'@"
$setup = $setup.Replace('# EMBED_SOURCE', $embedded)
$tokens = $null; $parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($setup,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$header = [IO.File]::ReadAllText((Join-Path $root 'scripts\Launcher.bat.in')).TrimEnd()
$content = (($header + "`n" + $setup.TrimEnd() + "`n") -replace '\r?\n', "`r`n")
if (@($content.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count) { throw 'BAT payload must be ASCII; use Unicode escapes in C#.' }
$output = Join-Path $root 'ClickToDo-Chrome-Redirect.bat'
if ($Check) {
    if (!(Test-Path -LiteralPath $output) -or [IO.File]::ReadAllText($output) -cne $content) { throw 'Generated BAT is out of date. Run scripts/Build.ps1.' }
    Write-Host 'Generated BAT matches sources.'
} else {
    [IO.File]::WriteAllText($output,$content,[Text.Encoding]::ASCII)
    Write-Host "Built $output"
}
