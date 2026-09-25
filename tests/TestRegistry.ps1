# Exercise recovery against a private HKCU fixture, never the real IFEO key.
# This test checks recovery invariants without requiring administrator rights or
# installing the forwarder. It does not claim to test Windows process interception.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$tokens = $null; $parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'src\Setup.ps1'),[ref]$tokens,[ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
# Extract just the production function definitions from the syntax tree. Dot-
# sourcing all of Setup.ps1 would run its dispatcher and inspect real setup state.
# Calling these exact functions also avoids testing a copied recovery algorithm.
foreach ($name in @('Assert-OwnedFilter','Restore-Registration')) {
    $definition = $ast.Find({param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $name},$true)
    if (!$definition) { throw "Missing function $name" }
    . ([scriptblock]::Create($definition.Extent.Text))
}
# The imported functions resolve these variables from the test's script scope.
# Every registry operation is redirected into this unique, disposable HKCU root;
# executable paths below are inert strings and are never launched.
$fixture = 'HKCU:\Software\ClickToDoRedirectTest-' + [guid]::NewGuid().ToString('N')
$key = "$fixture\helper"
$filter = "$key\ClickToDoChromeRedirect"
$target = 'C:\test-only\helper.exe'
$debugger = '"C:\test-only\redirect.exe"'
# Recreate the expected enabled filter for each scenario. Parent values from a
# prior scenario may deliberately remain so preservation behavior is exercised.
function Seed-Filter {
    New-Item -Path $filter -Force | Out-Null
    New-ItemProperty -LiteralPath $filter -Name FilterFullPath -Value $target -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $filter -Name Debugger -Value $debugger -PropertyType String -Force | Out-Null
    New-ItemProperty -LiteralPath $key -Name UseFilter -Value 1 -PropertyType DWord -Force | Out-Null
}
try {
    # Case 1: the installer created an otherwise empty parent; remove it entirely.
    Seed-Filter
    Restore-Registration ([pscustomobject]@{HadKey=$false;HadUseFilter=$false;UseFilter=0})
    if (Test-Path -LiteralPath $key) { throw 'Fresh-install recovery left a key.' }

    # Case 2: the parent and UseFilter=0 predated setup. Restore that exact value
    # while retaining unrelated settings instead of replacing the entire key.
    Seed-Filter
    New-ItemProperty -LiteralPath $key -Name UnrelatedSetting -Value 'keep' | Out-Null
    Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$true;UseFilter=0})
    if ((Get-Item $key).GetValue('UseFilter') -ne 0 -or (Get-Item $key).GetValue('UnrelatedSetting') -ne 'keep') { throw 'Original registry settings were not preserved.' }

    # Case 3: another child filter now relies on UseFilter=1. Removing our child
    # must not disable that other filter, even if UseFilter was originally absent.
    Seed-Filter
    New-Item -Path "$key\OtherFilter" | Out-Null
    Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$false;UseFilter=0})
    if (!(Test-Path "$key\OtherFilter") -or (Get-Item $key).GetValue('UseFilter') -ne 1) { throw 'Another filter was disrupted.' }
    Remove-Item -LiteralPath "$key\OtherFilter"

    # Case 4: a familiar subkey name no longer proves ownership after another
    # program changes its debugger. Recovery must fail without deleting the key.
    Seed-Filter
    Set-ItemProperty -LiteralPath $filter -Name Debugger -Value 'external.exe'
    $blocked = $false
    try { Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$false;UseFilter=0}) } catch { $blocked=$true }
    if (!$blocked -or !(Test-Path $filter)) { throw 'Externally modified filter was not protected.' }
    Set-ItemProperty -LiteralPath $filter -Name Debugger -Value $debugger

    # Case 5: simulate setup failure before all child values were written. The
    # explicitly allowed incomplete form can be removed and the absent original
    # UseFilter restored; this tolerance is not used for ordinary uninstall.
    Remove-ItemProperty -LiteralPath $filter -Name Debugger
    Restore-Registration ([pscustomobject]@{HadKey=$true;HadUseFilter=$false;UseFilter=0}) -AllowIncomplete
    if ((Test-Path $filter) -or $null -ne (Get-Item $key).GetValue('UseFilter')) { throw 'Partial-install recovery failed.' }
    Write-Host 'Five registry recovery tests passed using a private HKCU fixture.'
} finally {
    # Cleanup runs on assertion failure too. Validate the narrow generated root
    # before recursive removal so a variable mistake cannot target a broader key.
    if ($fixture -notmatch '^HKCU:\\Software\\ClickToDoRedirectTest-[a-f0-9]{32}$') { throw 'Unexpected fixture cleanup path.' }
    if (Test-Path -LiteralPath $fixture) { Remove-Item -LiteralPath $fixture -Recurse -Force }
}
