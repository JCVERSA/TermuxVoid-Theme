#Requires -Version 5.1
# Exercises the short-command bootstrap with local fixtures, not the network.
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'These integration tests require Windows.' }
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TermuxVoid-bootstrap-test-' + [guid]::NewGuid().ToString('N'))
$oldTemp = $env:TEMP
$oldTmp = $env:TMP
$script:failDownload = $false
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
# The scriptblock sees these functions in its parent scope. No remote code is used.
function Invoke-RestMethod([string]$Uri) {
    return [System.IO.File]::ReadAllText((Join-Path $root 'windows\install.ps1'))
}
function Invoke-WebRequest([string]$Uri, [string]$OutFile, [switch]$UseBasicParsing) {
    $name = $Uri.Substring($Uri.LastIndexOf('/') + 1)
    if ($script:failDownload -and $name -eq 'starship.toml') { throw 'Simulated download failure' }
    if ($name -notin @('termuxvoid.ps1', 'starship.toml', 'termuxvoid-scheme.json', 'animation.ps1', 'animation-demo.py')) { throw "Unexpected download: $Uri" }
    Copy-Item -LiteralPath (Join-Path $root "windows\$name") -Destination $OutFile
}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $temp = Join-Path $testRoot 'temp'
    New-Item -ItemType Directory -Path $temp | Out-Null
    $env:TEMP = $temp
    $env:TMP = $temp
    $profilePath = Join-Path $testRoot 'Profile With Spaces\Microsoft.PowerShell_profile.ps1'
    $themeDir = Join-Path $testRoot ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition)
    $testArgs = @{ TestHome = $testRoot; TestProfile = $profilePath; SkipDependencyInstall = $true; TerminalProfile = $true }

    $script:failDownload = $true
    $failed = $false
    try { & ([scriptblock]::Create((irm 'mock-install'))) @testArgs } catch { $failed = $true }
    Assert $failed 'failed download must stop install'
    Assert (-not (Test-Path -LiteralPath $themeDir)) 'failed download must not install theme'
    Assert ((Get-ChildItem -LiteralPath $temp -Force | Measure-Object).Count -eq 0) 'temporary download files removed on error'

    $script:failDownload = $false
    & ([scriptblock]::Create((irm 'mock-install'))) @testArgs
    Assert (Test-Path -LiteralPath (Join-Path $themeDir 'manifest.json')) 'short command installs theme'
    $fragment = Join-Path $testRoot ('LocalAppData\Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme\' + $PSVersionTable.PSEdition + '.json')
    Assert (Test-Path -LiteralPath $fragment) 'short command installs optional Terminal profile'
    [byte[]]$originalProfile = [System.IO.File]::ReadAllBytes($profilePath)
    & ([scriptblock]::Create((irm 'mock-install'))) @testArgs
    Assert ([Convert]::ToBase64String($originalProfile) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($profilePath))) 'second invocation updates without duplicating profile block'
    $config = Join-Path $themeDir 'starship.toml'
    Add-Content -LiteralPath $config -Value '# local edit'
    $failed = $false
    try { & ([scriptblock]::Create((irm 'mock-install'))) @testArgs } catch { $failed = $true }
    Assert $failed 'update must refuse a modified config'
    Assert ((Get-Content -LiteralPath $config -Raw).Contains('# local edit')) 'update preserves user edits'
    Assert ((Get-ChildItem -LiteralPath $temp -Force | Measure-Object).Count -eq 0) 'temporary download files removed after update'
    Write-Host 'PASS: Windows short-command bootstrap'
    # The deliberately failed child process above must not fail the test runner.
    $global:LASTEXITCODE = 0
} finally {
    $env:TEMP = $oldTemp
    $env:TMP = $oldTmp
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
