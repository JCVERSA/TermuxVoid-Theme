#Requires -Version 5.1
# Exercise the missing-Node path without modifying machine installations.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-node-test-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
function global:Get-FileHash { throw 'Setup must not depend on Get-FileHash.' }
try {
    $env:PATH = Join-Path $env:SystemRoot 'System32'
    & (Join-Path $root 'windows\animation-setup.ps1') -Base $testRoot -Engine AsciiRest
    $node = Join-Path $testRoot 'animation-node-runtime\node.exe'
    $cli = Join-Path $testRoot 'animation-node\node_modules\ascii.rest\dist\cli.js'
    if (-not (Test-Path -LiteralPath $node) -or -not (Test-Path -LiteralPath $cli)) { throw 'Portable Node setup did not produce the runtime and CLI.' }
    & $node $cli --version
    if ($LASTEXITCODE -ne 0) { throw 'Portable Node could not run ascii.rest.' }
    Write-Host 'PASS: portable Node download, checksum and package setup'
} finally {
    $env:PATH = $oldPath
    Remove-Item -Path Function:\global:Get-FileHash -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
