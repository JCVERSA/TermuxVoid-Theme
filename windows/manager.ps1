# PowerShell Void manager. Installer-owned templates remain unchanged.
# Functions use a distinct namespace to avoid interfering with the user's profile.
if (@('Invoke-PowerShellVoidManager', 'Get-PVPaths', 'Get-PVManifest', 'Get-PVFileHash', 'Assert-PVOwnedFile', 'Backup-PVFiles', 'Read-PVChoice', 'Read-PVText', 'Get-PVPromptState', 'Set-PVPromptState', 'Get-PVAnimationState', 'Set-PVAnimationState', 'Get-PVColorNames', 'Get-PVPalette', 'Get-PVUpdatedPalette', 'Get-PVContrast', 'Show-PVChoiceStatus', 'Format-PVValues', 'Confirm-PVMixedChange', 'Confirm-PVPalette', 'Set-PVPalette', 'Get-PVSuggestionState', 'Set-PVSuggestionState', 'Apply-PVSuggestions', 'Show-PVSuggestions', 'Get-PVTargets', 'Show-PVAnimations', 'Show-PVPrompt', 'Show-PVColors', 'Show-PVMaintenance', 'Start-PVShortcut' | Where-Object {
    Get-Command $_ -ErrorAction SilentlyContinue
}).Count -gt 0) { return }

function global:Get-PVPaths([string]$Edition) {
    $base = Join-Path $HOME '.config\TermuxVoid-Windows'
    $theme = Join-Path $base $Edition
    $fragment = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA ("Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme\$Edition.json") } else { $null }
    return @{ Base = $base; Theme = $theme; Manifest = (Join-Path $theme 'manifest.json');
        Prompt = (Join-Path $base "prompt-$Edition.toml"); PromptSettings = (Join-Path $base "prompt-settings-$Edition.json");
        AnimationSettings = (Join-Path $base "animation-settings-$Edition.json"); SuggestionSettings = (Join-Path $base "suggestion-settings-$Edition.json"); Fragment = $fragment }
}

function global:Get-PVManifest([string]$Edition) {
    $paths = Get-PVPaths $Edition
    if (-not (Test-Path -LiteralPath $paths.Manifest -PathType Leaf)) { throw "No $Edition installation found." }
    try { $manifest = Get-Content -LiteralPath $paths.Manifest -Raw | ConvertFrom-Json } catch { throw "Invalid manifest: $($paths.Manifest)" }
    if (-not $manifest.profilePath -or -not $manifest.hashes) { throw "Invalid manifest: $($paths.Manifest)" }
    return $manifest
}

function global:Get-PVFileHash([string]$Path) {
    $algorithm = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '')
    } finally {
        if ($stream) { $stream.Dispose() }
        $algorithm.Dispose()
    }
}

function global:Assert-PVOwnedFile($Manifest, [string]$Path, [string]$Name) {
    $expected = $Manifest.hashes.$Name
    if (-not $expected -or -not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-PVFileHash $Path) -ne $expected) {
        throw "Managed file is missing or modified: $Path. No changes made. Back up your changes, then restore the matching installed file or see Windows README > Update an existing Windows installation."
    }
}

function global:Get-PVPromptState([string]$Edition) {
    $paths = Get-PVPaths $Edition
    $defaults = @{ Username = $true; Directory = $true; Git = $true; Languages = $true; Duration = $true; Time = $true; Jobs = $true; Status = $true; DirectoryColor = '#87FF00'; PromptHash = ''; SourceHash = '' }
    if (-not (Test-Path -LiteralPath $paths.PromptSettings)) {
        if (Test-Path -LiteralPath $paths.Prompt) { throw "Unowned prompt file exists: $($paths.Prompt). It was not changed." }
        return $defaults
    }
    try { $saved = Get-Content -LiteralPath $paths.PromptSettings -Raw | ConvertFrom-Json } catch { throw "Invalid prompt settings: $($paths.PromptSettings)" }
    foreach ($key in @('Username', 'Directory', 'Git', 'Languages', 'Duration', 'Time', 'Jobs', 'Status')) {
        if ($saved.$key -isnot [bool]) { throw "Invalid $key in $($paths.PromptSettings)" }
        $defaults[$key] = $saved.$key
    }
    if ($saved.DirectoryColor -notmatch '^#[0-9a-fA-F]{6}$' -or $saved.PromptHash -notmatch '^[0-9A-Fa-f]{64}$' -or $saved.SourceHash -notmatch '^[0-9A-Fa-f]{64}$') {
        throw "Invalid prompt settings: $($paths.PromptSettings)"
    }
    if (-not (Test-Path -LiteralPath $paths.Prompt -PathType Leaf) -or (Get-PVFileHash $paths.Prompt) -ne $saved.PromptHash) {
        throw "Custom prompt is missing or has been edited: $($paths.Prompt). No changes made. Back up the prompt and its settings, then restore the matching pair or move both aside to reset the menu settings."
    }
    $defaults.DirectoryColor = $saved.DirectoryColor
    $defaults.PromptHash = $saved.PromptHash
    $defaults.SourceHash = $saved.SourceHash
    return $defaults
}

function global:Backup-PVFiles([string]$Base, [string[]]$Files) {
    $existing = @($Files | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($existing.Count -eq 0) { return }
    $backup = Join-Path $Base ('backups\manager-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    $i = 0
    foreach ($file in $existing) { Copy-Item -LiteralPath $file -Destination (Join-Path $backup ("{0}-{1}" -f $i, (Split-Path -Leaf $file))); $i++ }
    Write-Host "Backup: $backup"
}

function global:Set-PVPromptState([string[]]$Editions, [string]$Key, $Value) {
    $allowed = @('Username', 'Directory', 'Git', 'Languages', 'Duration', 'Time', 'Jobs', 'Status')
    if ($Key -notin $allowed -and $Key -ne 'DirectoryColor' -and $Key -ne 'Reapply') { throw 'Unknown prompt setting.' }
    if ($Key -in $allowed -and $Value -isnot [bool]) { throw 'Prompt switches must be boolean.' }
    if ($Key -eq 'DirectoryColor' -and $Value -notmatch '^#[0-9a-fA-F]{6}$') { throw 'Use a color such as #87FF00.' }
    $plans = @()
    foreach ($edition in $Editions) {
        $paths = Get-PVPaths $edition
        $manifest = Get-PVManifest $edition
        Assert-PVOwnedFile $manifest (Join-Path $paths.Theme 'manager.ps1') 'manager.ps1'
        $template = Join-Path $paths.Theme 'starship.toml'
        Assert-PVOwnedFile $manifest $template 'starship.toml'
        $state = Get-PVPromptState $edition
        if ($Key -ne 'Reapply') { $state[$Key] = $Value }
        $toml = [System.IO.File]::ReadAllText($template, [System.Text.Encoding]::UTF8)
        $start = $toml.IndexOf('format = """')
        $end = if ($start -ge 0) { $toml.IndexOf('"""', $start + 12) } else { -1 }
        if ($start -lt 0 -or $end -lt 0 -or -not $toml.Contains('bold #87FF00')) { throw "Unrecognized prompt template for $edition; no changes made." }
        $format = $toml.Substring($start, $end + 3 - $start)
        $groups = @{
            Username = @('${env_var.USERNAME}'); Directory = @('$directory'); Git = @('$git_branch', '$git_status');
            Languages = @('$nodejs', '$python', '$rust', '$dotnet', '$package'); Duration = @('$cmd_duration'); Time = @('$time'); Jobs = @('$jobs')
        }
        foreach ($keyName in $groups.Keys) {
            foreach ($token in $groups[$keyName]) {
                if (-not $format.Contains($token)) { throw "Unrecognized prompt template for ${edition}: $token missing." }
                if (-not $state[$keyName]) { $format = [regex]::Replace($format, '(?m)^' + [regex]::Escape($token) + '\\\r?\n', '') }
            }
        }
        if (-not $format.Contains('$character')) { throw "Unrecognized prompt template for ${edition}: character missing." }
        if (-not $state.Status) { $format = $format.Replace('$character', '>') }
        $toml = $toml.Substring(0, $start) + $format + $toml.Substring($end + 3)
        $toml = $toml.Replace('bold #87FF00', ('bold ' + $state.DirectoryColor.ToUpperInvariant()))
        $plans += @{ Edition = $edition; Paths = $paths; State = $state; Toml = $toml; SourceHash = (Get-PVFileHash $template) }
    }
    foreach ($plan in $plans) {
        $paths = $plan.Paths
        Backup-PVFiles $paths.Base @($paths.Prompt, $paths.PromptSettings)
        [System.IO.File]::WriteAllText($paths.Prompt, $plan.Toml, [System.Text.UTF8Encoding]::new($false))
        $plan.State.PromptHash = (Get-PVFileHash $paths.Prompt)
        $plan.State.SourceHash = $plan.SourceHash
        [System.IO.File]::WriteAllText($paths.PromptSettings, ($plan.State | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
        if ($plan.Edition -eq $PSVersionTable.PSEdition) { $env:STARSHIP_CONFIG = $paths.Prompt }
    }
    Write-Host 'Prompt settings saved. Other open shells must be restarted.'
}

function global:Get-PVAnimationState([string]$Edition) {
    $paths = Get-PVPaths $Edition
    if (-not (Test-Path -LiteralPath $paths.AnimationSettings)) { return @{ Welcome = $true; Banner = $true; Idle = $true; IdleSeconds = 5 } }
    try { $state = Get-Content -LiteralPath $paths.AnimationSettings -Raw | ConvertFrom-Json } catch { throw "Invalid animation settings: $($paths.AnimationSettings). Back up and correct this JSON, or move it aside to restore defaults; then reopen the menu." }
    if ($state.Welcome -isnot [bool] -or $state.Banner -isnot [bool] -or $state.Idle -isnot [bool] -or
        ($state.IdleSeconds -isnot [int] -and $state.IdleSeconds -isnot [long]) -or $state.IdleSeconds -lt 1 -or $state.IdleSeconds -gt 3600) { throw "Invalid animation settings: $($paths.AnimationSettings). Back up and correct this JSON, or move it aside to restore defaults; then reopen the menu." }
    return @{ Welcome = $state.Welcome; Banner = $state.Banner; Idle = $state.Idle; IdleSeconds = $state.IdleSeconds }
}

function global:Set-PVAnimationState([string[]]$Editions, [string]$Key, $Value) {
    if ($Key -notin @('Welcome', 'Banner', 'Idle', 'IdleSeconds')) { throw 'Unknown animation setting.' }
    if ($Key -eq 'IdleSeconds') {
        if ($Value -isnot [int] -or $Value -lt 1 -or $Value -gt 3600) { throw 'Choose a delay from 1 to 3600 seconds.' }
    } elseif ($Value -isnot [bool]) { throw 'Animation switches must be boolean.' }
    $plans = @()
    foreach ($edition in $Editions) {
        $manifest = Get-PVManifest $edition
        $paths = Get-PVPaths $edition
        Assert-PVOwnedFile $manifest (Join-Path $paths.Theme 'manager.ps1') 'manager.ps1'
        $state = Get-PVAnimationState $edition
        $state[$Key] = $Value
        $plans += @{ Edition = $edition; Paths = $paths; State = $state }
    }
    foreach ($plan in $plans) {
        Backup-PVFiles $plan.Paths.Base @($plan.Paths.AnimationSettings)
        [System.IO.File]::WriteAllText($plan.Paths.AnimationSettings, ($plan.State | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
        if ($plan.Edition -eq $PSVersionTable.PSEdition) {
            $global:PowerShellVoidSettings = $plan.State
            if ($plan.State.Idle) { Start-PowerShellVoidIdleMonitor }
            elseif ($global:PowerShellVoidIdleSubscription) {
                $job = $global:PowerShellVoidIdleSubscription
                Get-EventSubscriber -SourceIdentifier PowerShell.OnIdle -ErrorAction SilentlyContinue | Where-Object { $_.Action.Id -eq $job.Id } | ForEach-Object { Unregister-Event -SubscriptionId $_.SubscriptionId -ErrorAction SilentlyContinue }
                Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
                $global:PowerShellVoidIdleSubscription = $null
            }
        }
    }
    Write-Host 'Animation settings saved. Startup effects apply in new sessions.'
}

function global:Get-PVColorNames {
    return @('background', 'foreground', 'black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white', 'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite')
}

function global:Get-PVPalette([string]$Edition) {
    $paths = Get-PVPaths $Edition
    $manifest = Get-PVManifest $Edition
    Assert-PVOwnedFile $manifest (Join-Path $paths.Theme 'manager.ps1') 'manager.ps1'
    $schemePath = Join-Path $paths.Theme 'termuxvoid-scheme.json'
    Assert-PVOwnedFile $manifest $schemePath 'termuxvoid-scheme.json'
    $scheme = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
    $result = @{}
    foreach ($name in (Get-PVColorNames)) {
        $value = if ($manifest.terminalColors) { $manifest.terminalColors.$name } else { $scheme.$name }
        if ($value -notmatch '^#[0-9a-fA-F]{6}$') { throw "Invalid saved terminal color: $name." }
        $result[$name] = $value.ToUpperInvariant()
    }
    return $result
}

function global:Get-PVUpdatedPalette($Palette, [string]$Field, [string]$Value, [string]$Edition) {
    $result = @{}
    foreach ($name in (Get-PVColorNames)) { $result[$name] = $Palette[$name] }
    if ($Field -ne 'Preset') { $result[$Field] = $Value.ToUpperInvariant(); return $result }
    $schemePath = Join-Path (Get-PVPaths $Edition).Theme 'termuxvoid-scheme.json'
    $original = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
    foreach ($name in (Get-PVColorNames)) { $result[$name] = $original.$name.ToUpperInvariant() }
    if ($Value -eq 'Ocean') {
        $result.background = '#071927'; $result.foreground = '#D9F6FF'; $result.blue = '#45C5F7'; $result.cyan = '#64FFDA'; $result.purple = '#8F9BFF'
    } elseif ($Value -eq 'Monochrome') {
        $result.background = '#151515'; $result.foreground = '#E6E6E6'
        $result.black = '#242424'; $result.red = '#9B9B9B'; $result.green = '#AFAFAF'; $result.yellow = '#C1C1C1'
        $result.blue = '#AFAFAF'; $result.purple = '#C0C0C0'; $result.cyan = '#D0D0D0'; $result.white = '#E6E6E6'
        $result.brightBlack = '#777777'; $result.brightRed = '#B4B4B4'; $result.brightGreen = '#C4C4C4'; $result.brightYellow = '#D4D4D4'
        $result.brightBlue = '#C4C4C4'; $result.brightPurple = '#D0D0D0'; $result.brightCyan = '#E0E0E0'; $result.brightWhite = '#FFFFFF'
    }
    return $result
}

function global:Get-PVContrast([string]$Foreground, [string]$Background) {
    $luminances = @()
    foreach ($hex in @($Foreground, $Background)) {
        if ($hex -notmatch '^#[0-9a-fA-F]{6}$') { throw 'Use a color such as #16B1FB.' }
        $channels = @()
        foreach ($offset in @(1, 3, 5)) {
            $value = [Convert]::ToInt32($hex.Substring($offset, 2), 16) / 255.0
            $channels += if ($value -le 0.04045) { $value / 12.92 } else { [Math]::Pow(($value + 0.055) / 1.055, 2.4) }
        }
        $luminances += (0.2126 * $channels[0] + 0.7152 * $channels[1] + 0.0722 * $channels[2])
    }
    return (([Math]::Max($luminances[0], $luminances[1]) + 0.05) / ([Math]::Min($luminances[0], $luminances[1]) + 0.05))
}

function global:Set-PVPalette([string[]]$Editions, [string]$Field, [string]$Value) {
    $names = @(Get-PVColorNames)
    if ($Field -ne 'Preset' -and $Field -notin $names) { throw 'Unknown terminal color.' }
    if ($Field -eq 'Preset' -and $Value -notin @('Void', 'Ocean', 'Monochrome')) { throw 'Unknown palette.' }
    if ($Field -ne 'Preset' -and $Value -notmatch '^#[0-9a-fA-F]{6}$') { throw 'Use a color such as #16B1FB.' }
    $plans = @()
    foreach ($edition in $Editions) {
        $paths = Get-PVPaths $edition
        if (-not $paths.Fragment) { throw 'LOCALAPPDATA is unavailable; cannot manage a Windows Terminal profile.' }
        $manifest = Get-PVManifest $edition
        $palette = Get-PVPalette $edition
        $palette = Get-PVUpdatedPalette $palette $Field $Value $edition
        if (Test-Path -LiteralPath $paths.Fragment) {
            if (-not $manifest.terminalFragmentHash -or (Get-PVFileHash $paths.Fragment) -ne $manifest.terminalFragmentHash) {
                throw "Windows Terminal fragment is modified or unowned: $($paths.Fragment). No changes made. Back up your edits and restore the matching owned fragment before retrying."
            }
            $fragment = Get-Content -LiteralPath $paths.Fragment -Raw | ConvertFrom-Json
            if (@($fragment.schemes).Count -ne 1 -or @($fragment.profiles).Count -ne 1) { throw "Unrecognized Terminal fragment: $($paths.Fragment)." }
        } else {
            if ($manifest.terminalFragmentHash) { throw "The owned Terminal fragment is missing: $($paths.Fragment). Restore it before changing colors." }
            $scheme = Get-Content -LiteralPath (Join-Path $paths.Theme 'termuxvoid-scheme.json') -Raw | ConvertFrom-Json
            $scheme.name = 'PowerShell Void ' + $edition
            $exe = if ($edition -eq $PSVersionTable.PSEdition) { (Get-Process -Id $PID).Path }
                   elseif ($edition -eq 'Desktop') { Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
                   else { (Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue).Source }
            if (-not $exe -or -not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw "Cannot locate the $edition PowerShell executable. Open that edition and retry." }
            $guid = if ($edition -eq 'Core') { '{c04eb7b9-0a8d-4fc1-a6c6-dd5b94effd81}' } else { '{b29cc26a-e530-4639-a25b-34e13e5cd7b2}' }
            $label = if ($edition -eq 'Core') { 'PowerShell Void 7' } else { 'PowerShell Void Windows PowerShell' }
            $profile = @{ name = $label; guid = $guid; commandline = '"' + $exe + '"'; colorScheme = $scheme.name }
            $fragment = @{ profiles = @($profile); schemes = @($scheme) }
        }
        foreach ($name in $names) { $fragment.schemes[0].$name = $palette[$name] }
        $plans += @{ Edition = $edition; Paths = $paths; Manifest = $manifest; Palette = $palette; Fragment = $fragment }
    }
    foreach ($plan in $plans) {
        $paths = $plan.Paths
        Backup-PVFiles $paths.Base @($paths.Fragment, $paths.Manifest)
        New-Item -ItemType Directory -Path (Split-Path -Parent $paths.Fragment) -Force | Out-Null
        try {
            [System.IO.File]::WriteAllText($paths.Fragment, ($plan.Fragment | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
            $plan.Manifest | Add-Member -NotePropertyName terminalColors -NotePropertyValue $plan.Palette -Force
            $plan.Manifest | Add-Member -NotePropertyName terminalFragmentHash -NotePropertyValue (Get-PVFileHash $paths.Fragment) -Force
            [System.IO.File]::WriteAllText($paths.Manifest, ($plan.Manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        } catch { throw "Could not save the Terminal profile. Restore the printed backup before retrying: $($_.Exception.Message)" }
    }
    Write-Host 'Terminal colors saved to a separate PowerShell Void profile. Restart Terminal and select that profile.'
}

function global:Show-PVChoiceStatus([string]$Message, [bool]$Compact) {
    if ($Compact) {
        # Keep the status on one line even in a narrow window. The full menu stays above it.
        $width = [Console]::WindowWidth
        if ($width -gt 4 -and $Message.Length -ge $width) { $Message = $Message.Substring(0, $width - 4) + '...' }
        [Console]::Write("`r$([char]27)[2K$Message")
    } else { Write-Host $Message }
}

function global:Read-PVChoice([string]$Title, [string[]]$Items) {
    Write-Host "`n=== $Title ==="
    for ($i = 0; $i -lt $Items.Count; $i++) { Write-Host (" {0,2}) {1}" -f ($i + 1), $Items[$i]) }
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
        $answer = Read-Host 'Enter a number (0 to go back)'
        $number = 0
        if ([int]::TryParse($answer, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) { return ($number - 1) }
        return -1
    }
    $selection = 0
    $digits = ''
    $compact = [bool]($env:WT_SESSION -and $env:TERM -ne 'dumb' -and $env:POWERSHELLVOID_PLAIN_MENU -ne '1')
    Write-Host 'Up/Down + Enter, or type a number + Enter. Esc/0 goes back.'
    Show-PVChoiceStatus ("Selected: {0}" -f $Items[$selection]) $compact
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $selection = ($selection + $Items.Count - 1) % $Items.Count; $digits = ''; Show-PVChoiceStatus ("Selected: {0}" -f $Items[$selection]) $compact }
            'DownArrow' { $selection = ($selection + 1) % $Items.Count; $digits = ''; Show-PVChoiceStatus ("Selected: {0}" -f $Items[$selection]) $compact }
            'Escape' { Write-Host ''; return -1 }
            'Backspace' { if ($digits.Length -gt 0) { $digits = $digits.Substring(0, $digits.Length - 1); Show-PVChoiceStatus "Number: $digits" $compact } }
            'Enter' {
                if ($compact) { Write-Host '' }
                if ($digits.Length -eq 0) { return $selection }
                $number = 0
                if ([int]::TryParse($digits, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) { return ($number - 1) }
                if ($digits -eq '0') { return -1 }
                $digits = ''; Show-PVChoiceStatus 'Invalid choice. Try again.' $compact
            }
            default {
                if ($key.KeyChar -ge '0' -and $key.KeyChar -le '9' -and $digits.Length -lt 3) {
                    $digits += $key.KeyChar; Show-PVChoiceStatus "Number: $digits" $compact
                }
            }
        }
    }
}

function global:Read-PVText([string]$Label) {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return (Read-Host $Label) }
    Write-Host -NoNewline "$Label "
    $value = ''
    while ($true) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'Enter') { Write-Host ''; return $value }
        if ($key.Key -eq 'Escape') { Write-Host ''; return '' }
        if ($key.Key -eq 'Backspace') {
            if ($value.Length -gt 0) { $value = $value.Substring(0, $value.Length - 1); [Console]::Write("`b `b") }
        } elseif (-not [char]::IsControl($key.KeyChar) -and $value.Length -lt 32) {
            $value += $key.KeyChar; [Console]::Write($key.KeyChar)
        }
    }
}

function global:Get-PVSuggestionState([string]$Edition) {
    $path = (Get-PVPaths $Edition).SuggestionSettings
    if (-not (Test-Path -LiteralPath $path)) { return @{ Enabled = $true } }
    try {
        $saved = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if ($saved.Enabled -isnot [bool]) { throw 'Invalid Enabled value' }
        return @{ Enabled = $saved.Enabled }
    } catch { throw "Invalid history suggestion settings: $path. Back up and correct the file, or move it aside to restore defaults." }
}

function global:Apply-PVSuggestions([bool]$Enabled) {
    if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected -or $env:TERM -eq 'dumb') { return }
    try {
        if (-not (Get-Module PSReadLine)) { Import-Module PSReadLine -ErrorAction Stop }
        $command = Get-Command Set-PSReadLineOption -ErrorAction Stop
        if (-not $command.Parameters.ContainsKey('PredictionSource')) {
            if ($Enabled) { Write-Warning 'History suggestions need PSReadLine 2.1 or newer. Update PowerShell Void or install PSReadLine 2.3.6 for the current user, then restart PowerShell.' }
            return
        }
        $options = Get-PSReadLineOption
        $source = [string]$options.PredictionSource
        if ($Enabled) {
            $newSource = switch ($source) { 'None' { 'History' } 'Plugin' { 'HistoryAndPlugin' } default { $source } }
            if ($command.Parameters.ContainsKey('PredictionViewStyle')) {
                Set-PSReadLineOption -PredictionSource $newSource -PredictionViewStyle InlineView -ErrorAction Stop
            } else {
                # PSReadLine 2.1 has only inline predictions and no view-style parameter.
                Set-PSReadLineOption -PredictionSource $newSource -ErrorAction Stop
            }
            if ([string]$options.HistorySaveStyle -eq 'SaveNothing') { Write-Warning 'PSReadLine history saving is disabled in your settings; suggestions will not persist between sessions.' }
        } else {
            $newSource = switch ($source) { 'History' { 'None' } 'HistoryAndPlugin' { 'Plugin' } default { $source } }
            Set-PSReadLineOption -PredictionSource $newSource -ErrorAction Stop
        }
    } catch { Write-Warning "Could not configure history suggestions: $($_.Exception.Message)" }
}

function global:Set-PVSuggestionState([string[]]$Editions, [bool]$Enabled) {
    $plans = @()
    foreach ($edition in $Editions) {
        $paths = Get-PVPaths $edition
        $manifest = Get-PVManifest $edition
        Assert-PVOwnedFile $manifest (Join-Path $paths.Theme 'manager.ps1') 'manager.ps1'
        $null = Get-PVSuggestionState $edition
        $plans += $paths
    }
    foreach ($paths in $plans) {
        Backup-PVFiles $paths.Base @($paths.SuggestionSettings)
        [System.IO.File]::WriteAllText($paths.SuggestionSettings, (@{ Enabled = $Enabled } | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    }
    if ($Editions -contains $PSVersionTable.PSEdition) { Apply-PVSuggestions $Enabled }
    Write-Host 'History suggestion preference saved. Other open shells must be restarted.'
}

function global:Show-PVSuggestions([string[]]$Editions) {
    while ($true) {
        try { $states = @{}; foreach ($edition in $Editions) { $states[$edition] = Get-PVSuggestionState $edition } } catch { Write-Warning $_.Exception.Message; return }
        $state = $states[$PSVersionTable.PSEdition]
        $choice = Read-PVChoice 'History suggestions' @("History suggestions: $(Format-PVValues $Editions $states 'Enabled')", 'Back')
        if ($choice -lt 0 -or $choice -eq 1) { return }
        try {
            $value = -not $state.Enabled
            if (Confirm-PVMixedChange $Editions $states 'Enabled' $value) { Set-PVSuggestionState $Editions $value }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Get-PVTargets([bool]$Both) {
    $current = $PSVersionTable.PSEdition
    $result = @($current)
    if ($Both) {
        $other = if ($current -eq 'Core') { 'Desktop' } else { 'Core' }
        if (Test-Path -LiteralPath (Get-PVPaths $other).Manifest -PathType Leaf) { $result += $other }
    }
    return $result
}

function global:Format-PVValues([string[]]$Editions, $States, [string]$Key) {
    $parts = @()
    foreach ($edition in $Editions) {
        $value = $States[$edition][$Key]
        if ($value -is [bool]) { $value = if ($value) { 'On' } else { 'Off' } }
        if ($Editions.Count -gt 1) { $parts += "${edition}: $value" } else { $parts += "$value" }
    }
    return ($parts -join ' | ')
}

function global:Confirm-PVMixedChange([string[]]$Editions, $States, [string]$Key, [bool]$Value) {
    if ($Editions.Count -lt 2 -or $States[$Editions[0]][$Key] -eq $States[$Editions[1]][$Key]) { return $true }
    $desired = if ($Value) { 'On' } else { 'Off' }
    $current = Format-PVValues $Editions $States $Key
    return ((Read-PVChoice "Values differ ($current). Set $Key to $desired in both editions?" @('No', 'Yes')) -eq 1)
}

function global:Confirm-PVPalette([string[]]$Editions, [string]$Field, [string]$Value) {
    if ($Field -ne 'Preset' -and $Value -notmatch '^#[0-9a-fA-F]{6}$') { throw 'Use a color such as #16B1FB.' }
    $low = $false
    foreach ($edition in $Editions) {
        $palette = Get-PVUpdatedPalette (Get-PVPalette $edition) $Field $Value $edition
        $ratio = Get-PVContrast $palette.foreground $palette.background
        Write-Host ("{0}: background {1}, foreground {2}, contrast {3:N2}:1" -f $edition, $palette.background, $palette.foreground, $ratio)
        if ($ratio -lt 4.5) { $low = $true }
        if ($Field -eq 'Preset') {
            foreach ($name in (Get-PVColorNames)) { Write-Host ("  {0,-13} {1}" -f $name, $palette[$name]) }
        }
    }
    if ($low) { Write-Warning 'Foreground/background contrast is below 4.5:1 and may be hard to read.' }
    if ($Field -ne 'Preset' -and -not $low) { Write-Host 'Changes affect a separate PowerShell Void profile. Restart Terminal and select that profile.' }
    if ($Field -eq 'Preset' -or $low) {
        Write-Host 'Only the default foreground/background pair is checked; prompt and ANSI colors may differ.'
        Write-Host 'Changes affect a separate PowerShell Void profile. Restart Terminal and select that profile.'
        return ((Read-PVChoice "Apply $Value to $($Editions -join ', ')?" @('No', 'Yes')) -eq 1)
    }
    return $true
}

function global:Show-PVAnimations([string[]]$Editions) {
    while ($true) {
        try {
            $states = @{}; foreach ($edition in $Editions) { $states[$edition] = Get-PVAnimationState $edition }
        } catch { Write-Warning $_.Exception.Message; return }
        $state = $states[$PSVersionTable.PSEdition]
        $choices = @("TTE welcome: $(Format-PVValues $Editions $states 'Welcome')", "ascii.rest banner: $(Format-PVValues $Editions $states 'Banner')", "Idle showcase: $(Format-PVValues $Editions $states 'Idle')", "Idle delay (seconds): $(Format-PVValues $Editions $states 'IdleSeconds')", 'Preview an animation', 'Back')
        $choice = Read-PVChoice 'Animations' $choices
        if ($choice -lt 0 -or $choice -eq 5) { return }
        try {
            if ($choice -lt 3) {
                $key = @('Welcome', 'Banner', 'Idle')[$choice]; $value = -not $state[$key]
                if (Confirm-PVMixedChange $Editions $states $key $value) { Set-PVAnimationState $Editions $key $value }
            } elseif ($choice -eq 3) {
                $answer = Read-PVText 'Idle delay in seconds (1-3600; Esc cancels):'
                if ($answer) { $number = 0; if (-not [int]::TryParse($answer, [ref]$number)) { throw 'Enter a whole number.' }; Set-PVAnimationState $Editions 'IdleSeconds' $number }
            } elseif ($choice -eq 4) {
                $preview = Read-PVChoice 'Preview' @('TTE welcome', 'ascii.rest banner', 'Asciimatics showcase', 'Back')
                if ($preview -eq 0) { Show-PowerShellVoidAnimation -Engine TTE }
                elseif ($preview -eq 1) { Show-PowerShellVoidAnimation -Engine AsciiRest }
                elseif ($preview -eq 2) { Show-PowerShellVoidAnimation -Engine Asciimatics }
            }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Show-PVPrompt([string[]]$Editions) {
    $keys = @('Username', 'Directory', 'Git', 'Languages', 'Duration', 'Time', 'Jobs', 'Status')
    while ($true) {
        try { $states = @{}; foreach ($edition in $Editions) { $states[$edition] = Get-PVPromptState $edition } } catch { Write-Warning $_.Exception.Message; return }
        $state = $states[$PSVersionTable.PSEdition]
        $choices = @()
        foreach ($key in $keys) { $choices += "$key : $(Format-PVValues $Editions $states $key)" }
        $choices += @("Directory text color: $(Format-PVValues $Editions $states 'DirectoryColor')", 'Reapply settings to latest prompt template', 'Back')
        $choice = Read-PVChoice 'Prompt components' $choices
        if ($choice -lt 0 -or $choice -eq 10) { return }
        try {
            if ($choice -lt $keys.Count) {
                $key = $keys[$choice]; $value = -not $state[$key]
                if (Confirm-PVMixedChange $Editions $states $key $value) { Set-PVPromptState $Editions $key $value }
            } elseif ($choice -eq 8) { $color = Read-PVText 'Directory color (#RRGGBB; Esc cancels):'; if ($color) { Set-PVPromptState $Editions 'DirectoryColor' $color } }
            elseif ($choice -eq 9) { Set-PVPromptState $Editions 'Reapply' $null }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Show-PVColors([string[]]$Editions) {
    while ($true) {
        try { $palettes = @{}; foreach ($edition in $Editions) { $palettes[$edition] = Get-PVPalette $edition } } catch { Write-Warning $_.Exception.Message; return }
        $palette = $palettes[$PSVersionTable.PSEdition]
        $choice = Read-PVChoice 'Windows Terminal colors' @('Void preset', 'Ocean preset', 'Monochrome preset', 'Edit one color', 'Show current colors', 'Back')
        if ($choice -lt 0 -or $choice -eq 5) { return }
        try {
            if ($choice -lt 3) {
                $preset = @('Void', 'Ocean', 'Monochrome')[$choice]
                if (Confirm-PVPalette $Editions 'Preset' $preset) { Set-PVPalette $Editions 'Preset' $preset }
            }
            elseif ($choice -eq 3) {
                $names = @(Get-PVColorNames)
                $items = @($names | ForEach-Object { "$_ : $(Format-PVValues $Editions $palettes $_)" }) + @('Back')
                $field = Read-PVChoice 'Choose color' $items
                if ($field -ge 0 -and $field -lt $names.Count) {
                    $color = Read-PVText "$($names[$field]) (#RRGGBB; Esc cancels):"
                    if ($color -and (Confirm-PVPalette $Editions $names[$field] $color)) { Set-PVPalette $Editions $names[$field] $color }
                }
            } elseif ($choice -eq 4) { foreach ($name in (Get-PVColorNames)) { Write-Host ("{0,-13} {1}" -f $name, (Format-PVValues $Editions $palettes $name)) } }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Show-PVMaintenance {
    while ($true) {
        $choice = Read-PVChoice 'Status and maintenance (current edition)' @('Show status', 'Repair animation dependencies', 'Update PowerShell Void', 'Uninstall current edition', 'Back')
        if ($choice -lt 0 -or $choice -eq 4) { return }
        try {
            $paths = Get-PVPaths $PSVersionTable.PSEdition
            $manifest = Get-PVManifest $PSVersionTable.PSEdition
            switch ($choice) {
                0 {
                    Write-Host "Edition: $($PSVersionTable.PSEdition); profile: $($manifest.profilePath)"
                    Write-Host "Installation: $($paths.Theme)"
                    Write-Host "Starship available: $([bool](Get-Command starship -CommandType Application -ErrorAction SilentlyContinue))"
                    Write-Host "Python environment available: $(Test-Path -LiteralPath (Join-Path $paths.Base 'animation-python\Scripts\python.exe'))"
                    Write-Host "ascii.rest available: $(Test-Path -LiteralPath (Join-Path $paths.Base 'animation-node\node_modules\ascii.rest\dist\cli.js'))"
                    Write-Host "Terminal profile: $(if ($paths.Fragment) { Test-Path -LiteralPath $paths.Fragment } else { $false })"
                    if ($global:PowerShellVoidIdleFailed) { Write-Warning "Idle animation stopped: $global:PowerShellVoidIdleError" }
                }
                1 {
                    if ((Read-PVChoice 'Repair downloads dependencies and may install Python with WinGet. Continue?' @('No', 'Yes')) -eq 1) {
                        $setup = Join-Path $paths.Theme 'animation-setup.ps1'; Assert-PVOwnedFile $manifest $setup 'animation-setup.ps1'
                        & $setup -Base $paths.Base
                    }
                }
                2 {
                    if ((Read-PVChoice 'Update downloads and executes the current development branch. Continue?' @('No', 'Yes')) -eq 1) {
                        $url = 'https://raw.githubusercontent.com/JCVERSA/TermuxVoid-Theme/arena/d693b190-termuxvoid-theme/windows/install.ps1'
                        & ([scriptblock]::Create((Invoke-RestMethod -Uri $url)))
                    }
                }
                3 {
                    if ((Read-PVChoice 'Uninstall this edition? Backups and shared dependencies are retained.' @('No', 'Yes')) -eq 1) {
                        $installer = Join-Path $paths.Theme 'termuxvoid.ps1'; Assert-PVOwnedFile $manifest $installer 'termuxvoid.ps1'
                        & $installer -Uninstall
                        Write-Host 'Restart this PowerShell session to finish unloading the theme.'
                        return
                    }
                }
            }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Invoke-PowerShellVoidManager {
    if ($global:PowerShellVoidMenuActive) { return }
    $global:PowerShellVoidMenuActive = $true
    $both = $false
    try {
        while ($true) {
            $targets = @(Get-PVTargets $both)
            $scope = $targets -join ', '
            $choice = Read-PVChoice "PowerShell Void Manager | Target: $scope" @('Animations', 'Prompt components', 'Windows Terminal colors', 'Status and maintenance', "Switch target (current/both): $scope", 'History suggestions', 'Exit')
            if ($choice -lt 0 -or $choice -eq 6) { return }
            switch ($choice) {
                0 { Show-PVAnimations $targets }
                1 { Show-PVPrompt $targets }
                2 { Show-PVColors $targets }
                3 { Show-PVMaintenance }
                4 { $both = -not $both; if ($both -and $targets.Count -eq 1 -and @(Get-PVTargets $true).Count -eq 1) { Write-Host 'Only the current edition is installed.' } }
                5 { Show-PVSuggestions $targets }
            }
        }
    } finally { $global:PowerShellVoidMenuActive = $false }
}

function global:Start-PVShortcut {
    if (-not $env:WT_SESSION -or [Console]::IsInputRedirected -or [Console]::IsOutputRedirected) { return }
    try {
        if (-not (Get-Module PSReadLine)) { Import-Module PSReadLine -ErrorAction Stop }
        $bound = @(Get-PSReadLineKeyHandler | Where-Object { $_.Key -match '^(Ctrl\+Alt\+v|Alt\+Ctrl\+v)$' })
        if ($bound.Count -gt 0) { return }
        Set-PSReadLineKeyHandler -Chord 'Ctrl+Alt+v' -BriefDescription 'PowerShellVoidManager' -LongDescription 'Open PowerShell Void Manager' -ScriptBlock {
            $line = $null; $cursor = 0
            [Microsoft.PowerShell.PSConsoleReadLine]::GetBufferState([ref]$line, [ref]$cursor)
            if ($line.Length -gt 0) { return }
            Write-Host ''
            try { Invoke-PowerShellVoidManager } finally { [Microsoft.PowerShell.PSConsoleReadLine]::InvokePrompt() }
        }
    } catch { Write-Warning "PowerShell Void shortcut unavailable; use psvoid instead. $($_.Exception.Message)" }
}

if (-not (Get-Command psvoid -ErrorAction SilentlyContinue)) {
    Set-Item -Path Function:\global:psvoid -Value { Invoke-PowerShellVoidManager }
}
& {
    $paths = Get-PVPaths $PSVersionTable.PSEdition
    if (Test-Path -LiteralPath $paths.PromptSettings -PathType Leaf) {
        try {
            $state = Get-PVPromptState $PSVersionTable.PSEdition
            $env:STARSHIP_CONFIG = $paths.Prompt
            $template = Join-Path $paths.Theme 'starship.toml'
            if ((Test-Path -LiteralPath $template -PathType Leaf) -and (Get-PVFileHash $template) -ne $state.SourceHash) {
                Write-Warning 'PowerShell Void prompt template changed; use psvoid > Prompt components > Reapply to pick up the new template.'
            }
        } catch { Write-Warning $_.Exception.Message }
    }
    Start-PVShortcut
    try { $suggestions = Get-PVSuggestionState $PSVersionTable.PSEdition; Apply-PVSuggestions $suggestions.Enabled }
    catch { Write-Warning $_.Exception.Message }
}
