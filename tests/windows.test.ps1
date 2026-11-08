#Requires -Version 5.1
# Run in a disposable PowerShell process on Windows: powershell -NoProfile -File tests/windows.test.ps1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'These integration tests require Windows.' }
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\termuxvoid.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("TermuxVoid-test-" + [guid]::NewGuid().ToString('N'))
$originalHome = $HOME
$originalProfile = $PROFILE
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function BytesEqual([byte[]]$A, [byte[]]$B) {
    return [Convert]::ToBase64String($A) -ceq [Convert]::ToBase64String($B)
}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $HOME = $testRoot
    $profilePath = Join-Path $testRoot 'Profile With Spaces\Microsoft.PowerShell_profile.ps1'
    $PROFILE = [pscustomobject]@{ CurrentUserCurrentHost = $profilePath }
    New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
    $themeDir = Join-Path $testRoot ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition)

    foreach ($encoding in @([System.Text.UTF8Encoding]::new($true), [System.Text.UnicodeEncoding]::new($false, $true))) {
        [System.IO.File]::WriteAllText($profilePath, ("# Existing profile {0}`r`n`$value = 42" -f [char]0x00e9), $encoding)
        [byte[]]$original = [System.IO.File]::ReadAllBytes($profilePath)
        & $installer -Name 'Test User'
        Assert (Test-Path -LiteralPath (Join-Path $themeDir 'starship.toml')) 'config installed'
        Assert ((Get-Content -LiteralPath (Join-Path $themeDir 'starship.toml') -Raw).Contains('[Test User]')) 'custom name inserted'
        $failed = $false
        try { & $installer } catch { $failed = $true }
        Assert $failed 'second install must refuse to overwrite'
        # Add user content after installation; uninstall must preserve it and the original bytes.
        [byte[]]$suffix = $encoding.GetBytes("# Later user change`r`n")
        [byte[]]$current = [System.IO.File]::ReadAllBytes($profilePath)
        [byte[]]$extended = [byte[]]::new($current.Length + $suffix.Length)
        [Array]::Copy($current, 0, $extended, 0, $current.Length)
        [Array]::Copy($suffix, 0, $extended, $current.Length, $suffix.Length)
        [System.IO.File]::WriteAllBytes($profilePath, $extended)
        & $installer -Uninstall
        [byte[]]$expected = [byte[]]::new($original.Length + $suffix.Length)
        [Array]::Copy($original, 0, $expected, 0, $original.Length)
        [Array]::Copy($suffix, 0, $expected, $original.Length, $suffix.Length)
        Assert (BytesEqual $expected ([System.IO.File]::ReadAllBytes($profilePath))) 'original and later profile bytes preserved'
        Assert (-not (Test-Path -LiteralPath $themeDir)) 'unmodified managed files removed'
    }

    # A fresh profile and an invalid label must not affect existing files unexpectedly.
    Remove-Item -LiteralPath $profilePath
    $failed = $false
    try { & $installer -Name 'Bad]Name' } catch { $failed = $true }
    Assert $failed 'invalid name must be rejected'
    Assert (-not (Test-Path -LiteralPath $themeDir)) 'invalid name must not create an installation'
    & $installer
    Assert (Test-Path -LiteralPath $profilePath) 'missing profile created'
    & $installer -Uninstall
    Assert (([System.IO.File]::ReadAllBytes($profilePath)).Length -eq 0) 'new profile left empty after uninstall'

    # Keep changes to the generated config and refuse to remove an edited managed block.
    [System.IO.File]::WriteAllText($profilePath, '# Original', [System.Text.UTF8Encoding]::new($false))
    & $installer
    $PROFILE = [pscustomobject]@{ CurrentUserCurrentHost = (Join-Path $testRoot 'OtherHost\profile.ps1') }
    $failed = $false
    try { & $installer -Uninstall } catch { $failed = $true }
    Assert $failed 'uninstall from a different host must fail'
    $PROFILE = [pscustomobject]@{ CurrentUserCurrentHost = $profilePath }
    Add-Content -LiteralPath (Join-Path $themeDir 'starship.toml') -Value '# User edit'
    $profile = [System.IO.File]::ReadAllText($profilePath).Replace('Remove-Variable termuxVoidConfig', 'Remove-Variable changedConfig')
    [System.IO.File]::WriteAllText($profilePath, $profile, [System.Text.UTF8Encoding]::new($false))
    $failed = $false
    try { & $installer -Uninstall } catch { $failed = $true }
    Assert $failed 'edited managed block must not be removed automatically'
    Assert (Test-Path -LiteralPath (Join-Path $themeDir 'starship.toml')) 'config retained after blocked uninstall'
    $profile = $profile.Replace('Remove-Variable changedConfig', 'Remove-Variable termuxVoidConfig')
    [System.IO.File]::WriteAllText($profilePath, $profile, [System.Text.UTF8Encoding]::new($false))
    & $installer -Uninstall
    Assert (Test-Path -LiteralPath (Join-Path $themeDir 'starship.toml')) 'modified config retained on uninstall'
    Assert ((Get-ChildItem -LiteralPath (Join-Path $testRoot '.config\TermuxVoid-Windows\backups')).Count -ge 1) 'backups created'
    Write-Host 'PASS: Windows installer integration tests'
} finally {
    $HOME = $originalHome
    $PROFILE = $originalProfile
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
