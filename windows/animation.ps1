# TermuxVoid optional animations. Dot-sourced from the user's managed profile.
# No package is installed or animation played unless the user opts in.
foreach ($name in @('Get-TermuxVoidAnimationPaths', 'Install-TermuxVoidAnimation', 'Show-TermuxVoidAnimation', 'Enable-TermuxVoidWelcome', 'Disable-TermuxVoidWelcome')) {
    if (Get-Command $name -CommandType Function -ErrorAction SilentlyContinue) { return }
}

function global:Get-TermuxVoidAnimationPaths {
    $base = Join-Path $HOME '.config\TermuxVoid-Windows'
    return @{
        Base = $base
        Python = Join-Path $base 'animation-python\Scripts\python.exe'
        Node = Join-Path $base 'animation-node\node_modules\ascii.rest\dist\cli.js'
        Welcome = Join-Path $base ('welcome-' + $PSVersionTable.PSEdition + '.enabled')
        Demo = Join-Path $base ($PSVersionTable.PSEdition + '\animation-demo.py')
    }
}

function global:Install-TermuxVoidAnimation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('TTE', 'AsciiRest', 'Asciimatics')][string]$Engine)
    $paths = Get-TermuxVoidAnimationPaths
    if ($Engine -eq 'AsciiRest') {
        $npm = Get-Command npm.cmd -CommandType Application -ErrorAction SilentlyContinue
        $node = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
        if (-not $npm -or -not $node) { throw 'Node.js and npm are required. Install Node.js 18.3 or newer, restart Terminal, and retry.' }
        Write-Host 'Installing ascii.rest 0.4.0 into the TermuxVoid user directory...'
        & $npm.Source install --prefix (Join-Path $paths.Base 'animation-node') --no-audit --no-fund --ignore-scripts 'ascii.rest@0.4.0'
        if ($LASTEXITCODE -ne 0) { throw 'ascii.rest installation failed.' }
    } else {
        $python = $paths.Python
        if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
            $launcher = Get-Command py.exe -CommandType Application -ErrorAction SilentlyContinue
            if ($launcher) { & $launcher.Source -3 -m venv (Join-Path $paths.Base 'animation-python') }
            else {
                $systemPython = Get-Command python.exe -CommandType Application -ErrorAction SilentlyContinue
                if (-not $systemPython) { throw 'Python 3.8 or newer is required. Install Python, restart Terminal, and retry.' }
                & $systemPython.Source -m venv (Join-Path $paths.Base 'animation-python')
            }
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $python -PathType Leaf)) { throw 'Could not create the Python environment. Check your Python installation.' }
        }
        $package = if ($Engine -eq 'TTE') { 'terminaltexteffects==0.15.0' } else { 'asciimatics==1.15.0' }
        Write-Host "Installing $package into the TermuxVoid Python environment..."
        & $python -m pip install $package
        if ($LASTEXITCODE -ne 0) { throw "Installation of $package failed." }
    }
    Write-Host "$Engine is ready. Run Show-TermuxVoidAnimation -Engine $Engine."
}

function global:Show-TermuxVoidAnimation {
    [CmdletBinding()]
    param([ValidateSet('TTE', 'AsciiRest', 'Asciimatics')][string]$Engine = 'TTE')
    $paths = Get-TermuxVoidAnimationPaths
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected -or $env:TERM -eq 'dumb' -or $env:TERMUXVOID_NO_ANIMATION) {
        Write-Output 'Welcome to TermuxVoid!'
        return
    }
    try {
        if ($Host.UI.RawUI.WindowSize.Width -lt 40 -or $Host.UI.RawUI.WindowSize.Height -lt 10) {
            Write-Output 'Welcome to TermuxVoid!'
            return
        }
        switch ($Engine) {
            'TTE' {
                if (-not (Test-Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'TTE is not installed. Run Install-TermuxVoidAnimation -Engine TTE.' }
                'Welcome to TermuxVoid!' | & $paths.Python -m terminaltexteffects --frame-rate 30 --terminal-background-color 0b0e1f print --print-speed 8 --print-head-return-speed 8 --final-gradient-stops 16b1fb ff2491
            }
            'AsciiRest' {
                $node = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue
                if (-not $node -or -not (Test-Path -LiteralPath $paths.Node -PathType Leaf)) { throw 'ascii.rest is not installed. Run Install-TermuxVoidAnimation -Engine AsciiRest.' }
                & $node.Source $paths.Node banner 'TermuxVoid' --seconds 2 --color '16b1fb,ff2491'
            }
            'Asciimatics' {
                if (-not (Test-Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'Asciimatics is not installed. Run Install-TermuxVoidAnimation -Engine Asciimatics.' }
                & $paths.Python $paths.Demo
            }
        }
        if ($LASTEXITCODE -ne 0) { throw "$Engine exited with code $LASTEXITCODE. Check that its optional package is installed." }
    } catch {
        Write-Warning $_.Exception.Message
        Write-Output 'Welcome to TermuxVoid!'
    } finally {
        # Avoid leaving the cursor hidden if an animation fails or is interrupted.
        [Console]::Write("$([char]27)[?25h$([char]27)[0m")
    }
}

function global:Enable-TermuxVoidWelcome {
    $paths = Get-TermuxVoidAnimationPaths
    if (-not (Test-Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'Install TTE first: Install-TermuxVoidAnimation -Engine TTE' }
    & $paths.Python -c 'import terminaltexteffects' 2>$null
    if ($LASTEXITCODE -ne 0) { throw 'Install TTE first: Install-TermuxVoidAnimation -Engine TTE' }
    New-Item -ItemType Directory -Path $paths.Base -Force | Out-Null
    [System.IO.File]::WriteAllText($paths.Welcome, 'enabled')
    Write-Host 'Animated welcome enabled for this PowerShell edition.'
}

function global:Disable-TermuxVoidWelcome {
    $paths = Get-TermuxVoidAnimationPaths
    if (Test-Path -LiteralPath $paths.Welcome -PathType Leaf) { Remove-Item -LiteralPath $paths.Welcome }
    Write-Host 'Animated welcome disabled for this PowerShell edition.'
}

$termuxVoidAnimationPaths = Get-TermuxVoidAnimationPaths
if ($env:WT_SESSION -and (Test-Path -LiteralPath $termuxVoidAnimationPaths.Welcome -PathType Leaf) -and
    -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected -and
    $env:TERM -ne 'dumb' -and -not $env:TERMUXVOID_NO_ANIMATION) {
    Show-TermuxVoidAnimation -Engine TTE
}
Remove-Variable termuxVoidAnimationPaths -ErrorAction SilentlyContinue
