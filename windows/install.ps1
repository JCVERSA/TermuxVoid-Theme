#Requires -Version 5.1
<#
.SYNOPSIS
Downloads the Windows theme installer and runs a fresh install or guarded update.
#>
[CmdletBinding()]
param(
    [switch]$SkipDependencyInstall,
    [switch]$TerminalProfile,
    [switch]$SkipTerminalProfile,
    # These paths are for isolated integration tests only.
    [Parameter(DontShow)] [string]$TestHome,
    [Parameter(DontShow)] [string]$TestProfile
)

$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'Run this installer in PowerShell on Windows.' }
if ([bool]$TestHome -ne [bool]$TestProfile) { throw 'Both test paths must be provided together.' }

# This branch is the current release source. Change to main when merged.
$baseUrl = 'https://raw.githubusercontent.com/JCVERSA/TermuxVoid-Theme/arena/d693b190-termuxvoid-theme/windows'
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ('TermuxVoid-install-' + [guid]::NewGuid().ToString('N'))
$homeDir = if ($TestHome) { $TestHome } else { $HOME }
$themeDir = Join-Path (Join-Path $homeDir '.config\TermuxVoid-Windows') $PSVersionTable.PSEdition
try {
    New-Item -ItemType Directory -Path $tempDir | Out-Null
    foreach ($file in @('termuxvoid.ps1', 'starship.toml', 'termuxvoid-scheme.json', 'animation.ps1', 'animation-demo.py', 'animation-setup.ps1')) {
        Invoke-WebRequest -UseBasicParsing -Uri "$baseUrl/$file" -OutFile (Join-Path $tempDir $file)
    }
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $tempDir 'termuxvoid.ps1'))
    if (Test-Path -LiteralPath $themeDir) { $arguments += '-Update' }
    if ($SkipDependencyInstall) { $arguments += '-SkipDependencyInstall' }
    if ($TerminalProfile) { $arguments += '-TerminalProfile' }
    if ($SkipTerminalProfile) { $arguments += '-SkipTerminalProfile' }
    if ($TestHome) { $arguments += @('-TestHome', $TestHome, '-TestProfile', $TestProfile) }
    $exe = (Get-Process -Id $PID).Path
    if (-not $exe) { throw 'Cannot find the current PowerShell executable.' }
    & $exe @arguments
    if ($LASTEXITCODE -ne 0) { throw "TermuxVoid setup failed (exit code $LASTEXITCODE)." }
} finally {
    if (Test-Path -LiteralPath $tempDir) { Remove-Item -LiteralPath $tempDir -Recurse -Force }
}
