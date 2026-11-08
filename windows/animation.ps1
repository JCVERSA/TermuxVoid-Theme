# PowerShell Void animation helpers. Existing TermuxVoid names remain compatible.
if (@('Get-TermuxVoidAnimationPaths', 'Install-TermuxVoidAnimation', 'Show-TermuxVoidAnimation', 'Enable-TermuxVoidWelcome', 'Disable-TermuxVoidWelcome', 'Set-PowerShellVoidAnimation', 'Get-PowerShellVoidAnimationSettings', 'Show-PowerShellVoidAnimation', 'Install-PowerShellVoidAnimation', 'Enable-PowerShellVoidWelcome', 'Disable-PowerShellVoidWelcome', 'Start-PowerShellVoidIdleMonitor', 'Invoke-PowerShellVoidIdle' | Where-Object {
    Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue
}).Count -gt 0) { return }

function global:Get-TermuxVoidAnimationPaths {
    $base = Join-Path $HOME '.config\TermuxVoid-Windows'
    return @{
        Base = $base
        Python = Join-Path $base 'animation-python\Scripts\python.exe'
        Node = Join-Path $base 'animation-node\node_modules\ascii.rest\dist\cli.js'
        NodeRuntime = Join-Path $base 'animation-node-runtime\node.exe'
        Settings = Join-Path $base ('animation-settings-' + $PSVersionTable.PSEdition + '.json')
        Demo = Join-Path $base ($PSVersionTable.PSEdition + '\animation-demo.py')
        Setup = Join-Path $base ($PSVersionTable.PSEdition + '\animation-setup.ps1')
    }
}

function global:Get-PowerShellVoidAnimationSettings {
    $path = (Get-TermuxVoidAnimationPaths).Settings
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return @{ Welcome = $true; Banner = $true; Idle = $true; IdleSeconds = 5 }
    }
    try {
        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($saved.Welcome -isnot [bool] -or $saved.Banner -isnot [bool] -or $saved.Idle -isnot [bool] -or
            ($saved.IdleSeconds -isnot [int] -and $saved.IdleSeconds -isnot [long]) -or $saved.IdleSeconds -lt 1 -or $saved.IdleSeconds -gt 3600) { throw 'Invalid settings' }
        return @{ Welcome = $saved.Welcome; Banner = $saved.Banner; Idle = $saved.Idle; IdleSeconds = $saved.IdleSeconds }
    } catch {
        Write-Warning "Invalid animation settings at $path; animations are disabled until the file is fixed or removed."
        return @{ Welcome = $false; Banner = $false; Idle = $false; IdleSeconds = 5 }
    }
}

function global:Set-PowerShellVoidAnimation {
    [CmdletBinding()]
    param(
        [ValidateSet('On', 'Off')][string]$Welcome,
        [ValidateSet('On', 'Off')][string]$Banner,
        [ValidateSet('On', 'Off')][string]$Idle,
        [ValidateRange(1, 3600)][int]$IdleSeconds
    )
    $settings = Get-PowerShellVoidAnimationSettings
    foreach ($key in @('Welcome', 'Banner', 'Idle')) {
        if ($PSBoundParameters.ContainsKey($key)) { $settings[$key] = $PSBoundParameters[$key] -eq 'On' }
    }
    if ($PSBoundParameters.ContainsKey('IdleSeconds')) { $settings.IdleSeconds = $IdleSeconds }
    $paths = Get-TermuxVoidAnimationPaths
    New-Item -ItemType Directory -Path $paths.Base -Force | Out-Null
    [System.IO.File]::WriteAllText($paths.Settings, ($settings | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $global:PowerShellVoidSettings = $settings
    if ($settings.Idle) { Start-PowerShellVoidIdleMonitor }
    elseif ($global:PowerShellVoidIdleSubscription) {
        $job = $global:PowerShellVoidIdleSubscription
        Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue |
            Where-Object { $_.Action.Id -eq $job.Id } |
            ForEach-Object { Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue }
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        $global:PowerShellVoidIdleSubscription = $null
    }
    Write-Host "PowerShell Void: welcome=$($settings.Welcome), banner=$($settings.Banner), idle=$($settings.Idle), delay=$($settings.IdleSeconds)s."
}

function global:Install-TermuxVoidAnimation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('TTE', 'AsciiRest', 'Asciimatics')][string]$Engine)
    $paths = Get-TermuxVoidAnimationPaths
    if (-not (Test-Path -LiteralPath $paths.Setup -PathType Leaf)) { throw 'Animation setup is missing. Rerun the PowerShell Void installer.' }
    & $paths.Setup -Base $paths.Base -Engine $Engine
}

function global:Show-TermuxVoidAnimation {
    [CmdletBinding()]
    param(
        [ValidateSet('TTE', 'AsciiRest', 'Asciimatics')][string]$Engine = 'TTE',
        [Parameter(DontShow)][Nullable[uint32]]$IdleInputTick
    )
    $paths = Get-TermuxVoidAnimationPaths
    if ([Console]::IsOutputRedirected -or [Console]::IsInputRedirected -or $env:TERM -eq 'dumb' -or $env:NO_COLOR -or $env:TERMUXVOID_NO_ANIMATION) {
        if ($null -eq $IdleInputTick) { Write-Output 'Welcome to PowerShell Void!' }
        return
    }
    $previousExitCode = $global:LASTEXITCODE
    try {
        if ($Host.UI.RawUI.WindowSize.Width -lt 50 -or $Host.UI.RawUI.WindowSize.Height -lt 10) {
            if ($null -eq $IdleInputTick) { Write-Output 'Welcome to PowerShell Void!' }
            return
        }
        switch ($Engine) {
            'TTE' {
                if (-not (Test-Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'TTE is unavailable. Rerun the installer.' }
                'Welcome to PowerShell Void!' | & $paths.Python -m terminaltexteffects --frame-rate 30 --terminal-background-color '0b0e1f' print --print-speed 8 --print-head-return-speed 8 --final-gradient-stops '16b1fb' 'ff2491'
            }
            'AsciiRest' {
                $node = if (Test-Path -LiteralPath $paths.NodeRuntime -PathType Leaf) { $paths.NodeRuntime } else { (Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue).Source }
                if (-not $node -or -not (Test-Path -LiteralPath $paths.Node -PathType Leaf)) { throw 'ascii.rest is unavailable. Rerun the installer.' }
                & $node $paths.Node banner 'PowerShell Void' --seconds 2 --color '16b1fb,ff2491'
            }
            'Asciimatics' {
                if (-not (Test-Path -LiteralPath $paths.Python -PathType Leaf)) { throw 'Asciimatics is unavailable. Rerun the installer.' }
                if ($null -ne $IdleInputTick) { & $paths.Python $paths.Demo --idle $IdleInputTick }
                else { & $paths.Python $paths.Demo }
            }
        }
        if ($LASTEXITCODE -ne 0) { throw "$Engine exited with code $LASTEXITCODE. Rerun the installer if its dependencies are missing." }
    } catch {
        if ($null -eq $IdleInputTick) { Write-Warning $_.Exception.Message; Write-Output 'Welcome to PowerShell Void!' }
        else { $global:PowerShellVoidIdleFailed = $true }
    } finally {
        [Console]::Write("$([char]27)[?25h$([char]27)[0m")
        $global:LASTEXITCODE = $previousExitCode
    }
}

function global:Show-PowerShellVoidAnimation {
    [CmdletBinding()]
    param([ValidateSet('TTE', 'AsciiRest', 'Asciimatics')][string]$Engine = 'TTE')
    Show-TermuxVoidAnimation -Engine $Engine
}
function global:Install-PowerShellVoidAnimation {
    [CmdletBinding()]
    param([Parameter(Mandatory)][ValidateSet('TTE', 'AsciiRest', 'Asciimatics')][string]$Engine)
    Install-TermuxVoidAnimation -Engine $Engine
}
function global:Enable-PowerShellVoidWelcome { Set-PowerShellVoidAnimation -Welcome On -Banner On }
function global:Disable-PowerShellVoidWelcome { Set-PowerShellVoidAnimation -Welcome Off -Banner Off }

function global:Enable-TermuxVoidWelcome { Set-PowerShellVoidAnimation -Welcome On -Banner On }
function global:Disable-TermuxVoidWelcome { Set-PowerShellVoidAnimation -Welcome Off -Banner Off }

# OnIdle is only useful when PSReadLine is waiting for an empty command line.
# Use Windows' last-input tick as a conservative additional safeguard.
function global:Invoke-PowerShellVoidIdle {
    if (-not $global:PowerShellVoidSettings.Idle -or $global:PowerShellVoidIdleFailed -or
        -not (Get-Module PSReadLine) -or $env:TERMUXVOID_NO_ANIMATION -or $env:NO_COLOR) { return }
    try {
        $line = $null; $cursor = 0
        [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
        if ($line.Length -gt 0) { $global:PowerShellVoidIdleSince = $null; return }
        $now = [System.Diagnostics.Stopwatch]::GetTimestamp()
        $frequency = [System.Diagnostics.Stopwatch]::Frequency
        if (-not $global:PowerShellVoidIdleSince -or (($now - $global:PowerShellVoidLastIdleEvent) / $frequency) -gt 1.5) {
            $global:PowerShellVoidIdleSince = $now
        }
        $global:PowerShellVoidLastIdleEvent = $now
        if ((($now - $global:PowerShellVoidIdleSince) / $frequency) -lt $global:PowerShellVoidSettings.IdleSeconds) { return }
        if ([PowerShellVoid.Input]::IdleMilliseconds() -lt ($global:PowerShellVoidSettings.IdleSeconds * 1000)) { return }
        $tick = [PowerShellVoid.Input]::LastInputTick()
        Show-TermuxVoidAnimation -Engine Asciimatics -IdleInputTick $tick
        $global:PowerShellVoidIdleSince = $null
        $global:PowerShellVoidLastIdleEvent = $null
    } catch { $global:PowerShellVoidIdleFailed = $true }
}

function global:Start-PowerShellVoidIdleMonitor {
    if ($global:PowerShellVoidIdleSubscription -or -not $env:WT_SESSION -or [Console]::IsOutputRedirected -or
        [Console]::IsInputRedirected -or $env:TERM -eq 'dumb' -or $env:NO_COLOR -or $env:TERMUXVOID_NO_ANIMATION) { return }
    try {
        if (-not ('PowerShellVoid.Input' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace PowerShellVoid {
    public static class Input {
        [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
        [DllImport("user32.dll", SetLastError=true)] static extern bool GetLastInputInfo(ref LASTINPUTINFO info);
        public static uint LastInputTick() {
            LASTINPUTINFO info = new LASTINPUTINFO();
            info.cbSize = (uint)Marshal.SizeOf(typeof(LASTINPUTINFO));
            if (!GetLastInputInfo(ref info)) throw new System.ComponentModel.Win32Exception();
            return info.dwTime;
        }
        public static uint IdleMilliseconds() { return unchecked((uint)Environment.TickCount - LastInputTick()); }
    }
}
'@
        }
        $global:PowerShellVoidIdleFailed = $false
        $global:PowerShellVoidIdleSince = $null
        $global:PowerShellVoidLastIdleEvent = $null
        $global:PowerShellVoidIdleSubscription = Register-EngineEvent -SourceIdentifier PowerShell.OnIdle -Action { Invoke-PowerShellVoidIdle }
    } catch { Write-Warning "Idle animation unavailable: $($_.Exception.Message)" }
}

$global:PowerShellVoidSettings = Get-PowerShellVoidAnimationSettings
if ($env:WT_SESSION -and -not [Console]::IsOutputRedirected -and -not [Console]::IsInputRedirected -and
    $env:TERM -ne 'dumb' -and -not $env:NO_COLOR -and -not $env:TERMUXVOID_NO_ANIMATION) {
    if ($global:PowerShellVoidSettings.Welcome) { Show-TermuxVoidAnimation -Engine TTE }
    if ($global:PowerShellVoidSettings.Banner) { Show-TermuxVoidAnimation -Engine AsciiRest }
    if ($global:PowerShellVoidSettings.Idle) { Start-PowerShellVoidIdleMonitor }
}
