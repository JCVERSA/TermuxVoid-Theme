# PowerShell Void manager. Installer-owned templates remain unchanged.
# Functions use a distinct namespace to avoid interfering with the user's profile.
if (@('Invoke-PowerShellVoidManager', 'Get-PVPaths', 'Get-PVManifest', 'Assert-PVOwnedFile', 'Backup-PVFiles', 'Read-PVChoice', 'Read-PVText', 'Get-PVPromptState', 'Set-PVPromptState', 'Get-PVAnimationState', 'Set-PVAnimationState', 'Get-PVColorNames', 'Get-PVPalette', 'Set-PVPalette', 'Get-PVTargets', 'Show-PVAnimations', 'Show-PVPrompt', 'Show-PVColors', 'Show-PVMaintenance', 'Start-PVShortcut' | Where-Object {
    Get-Command $_ -ErrorAction SilentlyContinue
}).Count -gt 0) { return }

function global:Get-PVPaths([string]$Edition) {
    $base = Join-Path $HOME '.config\TermuxVoid-Windows'
    $theme = Join-Path $base $Edition
    $fragment = if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA ("Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme\$Edition.json") } else { $null }
    return @{ Base = $base; Theme = $theme; Manifest = (Join-Path $theme 'manifest.json');
        Prompt = (Join-Path $base "prompt-$Edition.toml"); PromptSettings = (Join-Path $base "prompt-settings-$Edition.json");
        AnimationSettings = (Join-Path $base "animation-settings-$Edition.json"); Fragment = $fragment }
}

function global:Get-PVManifest([string]$Edition) {
    $paths = Get-PVPaths $Edition
    if (-not (Test-Path -LiteralPath $paths.Manifest -PathType Leaf)) { throw "No $Edition installation found." }
    try { $manifest = Get-Content -LiteralPath $paths.Manifest -Raw | ConvertFrom-Json } catch { throw "Invalid manifest: $($paths.Manifest)" }
    if (-not $manifest.profilePath -or -not $manifest.hashes) { throw "Invalid manifest: $($paths.Manifest)" }
    return $manifest
}

function global:Assert-PVOwnedFile($Manifest, [string]$Path, [string]$Name) {
    $expected = $Manifest.hashes.$Name
    if (-not $expected -or -not (Test-Path -LiteralPath $Path -PathType Leaf) -or (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -ne $expected) {
        throw "Managed file is missing or modified: $Path. Resolve this before making changes."
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
    if (-not (Test-Path -LiteralPath $paths.Prompt -PathType Leaf) -or (Get-FileHash -LiteralPath $paths.Prompt -Algorithm SHA256).Hash -ne $saved.PromptHash) {
        throw "Custom prompt is missing or has been edited: $($paths.Prompt). It was not changed."
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
                if (-not $format.Contains($token)) { throw "Unrecognized prompt template for $edition: $token missing." }
                if (-not $state[$keyName]) { $format = [regex]::Replace($format, '(?m)^' + [regex]::Escape($token) + '\\\r?\n', '') }
            }
        }
        if (-not $format.Contains('$character')) { throw "Unrecognized prompt template for $edition: character missing." }
        if (-not $state.Status) { $format = $format.Replace('$character', '>') }
        $toml = $toml.Substring(0, $start) + $format + $toml.Substring($end + 3)
        $toml = $toml.Replace('bold #87FF00', ('bold ' + $state.DirectoryColor.ToUpperInvariant()))
        $plans += @{ Edition = $edition; Paths = $paths; State = $state; Toml = $toml; SourceHash = (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash }
    }
    foreach ($plan in $plans) {
        $paths = $plan.Paths
        Backup-PVFiles $paths.Base @($paths.Prompt, $paths.PromptSettings)
        [System.IO.File]::WriteAllText($paths.Prompt, $plan.Toml, [System.Text.UTF8Encoding]::new($false))
        $plan.State.PromptHash = (Get-FileHash -LiteralPath $paths.Prompt -Algorithm SHA256).Hash
        $plan.State.SourceHash = $plan.SourceHash
        [System.IO.File]::WriteAllText($paths.PromptSettings, ($plan.State | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
        if ($plan.Edition -eq $PSVersionTable.PSEdition) { $env:STARSHIP_CONFIG = $paths.Prompt }
    }
    Write-Host 'Prompt settings saved. Other open shells must be restarted.'
}

function global:Get-PVAnimationState([string]$Edition) {
    $paths = Get-PVPaths $Edition
    if (-not (Test-Path -LiteralPath $paths.AnimationSettings)) { return @{ Welcome = $true; Banner = $true; Idle = $true; IdleSeconds = 5 } }
    try { $state = Get-Content -LiteralPath $paths.AnimationSettings -Raw | ConvertFrom-Json } catch { throw "Invalid animation settings: $($paths.AnimationSettings)" }
    if ($state.Welcome -isnot [bool] -or $state.Banner -isnot [bool] -or $state.Idle -isnot [bool] -or
        ($state.IdleSeconds -isnot [int] -and $state.IdleSeconds -isnot [long]) -or $state.IdleSeconds -lt 1 -or $state.IdleSeconds -gt 3600) { throw "Invalid animation settings: $($paths.AnimationSettings)" }
    return @{ Welcome = $state.Welcome; Banner = $state.Banner; Idle = $state.Idle; IdleSeconds = $state.IdleSeconds }
}

function global:Set-PVAnimationState([string[]]$Editions, [string]$Key, $Value) {
    if ($Key -notin @('Welcome', 'Banner', 'Idle', 'IdleSeconds')) { throw 'Unknown animation setting.' }
    if ($Key -eq 'IdleSeconds') {
        if ($Value -isnot [int] -or $Value -lt 1 -or $Value -gt 3600) { throw 'Choose a delay from 1 to 3600 seconds.' }
    } elseif ($Value -isnot [bool]) { throw 'Animation switches must be boolean.' }
    $plans = @()
    foreach ($edition in $Editions) {
        $null = Get-PVManifest $edition
        $paths = Get-PVPaths $edition
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
        if ($Field -eq 'Preset') {
            $schemePath = Join-Path $paths.Theme 'termuxvoid-scheme.json'
            $original = Get-Content -LiteralPath $schemePath -Raw | ConvertFrom-Json
            foreach ($name in $names) { $palette[$name] = $original.$name.ToUpperInvariant() }
            if ($Value -eq 'Ocean') {
                $palette.background = '#071927'; $palette.foreground = '#D9F6FF'; $palette.blue = '#45C5F7'; $palette.cyan = '#64FFDA'; $palette.purple = '#8F9BFF'
            } elseif ($Value -eq 'Monochrome') {
                $palette.background = '#151515'; $palette.foreground = '#E6E6E6'; $palette.blue = '#AFAFAF'; $palette.cyan = '#D0D0D0'; $palette.purple = '#C0C0C0'
            }
        } else { $palette[$Field] = $Value.ToUpperInvariant() }
        if (Test-Path -LiteralPath $paths.Fragment) {
            if (-not $manifest.terminalFragmentHash -or (Get-FileHash -LiteralPath $paths.Fragment -Algorithm SHA256).Hash -ne $manifest.terminalFragmentHash) {
                throw "Windows Terminal fragment is modified or unowned: $($paths.Fragment). No changes made."
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
            $plan.Manifest | Add-Member -NotePropertyName terminalFragmentHash -NotePropertyValue (Get-FileHash -LiteralPath $paths.Fragment -Algorithm SHA256).Hash -Force
            [System.IO.File]::WriteAllText($paths.Manifest, ($plan.Manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
        } catch { throw "Could not save the Terminal profile. Restore the printed backup before retrying: $($_.Exception.Message)" }
    }
    Write-Host 'Terminal colors saved to a separate PowerShell Void profile. Restart Terminal and select that profile.'
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
    Write-Host 'Up/Down + Enter, or type a number + Enter. Esc/0 goes back.'
    Write-Host ("Selected: {0}" -f $Items[$selection])
    while ($true) {
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            'UpArrow' { $selection = ($selection + $Items.Count - 1) % $Items.Count; $digits = ''; Write-Host ("Selected: {0}" -f $Items[$selection]) }
            'DownArrow' { $selection = ($selection + 1) % $Items.Count; $digits = ''; Write-Host ("Selected: {0}" -f $Items[$selection]) }
            'Escape' { Write-Host ''; return -1 }
            'Backspace' { if ($digits.Length -gt 0) { $digits = $digits.Substring(0, $digits.Length - 1); Write-Host "Number: $digits" } }
            'Enter' {
                if ($digits.Length -eq 0) { return $selection }
                $number = 0
                if ([int]::TryParse($digits, [ref]$number) -and $number -ge 1 -and $number -le $Items.Count) { return ($number - 1) }
                if ($digits -eq '0') { return -1 }
                $digits = ''; Write-Host 'Invalid choice. Try again.'
            }
            default {
                if ($key.KeyChar -ge '0' -and $key.KeyChar -le '9' -and $digits.Length -lt 3) {
                    $digits += $key.KeyChar; Write-Host "Number: $digits"
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

function global:Get-PVTargets([bool]$Both) {
    $current = $PSVersionTable.PSEdition
    $result = @($current)
    if ($Both) {
        $other = if ($current -eq 'Core') { 'Desktop' } else { 'Core' }
        if (Test-Path -LiteralPath (Get-PVPaths $other).Manifest -PathType Leaf) { $result += $other }
    }
    return $result
}

function global:Show-PVAnimations([string[]]$Editions) {
    while ($true) {
        $state = Get-PVAnimationState $PSVersionTable.PSEdition
        $choices = @("TTE welcome: $($state.Welcome)", "ascii.rest banner: $($state.Banner)", "Idle showcase: $($state.Idle)", "Idle delay: $($state.IdleSeconds) seconds", 'Preview an animation', 'Back')
        $choice = Read-PVChoice 'Animations' $choices
        if ($choice -lt 0 -or $choice -eq 5) { return }
        try {
            switch ($choice) {
                0 { Set-PVAnimationState $Editions 'Welcome' (-not $state.Welcome) }
                1 { Set-PVAnimationState $Editions 'Banner' (-not $state.Banner) }
                2 { Set-PVAnimationState $Editions 'Idle' (-not $state.Idle) }
                3 {
                    $answer = Read-PVText 'Idle delay in seconds (1-3600; Esc cancels):'
                    if ($answer) { $number = 0; if (-not [int]::TryParse($answer, [ref]$number)) { throw 'Enter a whole number.' }; Set-PVAnimationState $Editions 'IdleSeconds' $number }
                }
                4 {
                    $preview = Read-PVChoice 'Preview' @('TTE welcome', 'ascii.rest banner', 'Asciimatics showcase', 'Back')
                    if ($preview -eq 0) { Show-PowerShellVoidAnimation -Engine TTE }
                    elseif ($preview -eq 1) { Show-PowerShellVoidAnimation -Engine AsciiRest }
                    elseif ($preview -eq 2) { Show-PowerShellVoidAnimation -Engine Asciimatics }
                }
            }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Show-PVPrompt([string[]]$Editions) {
    $keys = @('Username', 'Directory', 'Git', 'Languages', 'Duration', 'Time', 'Jobs', 'Status')
    while ($true) {
        try { $state = Get-PVPromptState $PSVersionTable.PSEdition } catch { Write-Warning $_.Exception.Message; return }
        $choices = @()
        foreach ($key in $keys) { $choices += "$key : $($state[$key])" }
        $choices += @("Directory text color: $($state.DirectoryColor)", 'Reapply settings to latest prompt template', 'Back')
        $choice = Read-PVChoice 'Prompt components' $choices
        if ($choice -lt 0 -or $choice -eq 10) { return }
        try {
            if ($choice -lt $keys.Count) { $key = $keys[$choice]; Set-PVPromptState $Editions $key (-not $state[$key]) }
            elseif ($choice -eq 8) { $color = Read-PVText 'Directory color (#RRGGBB; Esc cancels):'; if ($color) { Set-PVPromptState $Editions 'DirectoryColor' $color } }
            elseif ($choice -eq 9) { Set-PVPromptState $Editions 'Reapply' $null }
        } catch { Write-Warning $_.Exception.Message }
    }
}

function global:Show-PVColors([string[]]$Editions) {
    while ($true) {
        try { $palette = Get-PVPalette $PSVersionTable.PSEdition } catch { Write-Warning $_.Exception.Message; return }
        $choice = Read-PVChoice 'Windows Terminal colors' @('Void preset', 'Ocean preset', 'Monochrome preset', 'Edit one color', 'Show current colors', 'Back')
        if ($choice -lt 0 -or $choice -eq 5) { return }
        try {
            if ($choice -lt 3) { Set-PVPalette $Editions 'Preset' (@('Void', 'Ocean', 'Monochrome')[$choice]) }
            elseif ($choice -eq 3) {
                $names = @(Get-PVColorNames)
                $items = @($names | ForEach-Object { "$_ : $($palette[$_])" }) + @('Back')
                $field = Read-PVChoice 'Choose color' $items
                if ($field -ge 0 -and $field -lt $names.Count) {
                    $color = Read-PVText "$($names[$field]) (#RRGGBB; Esc cancels):"
                    if ($color) { Set-PVPalette $Editions $names[$field] $color }
                }
            } elseif ($choice -eq 4) { foreach ($name in (Get-PVColorNames)) { Write-Host ("{0,-13} {1}" -f $name, $palette[$name]) } }
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
            $choice = Read-PVChoice "PowerShell Void Manager | Target: $scope" @('Animations', 'Prompt components', 'Windows Terminal colors', 'Status and maintenance', "Switch target (current/both): $scope", 'Exit')
            if ($choice -lt 0 -or $choice -eq 5) { return }
            switch ($choice) {
                0 { Show-PVAnimations $targets }
                1 { Show-PVPrompt $targets }
                2 { Show-PVColors $targets }
                3 { Show-PVMaintenance }
                4 { $both = -not $both; if ($both -and $targets.Count -eq 1 -and @(Get-PVTargets $true).Count -eq 1) { Write-Host 'Only the current edition is installed.' } }
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
            if ((Test-Path -LiteralPath $template -PathType Leaf) -and (Get-FileHash -LiteralPath $template -Algorithm SHA256).Hash -ne $state.SourceHash) {
                Write-Warning 'PowerShell Void prompt template changed; use psvoid > Prompt components > Reapply to pick up the new template.'
            }
        } catch { Write-Warning $_.Exception.Message }
    }
    Start-PVShortcut
}
