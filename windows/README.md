# PowerShell Void for Windows Terminal + PowerShell

The Windows version uses Starship for the prompt and keeps its configuration separate from Termux and any existing Starship configuration. It shows the current username, directory, Git branch (in a repository), local time, the previous command's status, command duration when at least two seconds, and relevant Python, Node.js, Rust, .NET, and package context when detected:

- `✅` means the previous command succeeded; `❌` means it failed. A fresh session starts with the success indicator.
- `⏳` appears when PowerShell has running background jobs. A foreground command doesn't have a "pending" prompt: the next prompt appears only after it finishes. These indicators depend on Starship's PowerShell integration and the status PowerShell reports.

## Requirements and installation

Use Windows Terminal with Windows PowerShell 5.1 or PowerShell 7. In the profile you want to customize, run:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/JCVERSA/TermuxVoid-Theme/arena/d693b190-termuxvoid-theme/windows/install.ps1')))
```

This downloads and runs code from the current development branch. You can [inspect the bootstrap script](install.ps1) and [installer](termuxvoid.ps1) first. The bootstrap downloads those files into a temporary folder and runs setup in a child PowerShell process with a process-only execution-policy bypass; group policies can still prevent execution. It cleans up its temporary files. Run the same command to install or update: existing installations use the guarded update described below. During setup you can opt into a separate PowerShell Void Windows Terminal profile with the original colors.

Alternatively, from a complete repository checkout, run `.\windows\termuxvoid.ps1` for an install or `.\windows\termuxvoid.ps1 -Update` to update.
If Starship is not already on PATH, the installer uses WinGet to install the per-user portable `Starship.Starship` package. This requires an internet connection and WinGet, accepts the WinGet source and package agreements, and changes the user's installed packages/PATH. A missing WinGet or failed installation stops setup before theme files are changed. If Starship is already on PATH, nothing is downloaded. Restart **Windows Terminal** after setup so it picks up PATH changes; open the same PowerShell profile to see the prompt.

Git is only needed for working with Git repositories and is not installed or upgraded. The prompt works without Git; it shows a branch only inside a repository. Colors and font are optional visual customization, not required dependencies; the installer does not rewrite Windows Terminal settings or install fonts.

For offline or managed environments, use `-SkipDependencyInstall` with the local installer to skip dependency setup. The prompt won't initialize until Starship is available on PATH. The managed profile block sets `STARSHIP_CONFIG` in that shell session and initializes Starship. It doesn't overwrite your existing Starship config, but that config isn't used while the block is active. Other prompt customizations may conflict.

If Windows blocks scripts, inspect the script and execution-policy requirements first. A temporary process-only option is `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, followed by the command above. This does not override a machine/group policy. Downloaded files may also be marked as coming from the internet.

Windows PowerShell and PowerShell 7 have separate profiles and installations. Run the installer in each edition and host you want to customize. It backs up an existing profile to `~\.config\TermuxVoid-Windows\backups` before changing it; backups may contain sensitive profile content.

## Update an existing Windows installation

Run the quick-install command again in the same PowerShell edition and host used to install. Alternatively, from a **new copy of the repository**, run:

```powershell
.\windows\termuxvoid.ps1 -Update
```

This supports the earlier TermuxVoid Windows installer. It checks installed files against their manifest, backs them up, replaces the theme and installer, and appends a separately marked animation helper block to older profiles. Subsequent updates leave that block unchanged. If you edited an installed file or the managed profile block, the update stops rather than overwriting your changes. Save your customizations and resolve the conflict manually before retrying. If an update fails midway, restore the backed-up files from the printed update directory and, if the profile changed, the separately printed profile backup.

## Optional Windows Terminal profile and font

During installation or update, answer `y` when asked to create a PowerShell Void profile. This creates a Windows Terminal JSON fragment under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme`, containing the original color scheme and a **separate** profile for the current PowerShell edition. Restart Windows Terminal and select **PowerShell Void 7** or **PowerShell Void Windows PowerShell** in the profile menu. Your existing profiles and `settings.json` are not modified. Profile overrides or a conflicting scheme in your own Terminal settings can take precedence.

For a local noninteractive install, pass `-TerminalProfile` to opt in or `-SkipTerminalProfile` to skip the prompt. The short command also accepts either switch after the closing parenthesis. Updates preserve a previously installed fragment; they refuse to overwrite a modified or unowned fragment. The uninstaller removes an unchanged fragment but retains a modified one. Settings you manually saved in Windows Terminal may remain after removal.

For the matching font, open `assets\font.ttf` from a complete repository copy in Windows and select **Install**, then set the PowerShell Void profile's **Font face** to `UbuntuMono Nerd Font` in Terminal Settings → Appearance. The installer does not install it automatically: its metadata references the Ubuntu Font Licence 1.0, but this repository does not include complete font provenance or a separate font license. Verify its distribution terms before redistributing it. A different installed Nerd Font is also acceptable.

Alternatively, you can apply [`termuxvoid-scheme.json`](termuxvoid-scheme.json) to an existing profile manually: back up Terminal's `settings.json`, add the JSON object to its top-level `"schemes"` array without replacing existing entries, then select `PowerShell Void` under the profile's Appearance settings.

The original image banner and shell shortcuts are not enabled. This setup does not install Fish, eza or jp2a, or change the default shell.

## Interactive manager

After installing or updating, restart the same PowerShell profile and type **`psvoid`**. You can also press **Ctrl+Alt+V** at an empty prompt. The shortcut is not installed if PSReadLine already has a binding for it; Windows Terminal or an AltGr keyboard layout may also intercept it. In those cases use `psvoid` instead. An existing `psvoid` command is never replaced; use `Invoke-PowerShellVoidManager` if there is a name conflict.

Choose with Up/Down and Enter, or type a number and press Enter; Esc or 0 goes back. Windows Terminal updates the selection on one line; set `$env:POWERSHELLVOID_PLAIN_MENU = '1'` before opening the manager to use line-by-line feedback instead, which may work better with some assistive technologies. The menu provides animation switches, idle delay and previews; prompt-component toggles and a custom directory text color; Terminal color presets and custom `#RRGGBB` colors; and status, dependency repair, update and uninstall. Repair, update and uninstall ask for confirmation. Maintenance actions operate on the current edition; switch editions to maintain the other one.

Use **Switch target** to apply configuration changes to both installed PowerShell editions, or just the current one. When both editions are targeted, the menu shows each edition's values; if a toggle differs, it asks before setting both to the opposite of the current edition's value. Update both editions to this manager version before applying settings to both. Other open shells must be restarted to pick up their changes. Color presets show their hex values and ask for confirmation. Foreground/background contrast below 4.5:1 triggers a warning and confirmation; this check does not cover ANSI or prompt colors and is not an accessibility guarantee. Terminal colors belong to a separate **PowerShell Void** Terminal profile; creating or changing colors creates or updates that profile, not `settings.json`. Restart Terminal and select that profile. Existing user overrides in Windows Terminal can take precedence.

Prompt customization creates a separate user-owned prompt file and never edits the installed Starship template. The manager refuses to overwrite a modified generated prompt or an edited/unowned Terminal fragment; back up and resolve conflicts manually. Changes create backups under `~\.config\TermuxVoid-Windows\backups`. To reset an invalid animation settings file, back it up and move it aside before reopening the menu. For an edited generated prompt, back up and restore its matching prompt/settings pair, or move both aside to reset prompt choices. Restore a matching owned Terminal fragment to resolve a fragment conflict; do not discard your edits without a backup. Prompt choices are retained on update; if the underlying template changed, open **Prompt components → Reapply** to pick up the updated template. Custom prompt files and settings are retained on uninstall. A manager-customized Terminal profile and its color metadata are backed up before its fragment is removed.

## Command-history suggestions

PowerShell Void enables inline suggestions from PSReadLine history by default. Run a command such as `clear` once, then begin typing it again; press **Right Arrow** to accept a displayed suggestion, then **Enter** to run it. Suggestions depend on matching history and may not appear for every prefix. Your current PSReadLine keybindings are not changed; a custom Right Arrow binding may work differently.

In `psvoid`, choose **History suggestions** to switch history predictions on or off, including for both installed editions. Off removes the history prediction source but leaves any predictor plugins enabled; turning it on selects inline view and adds history without disabling plugins. Other open shells must be restarted. This setting is retained on uninstall, but uninstall stops PowerShell Void from applying it in new sessions.

PSReadLine normally stores its own history across sessions; PowerShell Void does not create, copy or clear history files or override your history-save policy. If your policy disables history saving, suggestions won't persist between sessions. History can contain sensitive information, so avoid entering secrets directly in commands. PowerShell editions or hosts may use different history files.

Suggestions require PSReadLine 2.1 or newer and a compatible terminal. If needed, normal installation/update attempts to install PSReadLine 2.3.6 from PowerShell Gallery for the current user; it does not upgrade an already compatible version. The module is retained on uninstall. If setup cannot install it, or if you used `-SkipDependencyInstall`, install it manually and restart PowerShell:

```powershell
Install-Module PSReadLine -RequiredVersion 2.3.6 -Scope CurrentUser -Repository PSGallery -AllowClobber -Force
```

An older already-loaded version may require closing all PowerShell windows before restarting. Plugin and profile settings applied later can override PowerShell Void's selection.

## Animations

The installer automatically sets up all three animation engines. In interactive Windows Terminal sessions the TTE welcome and ascii.rest banner play at startup; Asciimatics shows a full-screen starfield after **five seconds** of inactivity at an empty PowerShell prompt. It stops on keyboard or mouse activity, without intentionally consuming the key. It does not run while a command or interactive application is running, or while a command line contains text. It requires PSReadLine and Windows' session-wide last-input detection, so activity in other applications can delay or dismiss it. The display is not guaranteed to be limited to the active Windows Terminal tab. Very old PSReadLine versions or other event handlers may prevent idle detection. No packages are downloaded at shell startup.

After installation or update, restart the same PowerShell profile. Use these commands to configure the animations independently:

```powershell
Set-PowerShellVoidAnimation -Welcome Off       # TTE startup welcome
Set-PowerShellVoidAnimation -Banner Off        # ascii.rest startup banner
Set-PowerShellVoidAnimation -Idle Off          # Asciimatics idle showcase
Set-PowerShellVoidAnimation -Idle On -IdleSeconds 30
Set-PowerShellVoidAnimation -Welcome On -Banner On
```

Use `Disable-PowerShellVoidWelcome` or `Enable-PowerShellVoidWelcome` to switch both startup effects together. The previous `Enable-TermuxVoidWelcome`, `Disable-TermuxVoidWelcome`, `Install-TermuxVoidAnimation` and `Show-TermuxVoidAnimation` commands remain available for compatibility. To preview an effect, run `Show-PowerShellVoidAnimation -Engine TTE`, `-Engine AsciiRest`, or `-Engine Asciimatics`. Set `$env:TERMUXVOID_NO_ANIMATION = '1'` before launching a child shell to temporarily suppress all animations. Redirected sessions, `TERM=dumb`, `NO_COLOR`, and small terminals skip animations or use plain text. The timer accepts 1–3600 seconds.

### Automatic dependencies and cleanup

The installer uses an existing Python 3.8+ (with venv and pip), or attempts to install Python 3.12 per-user with WinGet if needed. WinGet accepts package and source agreements and changes the user's installed programs; installation can fail because of policies or connectivity. Existing Node.js 18.3+ and npm are used if available; otherwise a pinned, SHA-256-verified Node.js 24.22.1 archive is downloaded into the user directory on x64 or ARM64 Windows. Unsupported architectures require a suitable Node installation. The installer downloads pinned TTE 0.15.0, Asciimatics 1.15.0 (including pywin32 on Windows), and ascii.rest 0.4.0 into `~\.config\TermuxVoid-Windows`. Setup fails with instructions if a dependency cannot be installed; it may leave a Python installation or partial per-user dependency directories behind. Review an incomplete directory before removing it and retrying.

`-SkipDependencyInstall` skips both Starship and animation dependencies. Uninstall retains shared dependencies and animation settings so another PowerShell edition is not broken. If no longer needed, remove `animation-python`, `animation-node`, `animation-node-runtime`, and the `animation-settings-*.json` files from that directory manually. Python installed via WinGet is a separate Windows application and must be removed separately if desired.

## Uninstall or restore

From the same PowerShell edition and host used to install:

```powershell
& "$HOME\.config\TermuxVoid-Windows\$($PSVersionTable.PSEdition)\termuxvoid.ps1" -Uninstall
```

Alternatively, run `./windows/termuxvoid.ps1 -Uninstall` from the repository. The uninstaller backs up the current profile and removes only the unchanged managed block, preserving other profile bytes. If the block was edited, it stops; remove the marked block manually and run uninstall again. Installed files changed since installation are retained. Backups, custom prompt files and preferences, Starship, animation dependencies and preferences, fonts, and Windows Terminal settings remain; an unchanged optional Terminal fragment is removed. To restore an original profile instead, choose a backup and copy it to `$PROFILE.CurrentUserCurrentHost` after reviewing later changes.

If installation fails partway through, inspect the profile and the printed backup path. Installation files may remain under `~\.config\TermuxVoid-Windows\<edition>`; review them before removing them. Don't delete backups until you no longer need them.

## Tests

On Windows, run `powershell -NoProfile -File .\tests\windows.test.ps1` and/or `pwsh -NoProfile -File .\tests\windows.test.ps1`. The installer tests use a temporary home, profile, Terminal-fragment directory and fake WinGet; they do not install packages or change Windows Terminal settings. `tests/windows-animation.test.ps1` downloads the animation packages into a temporary directory to exercise automatic setup and settings. Separately verify actual WinGet installation and prompt rendering in a real Terminal, including a Git repository, success/failure and running background jobs.
