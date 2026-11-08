#Requires -Version 5.1
# Install animation dependencies into a shared per-user directory. Python itself,
# when missing, is installed with WinGet; Node is a hash-verified portable archive.
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Base,
    [ValidateSet('All', 'TTE', 'AsciiRest', 'Asciimatics')][string]$Engine = 'All'
)
$ErrorActionPreference = 'Stop'
$python = Join-Path $Base 'animation-python\Scripts\python.exe'
if ($Engine -ne 'AsciiRest') {
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        $launcher = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue
        $systemPython = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue
        $pythonPath = $null
        $pythonArgs = @()
        if ($launcher) {
            & $launcher.Source -3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>$null
            if ($LASTEXITCODE -eq 0) { $pythonPath = $launcher.Source; $pythonArgs = @('-3') }
        }
        if (-not $pythonPath -and $systemPython -and $systemPython.Source -notmatch '\\WindowsApps\\') {
            & $systemPython.Source -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>$null
            if ($LASTEXITCODE -eq 0) { $pythonPath = $systemPython.Source }
        }
        if (-not $pythonPath) {
            $winget = Get-Command winget.exe -CommandType Application -ErrorAction SilentlyContinue
            if (-not $winget) { $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue }
            if (-not $winget) { throw 'Python 3.8+ is missing and WinGet is unavailable. Install Python and retry setup.' }
            Write-Host 'Python is missing: installing Python 3.12 for the current user with WinGet (package agreements are accepted).'
            & $winget.Source install --id Python.Python.3.12 --exact --source winget --scope user --accept-package-agreements --accept-source-agreements --disable-interactivity
            if ($LASTEXITCODE -ne 0) { throw "WinGet failed to install Python (exit $LASTEXITCODE). Install Python 3.8+ and retry." }
            if ($env:LOCALAPPDATA) {
                foreach ($directory in @('Python312', 'Python312-arm64', 'Python312-32')) {
                    $candidate = Join-Path $env:LOCALAPPDATA ("Programs\Python\$directory\python.exe")
                    if (Test-Path -LiteralPath $candidate -PathType Leaf) { $pythonPath = $candidate; break }
                }
            }
            if (-not $pythonPath -and $launcher) {
                & $launcher.Source -3.12 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)' 2>$null
                if ($LASTEXITCODE -eq 0) { $pythonPath = $launcher.Source; $pythonArgs = @('-3.12') }
            }
            if (-not $pythonPath) { throw 'Python was installed but could not be located. Restart PowerShell and rerun setup.' }
        }
        if (Test-Path -LiteralPath (Join-Path $Base 'animation-python')) {
            throw 'An incomplete animation-python directory already exists. Inspect it before removing it and retrying.'
        }
        & $pythonPath @pythonArgs -m venv (Join-Path $Base 'animation-python')
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Could not create the isolated Python environment.' }
    }
    $packages = @()
    if ($Engine -in @('All', 'TTE')) { $packages += 'terminaltexteffects==0.15.0' }
    if ($Engine -in @('All', 'Asciimatics')) { $packages += 'asciimatics==1.15.0' }
    Write-Host "Installing $($packages -join ', ') into the PowerShell Void Python environment..."
    & $python -m pip install @packages
    if ($LASTEXITCODE -ne 0) { throw "Python animation dependency installation failed (exit $LASTEXITCODE)." }
}
if ($Engine -in @('All', 'AsciiRest')) {
    $nodeDir = Join-Path $Base 'animation-node-runtime'
    $node = Join-Path $nodeDir 'node.exe'
    $npm = Join-Path $nodeDir 'npm.cmd'
    if (-not (Test-Path -LiteralPath $node -PathType Leaf) -or -not (Test-Path -LiteralPath $npm -PathType Leaf)) {
        $systemNode = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
        $systemNpm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue
        if ($systemNode -and $systemNpm) {
            $node = $systemNode.Source
            $npm = $systemNpm.Source
            $version = & $node -p 'process.versions.node'
            if ($LASTEXITCODE -ne 0 -or [version]$version -lt [version]'18.3.0') { throw 'The installed Node.js is too old; Node.js 18.3+ is required.' }
        } else {
            if (Test-Path -LiteralPath $nodeDir) { throw "Incomplete Node runtime already exists: $nodeDir. Inspect it before removing it and retrying." }
            $architecture = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
            if ($architecture -eq 'ARM64') { $arch = 'arm64'; $hash = 'A0C807319FEDE24C4A0D8F84564C82A619BD313B16B10C007C383C2609E99171' }
            elseif ($architecture -eq 'AMD64') { $arch = 'x64'; $hash = 'D2046D28C2C3DCD211AC5145C0BF30E2047EF9DFB306693C8C6E2ECCD8B95FA5' }
            else { throw "No automatic Node runtime is available for $architecture. Install Node.js 18.3+ and retry." }
            $temp = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-node-' + [guid]::NewGuid().ToString('N'))
            try {
                New-Item -ItemType Directory -Path $temp -Force | Out-Null
                $zip = Join-Path $temp 'node.zip'
                Write-Host "Downloading Node.js 24.22.1 ($arch) into the user directory..."
                Invoke-WebRequest -UseBasicParsing -Uri "https://nodejs.org/dist/v24.22.1/node-v24.22.1-win-$arch.zip" -OutFile $zip
                if ((Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash -ne $hash) { throw 'Node archive checksum mismatch.' }
                Expand-Archive -LiteralPath $zip -DestinationPath $temp
                New-Item -ItemType Directory -Path $Base -Force | Out-Null
                Move-Item -LiteralPath (Join-Path $temp "node-v24.22.1-win-$arch") -Destination $nodeDir
            } finally { if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Recurse -Force } }
        }
    }
    # npm.cmd resolves node.exe from PATH. Limit the change to this process.
    $oldPath = $env:PATH
    try {
        $env:PATH = (Split-Path -Parent $node) + ';' + $env:PATH
        Write-Host 'Installing ascii.rest 0.4.0 into the PowerShell Void user directory...'
        & $npm install --prefix (Join-Path $Base 'animation-node') --no-audit --no-fund --ignore-scripts 'ascii.rest@0.4.0'
        if ($LASTEXITCODE -ne 0) { throw "ascii.rest installation failed (exit $LASTEXITCODE)." }
    } finally { $env:PATH = $oldPath }
}
Write-Host 'PowerShell Void animation dependencies are ready.'
