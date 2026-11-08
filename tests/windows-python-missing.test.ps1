#Requires -Version 5.1
# Simulate a missing Python runtime and a failed WinGet install without touching machine state.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-python-test-' + [guid]::NewGuid().ToString('N'))
$oldPath = $env:PATH
$oldLog = $env:POWERSHELL_VOID_TEST_LOG
try {
    $bin = Join-Path $testRoot 'bin'
    New-Item -ItemType Directory -Path $bin -Force | Out-Null
    $env:PATH = $bin + ';' + (Join-Path $env:SystemRoot 'System32')
    if ((Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue) -or (Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue)) {
        Write-Host 'SKIP: system Python visible in minimal PATH; missing-runtime simulation unsafe.'
        return
    }
    $env:POWERSHELL_VOID_TEST_LOG = Join-Path $testRoot 'winget.log'
    [System.IO.File]::WriteAllText((Join-Path $bin 'winget.cmd'), "@echo off`r`necho %* > `"%POWERSHELL_VOID_TEST_LOG%`"`r`nexit /b 12`r`n")
    $failed = $false
    try { & (Join-Path $root 'windows\animation-setup.ps1') -Base (Join-Path $testRoot 'dependencies') -Engine TTE }
    catch { $failed = $_.Exception.Message -match 'WinGet failed to install Python' }
    if (-not $failed) { throw 'Missing Python should invoke WinGet and report its failure.' }
    if (-not ((Get-Content -LiteralPath $env:POWERSHELL_VOID_TEST_LOG -Raw).Contains('Python.Python.3.12'))) { throw 'WinGet did not request Python 3.12.' }
    if (Test-Path -LiteralPath (Join-Path $testRoot 'dependencies')) { throw 'Failed runtime installation must not create an environment.' }
    Write-Host 'PASS: missing Python invokes WinGet and reports failure'
    # The mocked WinGet failed intentionally; do not propagate its native exit code.
    $global:LASTEXITCODE = 0
} finally {
    $env:PATH = $oldPath
    $env:POWERSHELL_VOID_TEST_LOG = $oldLog
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
