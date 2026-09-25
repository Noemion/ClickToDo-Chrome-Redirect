# Generate the single-file distribution from the maintained sources. -Check is
# read-only: CI uses it to detect source edits without a regenerated BAT.
param([switch]$Check)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
# VERSION is the single source for the launcher, status output and EXE metadata.
# Use a numeric major.minor.patch version; the fourth Windows file-version field
# is always zero. Restrict components to values accepted by the C# compiler.
$version = [IO.File]::ReadAllText((Join-Path $root 'VERSION')).Trim()
if ($version -notmatch '^(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})\.(0|[1-9][0-9]{0,4})$' -or
    @($version.Split('.') | Where-Object { [int]$_ -gt 65534 }).Count) { throw 'VERSION must contain major.minor.patch with components from 0 to 65534.' }
$source = [IO.File]::ReadAllText((Join-Path $root 'src\PwaRedirect.cs'))
$attributes = @"
[assembly: System.Reflection.AssemblyVersion("$version.0")]
[assembly: System.Reflection.AssemblyFileVersion("$version.0")]
[assembly: System.Reflection.AssemblyInformationalVersion("$version")]
"@
$source = $source.Replace('// VERSION_ATTRIBUTES', $attributes.TrimEnd())
$setup = [IO.File]::ReadAllText((Join-Path $root 'src\Setup.ps1'))
# A single-quoted PowerShell here-string preserves C# quotes, backslashes and
# dollar signs literally. Its closing delimiter must be on a separate line.
$embedded = '$source = @' + "'`n" + $source.TrimEnd() + "`n'@"
$setup = $setup.Replace('# EMBED_SOURCE', $embedded)
$setup = $setup.Replace('__PROJECT_VERSION__', $version)
# Parse the combined payload, not just Setup.ps1: embedding can otherwise create
# a syntactically broken installer even when the separate files look valid.
$tokens = $null; $parseErrors = $null
[void][Management.Automation.Language.Parser]::ParseInput($setup,[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
$header = [IO.File]::ReadAllText((Join-Path $root 'scripts\Launcher.bat.in')).TrimEnd()
$header = $header.Replace('__PROJECT_VERSION__', $version)
# Normalize all inputs to Windows newlines for cmd.exe. ASCII avoids depending
# on the user's active console code page; reject characters instead of silently
# replacing them when writing. The checked-in sources must obey this constraint.
$content = (($header + "`n" + $setup.TrimEnd() + "`n") -replace '\r?\n', "`r`n")
if (@($content.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count) { throw 'BAT payload must be ASCII; use Unicode escapes in C#.' }
$output = Join-Path $root 'ClickToDo-Chrome-Redirect.bat'
if ($Check) {
    # Exact comparison covers the launcher, embedded C# and installer together.
    if (!(Test-Path -LiteralPath $output) -or [IO.File]::ReadAllText($output) -cne $content) { throw 'Generated BAT is out of date. Run scripts/Build.ps1.' }
    Write-Host 'Generated BAT matches sources.'
} else {
    [IO.File]::WriteAllText($output,$content,[Text.Encoding]::ASCII)
    Write-Host "Built $output"
}
