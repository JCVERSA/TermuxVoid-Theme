#Requires -Version 5.1
# Verify setup decisions without modifying installed modules or accessing the network.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-prediction-setup-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$global:PVTestMockModules = @()
$global:PVTestInstallCalls = 0
$global:PVTestFailInstall = $false
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function Get-Module {
    [CmdletBinding()]
    param([switch]$ListAvailable, [string]$Name)
    if ($ListAvailable -and $Name -eq 'PSReadLine') { return $global:PVTestMockModules }
    Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
}
function Install-Module {
    [CmdletBinding()]
    param([string]$Name, [string]$RequiredVersion, [string]$Scope, [string]$Repository, [switch]$AllowClobber, [switch]$Force)
    $global:PVTestInstallCalls++
    Assert ($Name -eq 'PSReadLine' -and $RequiredVersion -eq '2.3.6' -and $Scope -eq 'CurrentUser' -and $Repository -eq 'PSGallery') 'installs the pinned per-user module'
    if ($global:PVTestFailInstall) { throw 'Simulated gallery failure' }
}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $bin = Join-Path $testRoot 'bin'
    New-Item -ItemType Directory -Path $bin | Out-Null
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'System32\cmd.exe') -Destination (Join-Path $bin 'starship.exe')
    $env:PATH = $bin + ';' + $oldPath
    $installer = Join-Path $root 'windows\termuxvoid.ps1'
    $argsForTest = @{ TestHome = $testRoot; TestProfile = (Join-Path $testRoot 'profile.ps1'); TestRunSuggestionSetup = $true }
    & $installer @argsForTest -SkipTerminalProfile
    Assert ($global:PVTestInstallCalls -eq 1) 'missing PSReadLine triggers install'
    $global:PVTestMockModules = @([pscustomobject]@{ Version = [version]'2.3.6' })
    & $installer @argsForTest -Update -SkipTerminalProfile
    Assert ($global:PVTestInstallCalls -eq 1) 'compatible PSReadLine is not upgraded'
    $global:PVTestMockModules = @()
    $global:PVTestFailInstall = $true
    & $installer @argsForTest -Update -SkipTerminalProfile
    Assert ($global:PVTestInstallCalls -eq 2) 'failed optional dependency setup is attempted'
    Assert (Test-Path -LiteralPath (Join-Path $testRoot ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition + '\manifest.json'))) 'theme remains installed after gallery failure'
    & $installer @argsForTest -Update -SkipDependencyInstall -SkipTerminalProfile
    Assert ($global:PVTestInstallCalls -eq 2) 'skip dependency flag skips PSReadLine setup'
    Write-Host 'PASS: PSReadLine install, existing version, failure and skip behavior'
} finally {
    $env:PATH = $oldPath
    Remove-Variable -Name PVTestMockModules, PVTestInstallCalls, PVTestFailInstall -Scope Global -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
