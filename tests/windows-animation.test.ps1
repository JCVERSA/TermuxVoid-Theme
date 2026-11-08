#Requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TermuxVoid-animation-test-' + [guid]::NewGuid().ToString('N'))
$oldDisable = $env:TERMUXVOID_NO_ANIMATION
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $name = 'profile value'
    . (Join-Path $root 'windows\animation.ps1')
    Assert ($name -eq 'profile value') 'loading helpers preserves profile variables'
    # Prevent the test from touching real user data; the helper resolves paths dynamically.
    function global:Get-TermuxVoidAnimationPaths {
        return @{
            Base = $testRoot
            Python = Join-Path $testRoot 'animation-python\Scripts\python.exe'
            Node = Join-Path $testRoot 'animation-node\node_modules\ascii.rest\dist\cli.js'
            Welcome = Join-Path $testRoot 'welcome.enabled'
            Demo = Join-Path $root 'windows\animation-demo.py'
        }
    }
    $env:TERMUXVOID_NO_ANIMATION = '1'
    foreach ($engine in @('TTE', 'AsciiRest', 'Asciimatics')) {
        Assert ((Show-TermuxVoidAnimation -Engine $engine) -eq 'Welcome to TermuxVoid!') 'disabled animation uses static fallback'
    }
    $failed = $false
    try { Enable-TermuxVoidWelcome } catch { $failed = $true }
    Assert $failed 'welcome cannot be enabled without TTE'
    Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot 'welcome.enabled'))) 'failed enable does not create preference'
    # Real packages are installed only inside this disposable test directory.
    Install-TermuxVoidAnimation -Engine TTE
    Enable-TermuxVoidWelcome
    Assert (Test-Path -LiteralPath (Join-Path $testRoot 'welcome.enabled')) 'enable creates preference'
    Disable-TermuxVoidWelcome
    Assert (-not (Test-Path -LiteralPath (Join-Path $testRoot 'welcome.enabled'))) 'disable removes preference'
    Install-TermuxVoidAnimation -Engine Asciimatics
    $paths = Get-TermuxVoidAnimationPaths
    & $paths.Python -c 'import terminaltexteffects, asciimatics'
    Assert ($LASTEXITCODE -eq 0) 'both Python engines import from isolated environment'
    Install-TermuxVoidAnimation -Engine AsciiRest
    Assert (Test-Path -LiteralPath $paths.Node) 'ascii.rest installed in isolated directory'
    & node.exe $paths.Node --version
    Assert ($LASTEXITCODE -eq 0) 'ascii.rest CLI starts'
    Write-Host 'PASS: Animation helpers and dependency setup'
} finally {
    $env:TERMUXVOID_NO_ANIMATION = $oldDisable
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
