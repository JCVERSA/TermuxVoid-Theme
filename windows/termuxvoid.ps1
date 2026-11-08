#Requires -Version 5.1
<#
.SYNOPSIS
Installs or removes the PowerShell Void prompt for the current Windows PowerShell host.
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Update,
    [switch]$SkipDependencyInstall,
    [switch]$TerminalProfile,
    [switch]$SkipTerminalProfile,
    # Test-only paths. The generated profile is intended for the real user's HOME.
    [Parameter(DontShow)] [string]$TestHome,
    [Parameter(DontShow)] [string]$TestProfile,
    [Parameter(DontShow)] [switch]$TestRunAnimationSetup,
    [Parameter(DontShow)] [switch]$TestRunSuggestionSetup
)

$ErrorActionPreference = 'Stop'
if ($Uninstall -and $Update) { throw 'Choose either -Uninstall or -Update.' }
if ($TerminalProfile -and $SkipTerminalProfile) { throw 'Choose either -TerminalProfile or -SkipTerminalProfile.' }
if ($env:OS -ne 'Windows_NT') {
    throw 'This installer is for Windows. Run it in PowerShell on Windows.'
}

# The two PowerShell editions use different profiles and get separate installations.
if ([bool]$TestHome -ne [bool]$TestProfile) { throw 'Both test paths must be provided together.' }
$homeDir = if ($TestHome) { $TestHome } else { $HOME }
$profilePath = if ($TestProfile) { $TestProfile } else { $PROFILE.CurrentUserCurrentHost }
if (-not $profilePath) { throw 'The current host profile is unavailable. Run this in a PowerShell host with a user profile.' }
$themeBase = Join-Path $homeDir '.config\TermuxVoid-Windows'
$themeDir = Join-Path $themeBase $PSVersionTable.PSEdition
$configPath = Join-Path $themeDir 'starship.toml'
$manifestPath = Join-Path $themeDir 'manifest.json'
$installedScript = Join-Path $themeDir 'termuxvoid.ps1'
# A separate Windows Terminal fragment avoids rewriting the user's settings.json.
$localAppData = if ($TestHome) { Join-Path $TestHome 'LocalAppData' } else { $env:LOCALAPPDATA }
$fragmentDir = if ($localAppData) { Join-Path $localAppData 'Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme' } else { $null }
$fragmentPath = if ($fragmentDir) { Join-Path $fragmentDir ($PSVersionTable.PSEdition + '.json') } else { $null }
$startMarker = '# >>> TermuxVoid Windows >>>'
$endMarker = '# <<< TermuxVoid Windows <<<'

# ASCII only: the block can be appended without re-encoding existing profile bytes.
$block = @'
# >>> TermuxVoid Windows >>>
$termuxVoidConfig = Join-Path $HOME ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition + '\starship.toml')
if ((Test-Path -LiteralPath $termuxVoidConfig) -and (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue)) {
    $env:STARSHIP_CONFIG = $termuxVoidConfig
    Invoke-Expression (& starship init powershell | Out-String)
}
Remove-Variable termuxVoidConfig -ErrorAction SilentlyContinue
# <<< TermuxVoid Windows <<<
'@
$block = "`r`n" + (($block -split "`r?`n") -join "`r`n") + "`r`n"

$animationStart = '# >>> TermuxVoid Animations >>>'
$animationEnd = '# <<< TermuxVoid Animations <<<'
$animationBlock = @'
# >>> TermuxVoid Animations >>>
$termuxVoidAnimation = Join-Path $HOME ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition + '\animation.ps1')
if (Test-Path -LiteralPath $termuxVoidAnimation) { . $termuxVoidAnimation }
Remove-Variable termuxVoidAnimation -ErrorAction SilentlyContinue
# <<< TermuxVoid Animations <<<
'@
$animationBlock = "`r`n" + (($animationBlock -split "`r?`n") -join "`r`n") + "`r`n"

function Get-TVFileHash([string]$Path) {
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

function Get-ProfileEncoding([byte[]]$Bytes) {
    # BOMs are inspected before UTF-16 because UTF-32 LE starts with the same bytes.
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe -and $Bytes[2] -eq 0 -and $Bytes[3] -eq 0) { return [System.Text.Encoding]::UTF32 }
    if ($Bytes.Length -ge 4 -and $Bytes[0] -eq 0 -and $Bytes[1] -eq 0 -and $Bytes[2] -eq 0xfe -and $Bytes[3] -eq 0xff) { return [System.Text.UTF32Encoding]::new($true, $true) }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xff -and $Bytes[1] -eq 0xfe) { return [System.Text.Encoding]::Unicode }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xfe -and $Bytes[1] -eq 0xff) { return [System.Text.Encoding]::BigEndianUnicode }
    # For UTF-8 and Windows ANSI profiles, the managed block is ASCII.
    if ([Array]::IndexOf($Bytes, [byte]0) -ge 0) { throw 'Profile has an unsupported encoding (possibly UTF-16 without a BOM). No changes made.' }
    return [System.Text.Encoding]::UTF8
}

function Find-Bytes([byte[]]$Bytes, [byte[]]$Needle) {
    $hits = [System.Collections.Generic.List[int]]::new()
    for ($i = 0; $i -le $Bytes.Length - $Needle.Length; $i++) {
        $match = $true
        for ($j = 0; $j -lt $Needle.Length; $j++) {
            if ($Bytes[$i + $j] -ne $Needle[$j]) { $match = $false; break }
        }
        if ($match) { $hits.Add($i) }
    }
    return ,$hits.ToArray()
}

function Backup-Profile {
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $backupDir = Join-Path $themeBase 'backups'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $backup = Join-Path $backupDir ("profile-{0}-{1}.ps1" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), [guid]::NewGuid().ToString('N'))
        Copy-Item -LiteralPath $profilePath -Destination $backup
        Write-Host "Profile backup: $backup"
    }
}


function Save-TerminalProfile($Manifest, $PreviousHash) {
    if (-not $fragmentPath) { throw 'LOCALAPPDATA is unavailable; cannot create a Terminal profile.' }
    $schemeFile = Join-Path $PSScriptRoot 'termuxvoid-scheme.json'
    if (-not (Test-Path -LiteralPath $schemeFile -PathType Leaf)) { throw 'Windows Terminal color scheme is missing.' }
    if (Test-Path -LiteralPath $fragmentPath) {
        if (-not $PreviousHash -or (Get-TVFileHash $fragmentPath) -ne $PreviousHash) {
            throw "A modified or unowned fragment already exists: $fragmentPath. It was not overwritten."
        }
        $backupDir = Join-Path $themeBase ('backups\terminal-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Copy-Item -LiteralPath $fragmentPath -Destination (Join-Path $backupDir 'fragment.json')
        Write-Host "Terminal fragment backup: $backupDir"
    }
    $scheme = Get-Content -LiteralPath $schemeFile -Raw | ConvertFrom-Json
    if ($Manifest.terminalColors) {
        foreach ($property in $scheme.PSObject.Properties) {
            if ($property.Name -eq 'name') { continue }
            $value = $Manifest.terminalColors.($property.Name)
            if ($value -notmatch '^#[0-9a-fA-F]{6}$') { throw "Invalid saved Terminal color: $($property.Name)." }
            $property.Value = $value
        }
    }
    $scheme.name = 'PowerShell Void ' + $PSVersionTable.PSEdition
    $powerShellPath = (Get-Process -Id $PID).Path
    if (-not $powerShellPath) { throw 'Cannot find the current PowerShell executable.' }
    $profileGuid = if ($PSVersionTable.PSEdition -eq 'Core') { '{c04eb7b9-0a8d-4fc1-a6c6-dd5b94effd81}' } else { '{b29cc26a-e530-4639-a25b-34e13e5cd7b2}' }
    $label = if ($PSVersionTable.PSEdition -eq 'Core') { 'PowerShell Void 7' } else { 'PowerShell Void Windows PowerShell' }
    $profile = @{ name = $label; guid = $profileGuid; commandline = '"' + $powerShellPath + '"'; colorScheme = $scheme.name }
    $fragment = @{ profiles = @($profile); schemes = @($scheme) } | ConvertTo-Json -Depth 8
    New-Item -ItemType Directory -Path $fragmentDir -Force | Out-Null
    [System.IO.File]::WriteAllText($fragmentPath, $fragment, [System.Text.UTF8Encoding]::new($false))
    $Manifest.terminalFragmentHash = (Get-TVFileHash $fragmentPath)
    [System.IO.File]::WriteAllText($manifestPath, ($Manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    Write-Host "Added Windows Terminal profile '$label'. Select it from Terminal's profile menu after restarting."
    Write-Host 'The matching Nerd Font is optional; see the Windows guide for installation and licensing notes.'
}

function Should-CreateTerminalProfile($PreviousHash) {
    if ($SkipTerminalProfile) { return $false }
    if ($TerminalProfile -or $PreviousHash) { return $true }
    # Automated integration tests run non-interactively against isolated paths.
    if ($TestHome) { return $false }
    $answer = Read-Host 'Add a separate PowerShell Void Windows Terminal profile with matching colors? [y/N]'
    return $answer -match '^(y|yes)$'
}

[byte[]]$profileBytes = @()
if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
    $profileBytes = [System.IO.File]::ReadAllBytes($profilePath)
} elseif (Test-Path -LiteralPath $profilePath) {
    throw "Profile path is not a file: $profilePath"
}
$encoding = Get-ProfileEncoding $profileBytes
[byte[]]$blockBytes = $encoding.GetBytes($block)
$starts = Find-Bytes $profileBytes ($encoding.GetBytes($startMarker))
$ends = Find-Bytes $profileBytes ($encoding.GetBytes($endMarker))
$blocks = Find-Bytes $profileBytes $blockBytes

[byte[]]$animationBlockBytes = $encoding.GetBytes($animationBlock)
$animationStarts = Find-Bytes $profileBytes ($encoding.GetBytes($animationStart))
$animationEnds = Find-Bytes $profileBytes ($encoding.GetBytes($animationEnd))
$animationBlocks = Find-Bytes $profileBytes $animationBlockBytes
if (($animationStarts.Count -ne 0 -or $animationEnds.Count -ne 0) -and
    ($animationStarts.Count -ne 1 -or $animationEnds.Count -ne 1 -or $animationBlocks.Count -ne 1)) {
    throw 'The animation profile block was edited or duplicated. Resolve it manually before continuing. No changes made.'
}

if ($Uninstall) {
    $manifest = $null
    if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
        try { $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
        catch { throw "Cannot read $manifestPath. No changes made." }
        if (-not $manifest.profilePath -or $manifest.profilePath -ne $profilePath -or -not $manifest.hashes) {
            throw "Installation belongs to another profile or has an invalid manifest: $manifestPath. No changes made."
        }
    } elseif (Test-Path -LiteralPath $themeDir) {
        throw "No installation manifest found in $themeDir. No changes made."
    }
    if (($starts.Count -ne 0 -or $ends.Count -ne 0) -and
        ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $blocks.Count -ne 1)) {
        throw 'The managed profile block has been edited or duplicated. Remove it manually, then rerun uninstall. No changes made.'
    }
    # Preserve a manager-customized Terminal profile as user data before removal.
    if ($manifest -and $manifest.terminalColors -and $manifest.terminalFragmentHash -and $fragmentPath -and
        (Test-Path -LiteralPath $fragmentPath -PathType Leaf) -and
        (Get-TVFileHash $fragmentPath) -eq $manifest.terminalFragmentHash) {
        $colorBackup = Join-Path $themeBase ('backups\terminal-uninstall-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $colorBackup -Force | Out-Null
        Copy-Item -LiteralPath $fragmentPath -Destination (Join-Path $colorBackup 'terminal-fragment.json')
        Copy-Item -LiteralPath $manifestPath -Destination (Join-Path $colorBackup 'manifest.json')
        Write-Host "Customized Terminal profile backup: $colorBackup"
    }
    $removals = @()
    if ($blocks.Count -eq 1) { $removals += @{ Offset = $blocks[0]; Length = $blockBytes.Length } }
    if ($animationBlocks.Count -eq 1) { $removals += @{ Offset = $animationBlocks[0]; Length = $animationBlockBytes.Length } }
    if ($removals.Count -gt 0) {
        Backup-Profile
        foreach ($item in ($removals | Sort-Object Offset -Descending)) {
            $result = [byte[]]::new($profileBytes.Length - $item.Length)
            [Array]::Copy($profileBytes, 0, $result, 0, $item.Offset)
            $tail = $profileBytes.Length - $item.Offset - $item.Length
            [Array]::Copy($profileBytes, $item.Offset + $item.Length, $result, $item.Offset, $tail)
            $profileBytes = $result
        }
        [System.IO.File]::WriteAllBytes($profilePath, $profileBytes)
        Write-Host "Removed managed blocks from $profilePath"
    } else {
        Write-Host 'No managed profile blocks found in this host profile.'
    }

    if ($null -ne $manifest) {
        if ($manifest.terminalFragmentHash -and $fragmentPath -and (Test-Path -LiteralPath $fragmentPath -PathType Leaf)) {
            if ((Get-TVFileHash $fragmentPath) -eq $manifest.terminalFragmentHash) {
                Remove-Item -LiteralPath $fragmentPath
                Write-Host 'Removed the unchanged Windows Terminal fragment.'
            } else {
                Write-Warning "Retained modified Windows Terminal fragment: $fragmentPath"
            }
        } elseif ($manifest.terminalFragmentHash -and -not $fragmentPath) {
            Write-Warning 'LOCALAPPDATA is unavailable; the Windows Terminal fragment was retained.'
        }
        # Only known files whose contents still match the manifest are deleted.
        foreach ($file in @('starship.toml', 'termuxvoid.ps1', 'animation.ps1', 'animation-demo.py', 'animation-setup.ps1', 'manager.ps1', 'termuxvoid-scheme.json')) {
            $path = Join-Path $themeDir $file
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $expected = $manifest.hashes.$file
                if ($expected -and (Get-TVFileHash $path) -eq $expected) {
                    Remove-Item -LiteralPath $path
                } else {
                    Write-Warning "Retained modified file: $path"
                }
            }
        }
        Remove-Item -LiteralPath $manifestPath
        if ((Get-ChildItem -LiteralPath $themeDir -Force | Measure-Object).Count -eq 0) {
            Remove-Item -LiteralPath $themeDir
        } else {
            Write-Warning "Retained remaining files in $themeDir"
        }
    } elseif (Test-Path -LiteralPath $themeDir) {
        Write-Warning "No installation manifest found; files in $themeDir were retained."
    }
    Write-Host 'Uninstall complete. Backups, dependencies, fonts, and Windows Terminal settings are not removed.'
    return
}

$sourceConfig = Join-Path $PSScriptRoot 'starship.toml'
$sourceAnimation = Join-Path $PSScriptRoot 'animation.ps1'
$sourceDemo = Join-Path $PSScriptRoot 'animation-demo.py'
$sourceSetup = Join-Path $PSScriptRoot 'animation-setup.ps1'
$sourceManager = Join-Path $PSScriptRoot 'manager.ps1'
$sourceScheme = Join-Path $PSScriptRoot 'termuxvoid-scheme.json'
if (-not (Test-Path -LiteralPath $sourceConfig -PathType Leaf)) {
    throw 'The Windows Starship template is missing. Run the installer from a complete checkout or extracted archive.'
}

if (-not (Test-Path -LiteralPath $sourceAnimation -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceDemo -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceSetup -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceManager -PathType Leaf) -or -not (Test-Path -LiteralPath $sourceScheme -PathType Leaf)) { throw 'Manager or animation files are missing from the installer source.' }

if ($Update) {
    if ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $blocks.Count -ne 1) {
        throw 'The original managed profile block is missing, edited, or duplicated. Resolve it before updating. No changes made.'
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'No installation manifest found. Cannot safely update.'
    }
    try { $oldManifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json }
    catch { throw "Cannot read $manifestPath. No changes made." }
    if (-not $oldManifest.profilePath -or $oldManifest.profilePath -ne $profilePath -or -not $oldManifest.hashes) {
        throw 'The installation belongs to another profile or has an invalid manifest. No changes made.'
    }
    foreach ($file in @('starship.toml', 'termuxvoid.ps1')) {
        $path = Join-Path $themeDir $file
        $expected = $oldManifest.hashes.$file
        if (-not $expected -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-TVFileHash $path) -ne $expected) {
            throw "Installed file is missing or modified: $path. Back up your changes and resolve this before updating. No changes made."
        }
    }
    foreach ($file in @('animation.ps1', 'animation-demo.py', 'animation-setup.ps1', 'manager.ps1', 'termuxvoid-scheme.json')) {
        $path = Join-Path $themeDir $file
        $expected = $oldManifest.hashes.$file
        if ($expected -and (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-TVFileHash $path) -ne $expected)) {
            throw "Installed animation file is missing or modified: $path. No changes made."
        }
        if (-not $expected -and (Test-Path -LiteralPath $path)) { throw "Unowned animation file exists: $path. No changes made." }
    }
} else {
    if ($starts.Count -ne 0 -or $ends.Count -ne 0 -or $animationStarts.Count -ne 0 -or $animationEnds.Count -ne 0) {
        throw 'PowerShell Void legacy TermuxVoid markers already exist in this profile. Use -Update or resolve them before installing.'
    }
    if (Test-Path -LiteralPath $themeDir) {
        throw "Installation directory already exists: $themeDir. No files were overwritten."
    }
}

# Starship is the only mandatory external executable. The portable WinGet package
# installs per-user; do not silently upgrade or install Git or other tools.
if (-not (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue)) {
    if ($SkipDependencyInstall) {
        Write-Warning 'Starship is not on PATH. The prompt will activate after Starship is installed and PowerShell is restarted.'
    } else {
        $winget = Get-Command winget -CommandType Application -ErrorAction SilentlyContinue
        if (-not $winget) { throw 'Starship is missing and WinGet is unavailable. Install Starship or WinGet, then retry. No theme files changed.' }
        Write-Host 'Installing Starship with WinGet (per-user portable package)...'
        & $winget.Source install --id Starship.Starship --exact --source winget --scope user --installer-type portable --accept-package-agreements --accept-source-agreements --disable-interactivity
        if ($LASTEXITCODE -ne 0) { throw "WinGet failed to install Starship (exit code $LASTEXITCODE). No theme files changed." }
        if (-not (Get-Command starship -CommandType Application -ErrorAction SilentlyContinue)) {
            Write-Warning 'Starship is not yet on this session PATH. Restart Windows Terminal after installation to refresh PATH.'
        }
    }
}

# PSReadLine owns command history; install a compatible version only if needed.
# This happens during setup, never during profile startup. It affects the current
# user's PowerShell modules and is retained on uninstall.
if (-not $SkipDependencyInstall -and (-not $TestHome -or $TestRunSuggestionSetup)) {
    try {
        $compatible = @(Get-Module -ListAvailable PSReadLine | Where-Object { $_.Version -ge [version]'2.1.0' })
        if ($compatible.Count -eq 0) {
            Write-Host 'Installing PSReadLine 2.3.6 for history suggestions (current user, PowerShell Gallery)...'
            Install-Module -Name PSReadLine -RequiredVersion '2.3.6' -Scope CurrentUser -Repository PSGallery -AllowClobber -Force -ErrorAction Stop
        }
    } catch {
        Write-Warning "Could not install PSReadLine for history suggestions: $($_.Exception.Message). Install PSReadLine 2.3.6 for the current user and restart PowerShell. Theme setup will continue."
    }
}

# Setup is explicit here, never on profile startup. Tests isolate dependency setup separately.
if (-not $SkipDependencyInstall -and (-not $TestHome -or $TestRunAnimationSetup)) {
    & $sourceSetup -Base $themeBase
}

Write-Host "$(if ($Update) { 'Updating' } else { 'Installing' }) for $($PSVersionTable.PSEdition) into $themeDir"
if ($Update) {
    $backupDir = Join-Path $themeBase ('backups\update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach ($file in @('starship.toml', 'termuxvoid.ps1', 'manifest.json')) {
        Copy-Item -LiteralPath (Join-Path $themeDir $file) -Destination (Join-Path $backupDir $file)
    }
    foreach ($file in @('animation.ps1', 'animation-demo.py', 'animation-setup.ps1', 'manager.ps1', 'termuxvoid-scheme.json')) {
        $path = Join-Path $themeDir $file
        if (Test-Path -LiteralPath $path -PathType Leaf) { Copy-Item -LiteralPath $path -Destination (Join-Path $backupDir $file) }
    }
    if ($animationBlocks.Count -eq 0) { Backup-Profile }
    Write-Host "Previous installation backed up to $backupDir"
    try {
        Copy-Item -LiteralPath $sourceConfig -Destination $configPath -Force
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
        Copy-Item -LiteralPath $sourceAnimation -Destination (Join-Path $themeDir 'animation.ps1') -Force
        Copy-Item -LiteralPath $sourceDemo -Destination (Join-Path $themeDir 'animation-demo.py') -Force
        Copy-Item -LiteralPath $sourceSetup -Destination (Join-Path $themeDir 'animation-setup.ps1') -Force
        Copy-Item -LiteralPath $sourceManager -Destination (Join-Path $themeDir 'manager.ps1') -Force
        Copy-Item -LiteralPath $sourceScheme -Destination (Join-Path $themeDir 'termuxvoid-scheme.json') -Force
        $manifest = @{
            profilePath = $profilePath
            hashes = @{
                'starship.toml' = (Get-TVFileHash $configPath)
                'termuxvoid.ps1' = (Get-TVFileHash $installedScript)
                'animation.ps1' = (Get-TVFileHash (Join-Path $themeDir 'animation.ps1'))
                'animation-demo.py' = (Get-TVFileHash (Join-Path $themeDir 'animation-demo.py'))
            'animation-setup.ps1' = (Get-TVFileHash (Join-Path $themeDir 'animation-setup.ps1'))
                'manager.ps1' = (Get-TVFileHash (Join-Path $themeDir 'manager.ps1'))
                'termuxvoid-scheme.json' = (Get-TVFileHash (Join-Path $themeDir 'termuxvoid-scheme.json'))
            }
        }
        if ($oldManifest.terminalFragmentHash) { $manifest.terminalFragmentHash = $oldManifest.terminalFragmentHash }
        if ($oldManifest.terminalColors) { $manifest.terminalColors = $oldManifest.terminalColors }
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
        if ($animationBlocks.Count -eq 0) {
            $combined = [byte[]]::new($profileBytes.Length + $animationBlockBytes.Length)
            [Array]::Copy($profileBytes, 0, $combined, 0, $profileBytes.Length)
            [Array]::Copy($animationBlockBytes, 0, $combined, $profileBytes.Length, $animationBlockBytes.Length)
            [System.IO.File]::WriteAllBytes($profilePath, $combined)
        }
    } catch {
        Write-Warning "Update failed. Restore the files from $backupDir and check the printed profile backup before retrying."
        throw
    }
    if (Should-CreateTerminalProfile $oldManifest.terminalFragmentHash) {
        try { Save-TerminalProfile $manifest $oldManifest.terminalFragmentHash }
        catch { Write-Warning "Terminal profile not changed: $($_.Exception.Message)" }
    }
    Write-Host 'Update complete. Restart Windows Terminal to refresh PATH and load the new prompt.'
    return
}
Write-Host "Adding a managed block to $profilePath"
Backup-Profile
New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
New-Item -ItemType Directory -Path $themeDir -Force | Out-Null
try {
    Copy-Item -LiteralPath $sourceConfig -Destination $configPath
    Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript
    Copy-Item -LiteralPath $sourceAnimation -Destination (Join-Path $themeDir 'animation.ps1')
    Copy-Item -LiteralPath $sourceDemo -Destination (Join-Path $themeDir 'animation-demo.py')
    Copy-Item -LiteralPath $sourceSetup -Destination (Join-Path $themeDir 'animation-setup.ps1')
    Copy-Item -LiteralPath $sourceManager -Destination (Join-Path $themeDir 'manager.ps1')
    Copy-Item -LiteralPath $sourceScheme -Destination (Join-Path $themeDir 'termuxvoid-scheme.json')
    $manifest = @{
        profilePath = $profilePath
        hashes = @{
            'starship.toml' = (Get-TVFileHash $configPath)
            'termuxvoid.ps1' = (Get-TVFileHash $installedScript)
            'animation.ps1' = (Get-TVFileHash (Join-Path $themeDir 'animation.ps1'))
            'animation-demo.py' = (Get-TVFileHash (Join-Path $themeDir 'animation-demo.py'))
            'animation-setup.ps1' = (Get-TVFileHash (Join-Path $themeDir 'animation-setup.ps1'))
                'manager.ps1' = (Get-TVFileHash (Join-Path $themeDir 'manager.ps1'))
                'termuxvoid-scheme.json' = (Get-TVFileHash (Join-Path $themeDir 'termuxvoid-scheme.json'))
        }
    }
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $combined = [byte[]]::new($profileBytes.Length + $blockBytes.Length + $animationBlockBytes.Length)
    [Array]::Copy($profileBytes, 0, $combined, 0, $profileBytes.Length)
    [Array]::Copy($blockBytes, 0, $combined, $profileBytes.Length, $blockBytes.Length)
    [Array]::Copy($animationBlockBytes, 0, $combined, $profileBytes.Length + $blockBytes.Length, $animationBlockBytes.Length)
    [System.IO.File]::WriteAllBytes($profilePath, $combined)
} catch {
    Write-Warning "Installation failed. Check the profile and backup before retrying; installation files may remain in $themeDir."
    throw
}
if (Should-CreateTerminalProfile $null) {
    try { Save-TerminalProfile $manifest $null }
    catch { Write-Warning "Terminal profile not changed: $($_.Exception.Message)" }
}
Write-Host 'Installation complete. Restart Windows Terminal to refresh PATH and load the prompt. See windows/README.md for colors and uninstall.'
