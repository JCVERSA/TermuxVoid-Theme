#Requires -Version 5.1
param([string]$Starship)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$installer = Join-Path $root 'windows\termuxvoid.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('PowerShellVoid-manager-test-' + [guid]::NewGuid().ToString('N'))
$oldConfig = $env:STARSHIP_CONFIG
$oldNoAnimation = $env:TERMUXVOID_NO_ANIMATION
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $base = Join-Path $testRoot '.config\TermuxVoid-Windows'
    $profile = Join-Path $testRoot 'Profile\profile.ps1'
    $paths = @{ TestHome = $testRoot; TestProfile = $profile }
    & $installer @paths -SkipDependencyInstall -TerminalProfile
    $current = $PSVersionTable.PSEdition
    $other = if ($current -eq 'Core') { 'Desktop' } else { 'Core' }
    Copy-Item -LiteralPath (Join-Path $base $current) -Destination (Join-Path $base $other) -Recurse
    # The simulated other edition has not opted into a Terminal fragment yet.
    $otherManifestPath = Join-Path (Join-Path $base $other) 'manifest.json'
    $otherManifest = Get-Content -LiteralPath $otherManifestPath -Raw | ConvertFrom-Json
    $otherManifest.PSObject.Properties.Remove('terminalFragmentHash')
    [System.IO.File]::WriteAllText($otherManifestPath, ($otherManifest | ConvertTo-Json -Depth 8))
    $env:TERMUXVOID_NO_ANIMATION = '1'
    . (Join-Path $root 'windows\animation.ps1')
    . (Join-Path $root 'windows\manager.ps1')
    $hashFixture = Join-Path $testRoot 'hash-fixture.txt'
    [System.IO.File]::WriteAllText($hashFixture, 'abc', [System.Text.UTF8Encoding]::new($false))
    Assert ((Get-PVFileHash $hashFixture) -eq 'BA7816BF8F01CFEA414140DE5DAE2223B00361A396177A9CB410FF61F20015AD') 'manager SHA-256 matches known vector'
    function global:Get-PVPaths([string]$Edition) {
        $theme = Join-Path $base $Edition
        return @{
            Base = $base; Theme = $theme; Manifest = (Join-Path $theme 'manifest.json')
            Prompt = (Join-Path $base "prompt-$Edition.toml"); PromptSettings = (Join-Path $base "prompt-settings-$Edition.json")
            AnimationSettings = (Join-Path $base "animation-settings-$Edition.json")
            SuggestionSettings = (Join-Path $base "suggestion-settings-$Edition.json")
            Fragment = (Join-Path $testRoot "LocalAppData\Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme\$Edition.json")
        }
    }
    Assert ([Math]::Abs((Get-PVContrast '#FFFFFF' '#000000') - 21) -lt 0.001) 'contrast black/white known vector'
    Assert ([Math]::Abs((Get-PVContrast '#123456' '#123456') - 1) -lt 0.001) 'contrast identical colors known vector'
    $mono = Get-PVUpdatedPalette (Get-PVPalette $current) 'Preset' 'Monochrome' $current
    foreach ($name in (Get-PVColorNames)) {
        $hex = $mono[$name]
        Assert ($hex.Substring(1, 2) -eq $hex.Substring(3, 2) -and $hex.Substring(3, 2) -eq $hex.Substring(5, 2)) "monochrome $name is grayscale"
    }
    $mockStates = @{ Core = @{ Time = $true }; Desktop = @{ Time = $false } }
    Assert ((Format-PVValues @('Core', 'Desktop') $mockStates 'Time') -eq 'Core: On | Desktop: Off') 'mixed values identify editions'
    Assert ([bool](Get-Command psvoid -ErrorAction SilentlyContinue)) 'manager command registered'
    [string[]]$editions = @(Get-PVTargets $true)
    Assert ($editions.Count -eq 2) 'both installed editions found'
    foreach ($edition in $editions) { Assert ((Get-PVSuggestionState $edition).Enabled) 'history suggestions default on' }
    Set-PVSuggestionState $editions $false
    foreach ($edition in $editions) { Assert (-not (Get-PVSuggestionState $edition).Enabled) 'history suggestions disabled for both editions' }
    Set-PVSuggestionState $editions $true
    foreach ($edition in $editions) { Assert ((Get-PVSuggestionState $edition).Enabled) 'history suggestions enabled for both editions' }

    Set-PVAnimationState $editions 'Idle' $false
    Set-PVAnimationState $editions 'IdleSeconds' 15
    $otherManager = Join-Path (Join-Path $base $other) 'manager.ps1'
    [byte[]]$managerBytes = [System.IO.File]::ReadAllBytes($otherManager)
    Remove-Item -LiteralPath $otherManager
    [byte[]]$currentSettings = [System.IO.File]::ReadAllBytes((Get-PVPaths $current).AnimationSettings)
    $failed = $false
    try { Set-PVAnimationState $editions 'Banner' $false } catch { $failed = $true }
    Assert $failed 'incompatible other edition blocks cross-edition changes'
    Assert ([Convert]::ToBase64String($currentSettings) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Get-PVPaths $current).AnimationSettings))) 'incompatible target leaves current settings unchanged'
    [System.IO.File]::WriteAllBytes($otherManager, $managerBytes)
    foreach ($edition in $editions) {
        $state = Get-PVAnimationState $edition
        Assert (-not $state.Idle -and $state.IdleSeconds -eq 15 -and $state.Welcome -and $state.Banner) 'animation changes preserve other settings in both editions'
    }
    Set-PVPromptState $editions 'Time' $false
    Set-PVPromptState $editions 'DirectoryColor' '#123ABC'
    Set-PVPromptState $editions 'Git' $false
    foreach ($edition in $editions) {
        $source = [System.IO.File]::ReadAllText((Get-PVPaths $edition).Prompt)
        $format = [regex]::Match($source, '(?s)format = """(.*?)"""').Groups[1].Value
        Assert (-not $format.Contains('$git_branch') -and -not $format.Contains('$git_status')) 'git toggle removes both prompt tokens'
    }
    Set-PVPromptState $editions 'Git' $true
    foreach ($edition in $editions) {
        $testPaths = Get-PVPaths $edition
        $state = Get-PVPromptState $edition
        $content = [System.IO.File]::ReadAllText($testPaths.Prompt)
        Assert (-not $state.Time -and $state.DirectoryColor -eq '#123ABC') 'prompt settings saved'
        Assert (-not $content.Contains('$time\' + "`n")) 'time removed from prompt format'
        Assert ($content.Contains('bold #123ABC')) 'custom directory color applied'
        Assert ((Get-FileHash -LiteralPath (Join-Path $testPaths.Theme 'starship.toml') -Algorithm SHA256).Hash -eq (Get-PVManifest $edition).hashes.'starship.toml') 'owned template untouched'
    }
    if ($Starship) {
        $env:STARSHIP_CONFIG = (Get-PVPaths $current).Prompt
        $render = (& $Starship prompt --status 0 --terminal-width 120) -join ''
        Assert ($LASTEXITCODE -eq 0 -and $render) 'Starship renders generated prompt'
        Assert (-not ($render -match '\d\d:\d\d:\d\d')) 'time toggle affects real rendering'
    }
    $otherPrompt = (Get-PVPaths $other).Prompt
    [byte[]]$otherBytes = [System.IO.File]::ReadAllBytes($otherPrompt)
    $currentPrompt = (Get-PVPaths $current).Prompt
    [byte[]]$currentBytes = [System.IO.File]::ReadAllBytes($currentPrompt)
    Add-Content -LiteralPath $currentPrompt -Value '# edited by user'
    $failed = $false
    try { Set-PVPromptState $editions 'Git' $false } catch { $failed = $true }
    Assert $failed 'edited generated prompt blocks changes'
    Assert ([Convert]::ToBase64String($otherBytes) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($otherPrompt))) 'both-edition preflight preserves other prompt on conflict'
    [System.IO.File]::WriteAllBytes($currentPrompt, $currentBytes)

    Set-PVPalette $editions 'background' '#123456'
    foreach ($edition in $editions) {
        $testPaths = Get-PVPaths $edition
        $fragment = Get-Content -LiteralPath $testPaths.Fragment -Raw | ConvertFrom-Json
        $manifest = Get-PVManifest $edition
        Assert ($fragment.schemes[0].background -eq '#123456') 'custom terminal color applied'
        Assert ((Get-FileHash -LiteralPath $testPaths.Fragment -Algorithm SHA256).Hash -eq $manifest.terminalFragmentHash) 'fragment ownership hash updated'
    }
    $currentFragment = (Get-PVPaths $current).Fragment
    [byte[]]$before = [System.IO.File]::ReadAllBytes($currentFragment)
    Add-Content -LiteralPath $currentFragment -Value ' '
    [byte[]]$otherBefore = [System.IO.File]::ReadAllBytes((Get-PVPaths $other).Fragment)
    $failed = $false
    try { Set-PVPalette $editions 'Preset' 'Ocean' } catch { $failed = $true }
    Assert $failed 'modified fragment blocks palette changes'
    Assert ([Convert]::ToBase64String($otherBefore) -ceq [Convert]::ToBase64String([System.IO.File]::ReadAllBytes((Get-PVPaths $other).Fragment))) 'palette preflight prevents changes to other edition'
    [System.IO.File]::WriteAllBytes($currentFragment, $before)
    & $installer @paths -Update -SkipDependencyInstall
    $fragment = Get-Content -LiteralPath $currentFragment -Raw | ConvertFrom-Json
    Assert ($fragment.schemes[0].background -eq '#123456') 'palette survives guarded update'
    & $installer @paths -Uninstall
    Assert (Test-Path -LiteralPath $currentPrompt) 'user prompt retained after uninstall'
    $savedFragments = @(Get-ChildItem -LiteralPath (Join-Path $base 'backups') -Recurse -Filter 'terminal-fragment.json')
    Assert ($savedFragments.Count -ge 1) 'customized Terminal profile backed up on uninstall'
    $savedFragment = Get-Content -LiteralPath $savedFragments[-1].FullName -Raw | ConvertFrom-Json
    Assert ($savedFragment.schemes[0].background -eq '#123456') 'uninstall backup preserves custom terminal color'
    Write-Host 'PASS: manager settings, cross-edition safeguards, colors, and update'
} finally {
    $env:STARSHIP_CONFIG = $oldConfig
    $env:TERMUXVOID_NO_ANIMATION = $oldNoAnimation
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
