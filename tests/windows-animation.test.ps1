#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-animation-test-' + [guid]::NewGuid().ToString('N'))
$oldDisable = $env:TERMUXVOID_NO_ANIMATION
$oldPath = $env:PATH
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $profile = Join-Path $testRoot 'Profile\profile.ps1'
    $base = Join-Path $testRoot '.config\TermuxVoid-Windows'
    $theme = Join-Path $base $PSVersionTable.PSEdition
    # An isolated dummy Starship prevents WinGet from touching the runner.
    $bin = Join-Path $testRoot 'bin'
    New-Item -ItemType Directory -Path $bin | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $bin 'starship.cmd'), "@echo off`r`nexit /b 0`r`n")
    $env:PATH = $bin + ';' + $env:PATH
    & (Join-Path $root 'windows\termuxvoid.ps1') -TestHome $testRoot -TestProfile $profile -TestRunAnimationSetup -SkipTerminalProfile
    $python = Join-Path $base 'animation-python\Scripts\python.exe'
    $nodeCli = Join-Path $base 'animation-node\node_modules\ascii.rest\dist\cli.js'
    Assert (Test-Path -LiteralPath $python) 'installer creates isolated Python environment'
    Assert (Test-Path -LiteralPath $nodeCli) 'installer installs ascii.rest'
    & $python -c 'import terminaltexteffects, asciimatics'
    Assert ($LASTEXITCODE -eq 0) 'installer installs both Python engines'
    & node.exe $nodeCli --version
    Assert ($LASTEXITCODE -eq 0) 'ascii.rest CLI starts'

    $env:TERMUXVOID_NO_ANIMATION = '1'
    $name = 'profile value'
    . (Join-Path $root 'windows\animation.ps1')
    Assert ($name -eq 'profile value') 'loading helpers preserves profile variables'
    function global:Get-TermuxVoidAnimationPaths {
        return @{
            Base = $base
            Python = $python
            Node = $nodeCli
            NodeRuntime = Join-Path $base 'animation-node-runtime\node.exe'
            Settings = Join-Path $base 'animation-settings-test.json'
            Demo = Join-Path $theme 'animation-demo.py'
            Setup = Join-Path $theme 'animation-setup.ps1'
        }
    }
    foreach ($engine in @('TTE', 'AsciiRest', 'Asciimatics')) {
        Assert ((Show-PowerShellVoidAnimation -Engine $engine) -eq 'Welcome to PowerShell Void!') 'disabled animation uses static fallback'
    }
    $settings = Get-PowerShellVoidAnimationSettings
    Assert ($settings.Welcome -and $settings.Banner -and $settings.Idle -and $settings.IdleSeconds -eq 5) 'animations enabled with five-second default'
    Set-PowerShellVoidAnimation -Welcome Off -IdleSeconds 12
    $settings = Get-PowerShellVoidAnimationSettings
    Assert (-not $settings.Welcome -and $settings.Banner -and $settings.Idle -and $settings.IdleSeconds -eq 12) 'individual settings are saved'
    Disable-PowerShellVoidWelcome
    $settings = Get-PowerShellVoidAnimationSettings
    Assert (-not $settings.Welcome -and -not $settings.Banner -and $settings.Idle) 'welcome switch controls both startup effects'
    Enable-TermuxVoidWelcome
    $settings = Get-PowerShellVoidAnimationSettings
    Assert ($settings.Welcome -and $settings.Banner) 'old welcome command remains compatible'
    Set-PowerShellVoidAnimation -Idle Off
    Assert (-not (Get-PowerShellVoidAnimationSettings).Idle) 'idle can be disabled'
    $failed = $false
    try { Set-PowerShellVoidAnimation -IdleSeconds 0 } catch { $failed = $true }
    Assert $failed 'invalid idle duration is rejected'
    & (Join-Path $root 'windows\termuxvoid.ps1') -TestHome $testRoot -TestProfile $profile -Uninstall
    Assert (Test-Path -LiteralPath $python) 'uninstall retains shared dependencies'
    Assert (Test-Path -LiteralPath (Join-Path $base 'animation-settings-test.json')) 'uninstall retains settings'
    Write-Host 'PASS: automatic animation setup and configuration'
} finally {
    $env:PATH = $oldPath
    $env:TERMUXVOID_NO_ANIMATION = $oldDisable
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
