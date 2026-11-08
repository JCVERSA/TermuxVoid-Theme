# TermuxVoid for Windows Terminal + PowerShell

The Windows version uses Starship for the prompt and keeps its configuration separate from Termux and any existing Starship configuration. It shows the current username, directory, Git branch (in a repository), local time, and the previous command's status:

- `✅` means the previous command succeeded; `❌` means it failed. A fresh session starts with the success indicator.
- `⏳` appears when PowerShell has running background jobs. A foreground command doesn't have a "pending" prompt: the next prompt appears only after it finishes. These indicators depend on Starship's PowerShell integration and the status PowerShell reports.

## Requirements and installation

Use Windows Terminal with Windows PowerShell 5.1 or PowerShell 7. Get a complete copy of this repository, including `windows/starship.toml`. Open the PowerShell profile you want to customize, change directory to the repository, and run:

```powershell
.\windows\termuxvoid.ps1
```

If Starship is not already on PATH, the installer uses WinGet to install the per-user portable `Starship.Starship` package. This requires an internet connection and WinGet, accepts the WinGet source and package agreements, and changes the user's installed packages/PATH. A missing WinGet or failed installation stops setup before theme files are changed. If Starship is already on PATH, nothing is downloaded. Restart **Windows Terminal** after setup so it picks up PATH changes; open the same PowerShell profile to see the prompt.

Git is only needed for working with Git repositories and is not installed or upgraded. The prompt works without Git; it shows a branch only inside a repository. The colors and font below are optional visual customization, not required dependencies; the installer does not rewrite Windows Terminal settings or install fonts.

For offline or managed environments, `-SkipDependencyInstall` skips WinGet. The prompt won't initialize until Starship is available on PATH. The managed profile block sets `STARSHIP_CONFIG` in that shell session and initializes Starship. It doesn't overwrite your existing Starship config, but that config isn't used while the block is active. Other prompt customizations may conflict.

If Windows blocks scripts, inspect the script and execution-policy requirements first. A temporary process-only option is `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, followed by the command above. This does not override a machine/group policy. Downloaded files may also be marked as coming from the internet.

Windows PowerShell and PowerShell 7 have separate profiles and installations. Run the installer in each edition and host you want to customize. It backs up an existing profile to `~\.config\TermuxVoid-Windows\backups` before changing it; backups may contain sensitive profile content.

## Update an existing Windows installation

From a **new copy of the repository**, in the same PowerShell edition and host used to install, run:

```powershell
.\windows\termuxvoid.ps1 -Update
```

This supports the earlier TermuxVoid Windows installer. It checks the installed files against their manifest, backs them up, replaces the theme and installer, and leaves the profile unchanged. If you edited an installed file or the managed profile block, the update stops rather than overwriting your changes. Save your customizations and resolve the conflict manually before retrying. If an update fails midway, restore `starship.toml`, `termuxvoid.ps1`, and `manifest.json` from the printed backup directory.

## Apply the optional colors and font

The installer does not rewrite `settings.json` (which may contain comments and personal settings). In Windows Terminal:

1. Open **Settings → Open JSON file** and back it up.
2. Copy the JSON object in [`termuxvoid-scheme.json`](termuxvoid-scheme.json) into the existing top-level `"schemes"` array. Create the array if necessary; do not replace existing schemes or duplicate the `TermuxVoid` name. Save the file.
3. In Settings, select your PowerShell profile → **Appearance** → set **Color scheme** to `TermuxVoid`.
4. Optionally open `assets\font.ttf` in Windows and select **Install**, then set that profile's **Font face** to `UbuntuMono Nerd Font`. The existing font metadata references the Ubuntu Font Licence 1.0; this repository does not currently include complete font provenance or a separate font license. Verify its distribution terms before redistributing it.

These settings are per Windows Terminal profile and are not removed by the uninstaller. The image banner is not enabled. This setup does not install Fish, eza or jp2a, or change the default shell.

## Uninstall or restore

From the same PowerShell edition and host used to install:

```powershell
& "$HOME\.config\TermuxVoid-Windows\$($PSVersionTable.PSEdition)\termuxvoid.ps1" -Uninstall
```

Alternatively, run `./windows/termuxvoid.ps1 -Uninstall` from the repository. The uninstaller backs up the current profile and removes only the unchanged managed block, preserving other profile bytes. If the block was edited, it stops; remove the marked block manually and run uninstall again. Installed files changed since installation are retained. Backups, Starship, fonts, and Windows Terminal settings remain. To restore an original profile instead, choose a backup and copy it to `$PROFILE.CurrentUserCurrentHost` after reviewing later changes.

If installation fails partway through, inspect the profile and the printed backup path. Installation files may remain under `~\.config\TermuxVoid-Windows\<edition>`; review them before removing them. Don't delete backups until you no longer need them.

## Tests

On Windows, run `powershell -NoProfile -File .\tests\windows.test.ps1` and/or `pwsh -NoProfile -File .\tests\windows.test.ps1`. The tests use a temporary home, profile and fake WinGet; they do not install packages or change Windows Terminal settings. Separately verify actual WinGet installation and prompt rendering in a real Terminal, including a Git repository, success/failure and running background jobs.
