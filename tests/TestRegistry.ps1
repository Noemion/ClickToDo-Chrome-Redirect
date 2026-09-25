# Exercise recovery against a private HKCU fixture, never the real IFEO key.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src\Setup.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
foreach ($name in @('Assert-OwnedFilter','Restore-Registration')) {
    $definition = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if (!$definition) { throw "Missing function $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}
$fixture = 'HKCU:\Software\ClickToDoRedirectTest-' + [guid]::NewGuid().ToString('N')
$key = "$fixture\helper"
$filter = "$key\ClickToDoChromeRedirect"
$target = 'C:\test-only\helper.exe'
$debugger = '"C:\test-only\redirect.exe"'
function Seed-Filter {
    New-Item -Path $filter -Force | Out-Null
    New-ItemProperty -LiteralPath $filter -Name FilterFullPath -Value $target -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $filter -Name Debugger -Value $debugger -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name UseFilter -Value 1 -PropertyType DWord -Force | Out-Null
}
try {
    Seed-Filter
    Restore-Registration ([pscustomobject]@{HadKey=$false;HadUseFilter=$false;UseFilter=0})
    if (Test-Path -LiteralPath $key) { throw 'Fresh-install recovery left a key.' }

    Seed-Filter
    New-ItemProperty -LiteralPath $key -Name UnrelatedSetting -Value 'keep' | Out-Null
    Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$true;UseFilter=0})
    if ((Get-Item $key).GetValue('UseFilter') -ne 0 -or (Get-Item $key).GetValue('UnrelatedSetting') -ne 'keep') { throw 'Original registry settings were not preserved.' }

    Seed-Filter
    New-Item -Path "$key\OtherFilter" | Out-Null
    Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$false;UseFilter=0})
    if (!(Test-Path "$key\OtherFilter") -or (Get-Item $key).GetValue('UseFilter') -ne 1) { throw 'Another filter was disrupted.' }
    Remove-Item -LiteralPath "$key\OtherFilter"

    Seed-Filter
    Set-ItemProperty -LiteralPath $filter -Name Debugger -Value 'external.exe'
    $blocked = $false
    try { Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$false;UseFilter=0}) } catch { $blocked=$true }
    if (!$blocked -or !(Test-Path $filter)) { throw 'Externally modified filter was not protected.' }
    Set-ItemProperty -LiteralPath $filter -Name Debugger -Value $debugger

    Remove-ItemProperty -LiteralPath $filter -Name Debugger
    Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$false;UseFilter=0}) -AllowIncomplete
    if ((Test-Path $filter) -or $null -ne (Get-Item $key).GetValue('UseFilter')) { throw 'Partial-install recovery failed.' }
    Write-Host 'Five registry recovery tests passed using a private HKCU fixture.'
} finally {
    if ($fixture -notmatch '^HKCU:\\Software\\ClickToDoRedirectTest-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup path.' }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
