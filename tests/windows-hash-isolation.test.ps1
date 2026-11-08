#Requires -Version 5.1
# Exercise installer ownership checks without the Utility module's Get-FileHash.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-hash-test-' + [guid]::NewGuid().ToString('N'))
function global:Get-FileHash { throw 'Installer must not depend on Get-FileHash.' }
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $installer = Join-Path $root 'windows\termuxvoid.ps1'
    $testPaths = @{ TestHome = $testRoot; TestProfile = (Join-Path $testRoot 'Profile\profile.ps1') }
    & $installer @testPaths -SkipDependencyInstall -TerminalProfile
    & $installer @testPaths -Update -SkipDependencyInstall
    & $installer @testPaths -Uninstall
    Write-Host 'PASS: installer works without Get-FileHash'
} catch {
    Write-Output "::error::$($_.Exception.Message) at $($_.ScriptStackTrace)"
    exit 1
} finally {
    Remove-Item -Path Function:\global:Get-FileHash -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
