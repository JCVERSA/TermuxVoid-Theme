#Requires -Version 5.1
# Run in a disposable PowerShell process on Windows: powershell -NoProfile -File tests/windows.test.ps1
$ErrorActionPreference = 'Stop'
if ($env:OS -ne 'Windows_NT') { throw 'These integration tests require Windows.' }
$installer = Join-Path (Split-Path -Parent $PSScriptRoot) 'windows\termuxvoid.ps1'
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("TermuxVoid-test-" + [guid]::NewGuid().ToString('N'))
function Assert($Condition, [string]$Message) { if (-not $Condition) { throw "FAIL: $Message" } }
function BytesEqual([byte[]]$A, [byte[]]$B) {
    return [Convert]::ToBase64String($A) -ceq [Convert]::ToBase64String($B)
}
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $profilePath = Join-Path $testRoot 'Profile With Spaces\Microsoft.PowerShell_profile.ps1'
    $testPaths = @{ TestHome = $testRoot; TestProfile = $profilePath }
    New-Item -ItemType Directory -Path (Split-Path -Parent $profilePath) -Force | Out-Null
    $themeDir = Join-Path $testRoot ('.config\TermuxVoid-Windows\' + $PSVersionTable.PSEdition)

    foreach ($encoding in @([System.Text.UTF8Encoding]::new($true), [System.Text.UnicodeEncoding]::new($false, $true))) {
        [System.IO.File]::WriteAllText($profilePath, ("# Existing profile {0}`r`n`$value = 42" -f [char]0x00e9), $encoding)
        [byte[]]$original = [System.IO.File]::ReadAllBytes($profilePath)
        & $installer @testPaths -SkipDependencyInstall
        Assert (Test-Path -LiteralPath (Join-Path $themeDir 'starship.toml')) 'config installed'
        Assert ((Get-Content -LiteralPath (Join-Path $themeDir 'starship.toml') -Raw).Contains('${env_var.USERNAME}')) 'username module configured'
        $failed = $false
        try { & $installer @testPaths -SkipDependencyInstall } catch { $failed = $true }
        Assert $failed 'second install must refuse to overwrite'
        # Add user content after installation; uninstall must preserve it and the original bytes.
        [byte[]]$suffix = $encoding.GetBytes("# Later user change`r`n")
        [byte[]]$current = [System.IO.File]::ReadAllBytes($profilePath)
        [byte[]]$extended = [byte[]]::new($current.Length + $suffix.Length)
        [Array]::Copy($current, 0, $extended, 0, $current.Length)
        [Array]::Copy($suffix, 0, $extended, $current.Length, $suffix.Length)
        [System.IO.File]::WriteAllBytes($profilePath, $extended)
        & $installer @testPaths -Uninstall
        [byte[]]$expected = [byte[]]::new($original.Length + $suffix.Length)
        [Array]::Copy($original, 0, $expected, 0, $original.Length)
        [Array]::Copy($suffix, 0, $expected, $original.Length, $suffix.Length)
        Assert (BytesEqual $expected ([System.IO.File]::ReadAllBytes($profilePath))) 'original and later profile bytes preserved'
        Assert (-not (Test-Path -LiteralPath $themeDir)) 'unmodified managed files removed'
    }

    # A fresh profile should be left empty when the managed block is removed.
    Remove-Item -LiteralPath $profilePath
    & $installer @testPaths -SkipDependencyInstall
    Assert (Test-Path -LiteralPath $profilePath) 'missing profile created'
    & $installer @testPaths -Uninstall
    Assert (([System.IO.File]::ReadAllBytes($profilePath)).Length -eq 0) 'new profile left empty after uninstall'

    # Simulate the previous version's literal-name config and verify safe migration.
    [System.IO.File]::WriteAllText($profilePath, '# Original', [System.Text.UTF8Encoding]::new($false))
    & $installer @testPaths -SkipDependencyInstall
    $configPath = Join-Path $themeDir 'starship.toml'
    $manifestPath = Join-Path $themeDir 'manifest.json'
    [System.IO.File]::WriteAllText($configPath, 'legacy TermuxVoid config')
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $manifest.hashes.'starship.toml' = (Get-FileHash -LiteralPath $configPath -Algorithm SHA256).Hash
    [System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json))
    [byte[]]$beforeUpdate = [System.IO.File]::ReadAllBytes($profilePath)
    & $installer @testPaths -Update -SkipDependencyInstall
    Assert (BytesEqual $beforeUpdate ([System.IO.File]::ReadAllBytes($profilePath))) 'update must not change profile'
    Assert ((Get-Content -LiteralPath $configPath -Raw).Contains('${env_var.USERNAME}')) 'update installs username prompt'
    Add-Content -LiteralPath $configPath -Value '# Custom edit'
    $failed = $false
    try { & $installer @testPaths -Update -SkipDependencyInstall } catch { $failed = $true }
    Assert $failed 'update must not overwrite modified config'
    Assert ((Get-Content -LiteralPath $configPath -Raw).Contains('# Custom edit')) 'modified config preserved'
    & $installer @testPaths -Uninstall
    Assert (Test-Path -LiteralPath $configPath) 'uninstall retains modified config'
    Remove-Item -LiteralPath $themeDir -Recurse -Force

    # Keep changes to the generated config and refuse to remove an edited managed block.
    [System.IO.File]::WriteAllText($profilePath, '# Original', [System.Text.UTF8Encoding]::new($false))
    & $installer @testPaths -SkipDependencyInstall
    $testPaths.TestProfile = Join-Path $testRoot 'OtherHost\profile.ps1'
    $failed = $false
    try { & $installer @testPaths -Uninstall } catch { $failed = $true }
    Assert $failed 'uninstall from a different host must fail'
    $testPaths.TestProfile = $profilePath
    Add-Content -LiteralPath (Join-Path $themeDir 'starship.toml') -Value '# User edit'
    $profile = [System.IO.File]::ReadAllText($profilePath).Replace('Remove-Variable termuxVoidConfig', 'Remove-Variable changedConfig')
    [System.IO.File]::WriteAllText($profilePath, $profile, [System.Text.UTF8Encoding]::new($false))
    $failed = $false
    try { & $installer @testPaths -Uninstall } catch { $failed = $true }
    Assert $failed 'edited managed block must not be removed automatically'
    Assert (Test-Path -LiteralPath (Join-Path $themeDir 'starship.toml')) 'config retained after blocked uninstall'
    $profile = $profile.Replace('Remove-Variable changedConfig', 'Remove-Variable termuxVoidConfig')
    [System.IO.File]::WriteAllText($profilePath, $profile, [System.Text.UTF8Encoding]::new($false))
    & $installer @testPaths -Uninstall
    Assert (Test-Path -LiteralPath (Join-Path $themeDir 'starship.toml')) 'modified config retained on uninstall'
    Assert ((Get-ChildItem -LiteralPath (Join-Path $testRoot '.config\TermuxVoid-Windows\backups')).Count -ge 1) 'backups created'
    Remove-Item -LiteralPath $themeDir -Recurse -Force

    # Simulate WinGet without installing a real package or depending on machine PATH.
    $oldPath = $env:PATH
    $oldLog = $env:TERMUXVOID_TEST_LOG
    try {
        $bin = Join-Path $testRoot 'fake-bin'
        New-Item -ItemType Directory -Path $bin -Force | Out-Null
        $env:PATH = $bin
        $env:TERMUXVOID_TEST_LOG = Join-Path $testRoot 'winget.log'
        $fakeWinget = Join-Path $bin 'winget.cmd'
        [System.IO.File]::WriteAllText($fakeWinget, "@echo off`r`necho %* > `"%TERMUXVOID_TEST_LOG%`"`r`nexit /b 12`r`n")
        $failed = $false
        try { & $installer @testPaths } catch { $failed = $true }
        Assert $failed 'failed dependency installation must stop setup'
        Assert (-not (Test-Path -LiteralPath $themeDir)) 'dependency failure must not write theme files'
        Assert ((Get-Content -LiteralPath $env:TERMUXVOID_TEST_LOG -Raw).Contains('Starship.Starship')) 'WinGet invoked for Starship'
        [System.IO.File]::WriteAllText($fakeWinget, "@echo off`r`necho %* > `"%TERMUXVOID_TEST_LOG%`"`r`nexit /b 0`r`n")
        & $installer @testPaths
        Assert (Test-Path -LiteralPath $configPath) 'theme installed after successful dependency command'
        & $installer @testPaths -Uninstall
    } finally {
        $env:PATH = $oldPath
        $env:TERMUXVOID_TEST_LOG = $oldLog
    }
    Write-Host 'PASS: Windows installer integration tests'
} finally {
    if (Test-Path -LiteralPath $testRoot) { Remove-Item -LiteralPath $testRoot -Recurse -Force }
}
