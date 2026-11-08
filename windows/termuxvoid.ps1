#Requires -Version 5.1
<#
.SYNOPSIS
Installs or removes the TermuxVoid prompt for the current Windows PowerShell host.
#>
[CmdletBinding()]
param(
    [switch]$Uninstall,
    [switch]$Update,
    [switch]$SkipDependencyInstall
)

$ErrorActionPreference = 'Stop'
if ($Uninstall -and $Update) { throw 'Choose either -Uninstall or -Update.' }
if ($env:OS -ne 'Windows_NT') {
    throw 'This installer is for Windows. Run it in PowerShell on Windows.'
}

# The two PowerShell editions use different profiles and get separate installations.
$themeBase = Join-Path $HOME '.config\TermuxVoid-Windows'
$themeDir = Join-Path $themeBase $PSVersionTable.PSEdition
$configPath = Join-Path $themeDir 'starship.toml'
$manifestPath = Join-Path $themeDir 'manifest.json'
$installedScript = Join-Path $themeDir 'termuxvoid.ps1'
$profilePath = $PROFILE.CurrentUserCurrentHost
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
    if ($starts.Count -ne 0 -or $ends.Count -ne 0) {
        if ($starts.Count -ne 1 -or $ends.Count -ne 1 -or $blocks.Count -ne 1) {
            throw 'The managed profile block has been edited or duplicated. Remove it manually, then rerun uninstall. No changes made.'
        }
        Backup-Profile
        $offset = $blocks[0]
        $result = [byte[]]::new($profileBytes.Length - $blockBytes.Length)
        [Array]::Copy($profileBytes, 0, $result, 0, $offset)
        $tail = $profileBytes.Length - $offset - $blockBytes.Length
        [Array]::Copy($profileBytes, $offset + $blockBytes.Length, $result, $offset, $tail)
        [System.IO.File]::WriteAllBytes($profilePath, $result)
        Write-Host "Removed managed block from $profilePath"
    } else {
        Write-Host 'No managed profile block found in this host profile.'
    }

    if ($null -ne $manifest) {
        # Only known files whose contents still match the manifest are deleted.
        foreach ($file in @('starship.toml', 'termuxvoid.ps1')) {
            $path = Join-Path $themeDir $file
            if (Test-Path -LiteralPath $path -PathType Leaf) {
                $expected = $manifest.hashes.$file
                if ($expected -and (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -eq $expected) {
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
if (-not (Test-Path -LiteralPath $sourceConfig -PathType Leaf)) {
    throw 'The Windows Starship template is missing. Run the installer from a complete checkout or extracted archive.'
}

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
        if (-not $expected -or -not (Test-Path -LiteralPath $path -PathType Leaf) -or (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash -ne $expected) {
            throw "Installed file is missing or modified: $path. Back up your changes and resolve this before updating. No changes made."
        }
    }
} else {
    if ($starts.Count -ne 0 -or $ends.Count -ne 0) {
        throw 'TermuxVoid markers already exist in this profile. Use -Update or resolve them before installing.'
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

Write-Host "$(if ($Update) { 'Updating' } else { 'Installing' }) for $($PSVersionTable.PSEdition) into $themeDir"
if ($Update) {
    $backupDir = Join-Path $themeBase ('backups\update-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    foreach ($file in @('starship.toml', 'termuxvoid.ps1', 'manifest.json')) {
        Copy-Item -LiteralPath (Join-Path $themeDir $file) -Destination (Join-Path $backupDir $file)
    }
    Write-Host "Previous installation backed up to $backupDir"
    try {
        Copy-Item -LiteralPath $sourceConfig -Destination $configPath -Force
        Copy-Item -LiteralPath $PSCommandPath -Destination $installedScript -Force
        $manifest = @{
            profilePath = $profilePath
            hashes = @{
                'starship.toml' = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
                'termuxvoid.ps1' = (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash
            }
        }
        [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-Warning "Update failed. Restore the three files from $backupDir before retrying."
        throw
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
    $manifest = @{
        profilePath = $profilePath
        hashes = @{
            'starship.toml' = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
            'termuxvoid.ps1' = (Get-FileHash -LiteralPath $installedScript -Algorithm SHA256).Hash
        }
    }
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
    $combined = [byte[]]::new($profileBytes.Length + $blockBytes.Length)
    [Array]::Copy($profileBytes, 0, $combined, 0, $profileBytes.Length)
    [Array]::Copy($blockBytes, 0, $combined, $profileBytes.Length, $blockBytes.Length)
    [System.IO.File]::WriteAllBytes($profilePath, $combined)
} catch {
    Write-Warning "Installation failed. Check the profile and backup before retrying; installation files may remain in $themeDir."
    throw
}
Write-Host 'Installation complete. Restart Windows Terminal to refresh PATH and load the prompt. See windows/README.md for colors and uninstall.'
