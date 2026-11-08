#Requires -Version 5.1
# Verify setup decisions without modifying installed modules or accessing the network.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-prediction-setup-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$script:mockModules = @()
$script:installCalls = 0
$script:failInstall = $false
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function Get-Module {
    [CmdletBinding()]
    param([switch]$ListAvailable, [string]$Name)
    if ($ListAvailable -and $Name -eq 'PSReadLine') { return $script:mockModules }
    Microsoft.PowerShell.Core\Get-Module @PSBoundParameters
}
function Install-Module {
    [CmdletBinding()]
    param([string]$Name, [string]$RequiredVersion, [string]$Scope, [string]$Repository, [switch]$AllowClobber, [switch]$Force)
    $script:installCalls++
    Assert ($Name -eq 'PSReadLine' -and $RequiredVersion -eq '2.3.6' -and $Scope -eq 'CurrentUser' -and $Repository -eq 'PSGallery') 'installs the pinned per-user module'
    if ($script:failInstall) { throw 'Simulated gallery failure' }
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
    Assert ($script:installCalls -eq 1) 'missing PSReadLine triggers install'
    $script:mockModules = @([pscustomobject]@{ Version = [version]'2.3.6' })
    & $installer @argsForTest -Update -SkipTerminalProfile
    Assert ($script:installCalls -eq 1) 'compatible PSReadLine is not upgraded'
    $script:mockModules = @()
    $script:failInstall = $true
    & $installer @argsForTest -Update -SkipTerminalProfile
    Assert ($script:installCalls -eq 2) 'failed optional dependency setup is attempted'
    Assert (Test-Path -LiteralPath (Join-Path $testRoot ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition + '\manifest.json'))) 'theme remains installed after gallery failure'
    & $installer @argsForTest -Update -SkipDependencyInstall -SkipTerminalProfile
    Assert ($script:installCalls -eq 2) 'skip dependency flag skips PSReadLine setup'
    Write-Host 'PASS: PSReadLine install, existing version, failure and skip behavior'
} finally {
    $env:PATH = $oldPath
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
