#Requires -Version 7
param([Parameter(Mandatory)][string]$Starship)
$ErrorActionPreference = 'Stop'
$repo = Join-Path ([System.IO.Path]::GetTempPath()) ('TermuxVoid-render-' + [guid]::NewGuid().ToString('N'))
$oldConfig = $env:STARSHIP_CONFIG
try {
    New-Item -ItemType Directory -Path $repo | Out-Null
    & git init --quiet $repo
    if ($LASTEXITCODE -ne 0) { throw 'git init failed' }
    & git -C $repo symbolic-ref HEAD refs/heads/termuxvoid-test
    if ($LASTEXITCODE -ne 0) { throw 'git symbolic-ref failed' }
    [System.IO.File]::WriteAllText((Join-Path $repo 'package.json'), '{"name":"test-project","version":"2.3.4"}')
    $env:STARSHIP_CONFIG = (Resolve-Path (Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\starship.toml')).Path
    Push-Location $repo
    try {
        $success = & $Starship prompt '--status=0' '--jobs=0' '--terminal-width=120' | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Starship failed to render success prompt' }
        $failure = & $Starship prompt '--status=1' '--jobs=1' '--cmd-duration=3400' '--terminal-width=120' | Out-String
        if ($LASTEXITCODE -ne 0) { throw 'Starship failed to render failure prompt' }
        if (-not $success.Contains($env:USERNAME)) { throw "Username missing from prompt; expected $env:USERNAME; got: $($success -replace '[\x1b\r\n]', ' ')" }
        if (-not $success.Contains('termuxvoid-test')) { throw 'Git branch missing from prompt' }
        if (-not $success.Contains('pkg 2.3.4')) { throw 'Package version missing from prompt' }
        if (-not $success.Contains('Node ')) { throw 'Node project context missing from prompt' }
        if ($success -notmatch '\d{2}:\d{2}:\d{2}') { throw 'Time missing from prompt' }
        if (-not $success.Contains([char]0x2705)) { throw 'Success icon missing' }
        if (-not $failure.Contains([char]0x274c)) { throw 'Failure icon missing' }
        if (-not $failure.Contains([char]0x23f3)) { throw 'Running jobs icon missing' }
        if (-not $failure.Contains('took')) { throw 'Command duration missing' }
    } finally { Pop-Location }
    Write-Host 'PASS: Starship prompt rendering'
} finally {
    $env:STARSHIP_CONFIG = $oldConfig
    if (Test-Path -LiteralPath $repo) { Remove-Item -LiteralPath $repo -Recurse -Force }
}
