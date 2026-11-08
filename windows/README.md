# TermuxVoid for Windows Terminal + PowerShell

The Windows version uses Starship for the prompt and keeps its configuration separate from Termux and any existing Starship configuration. It shows the current username, directory, Git branch (in a repository), local time, the previous command's status, command duration when at least two seconds, and relevant Python, Node.js, Rust, .NET, and package context when detected:

- `✅` means the previous command succeeded; `❌` means it failed. A fresh session starts with the success indicator.
- `⏳` appears when PowerShell has running background jobs. A foreground command doesn't have a "pending" prompt: the next prompt appears only after it finishes. These indicators depend on Starship's PowerShell integration and the status PowerShell reports.

## Requirements and installation

Use Windows Terminal with Windows PowerShell 5.1 or PowerShell 7. In the profile you want to customize, run:

```powershell
& ([scriptblock]::Create((irm 'https://raw.githubusercontent.com/JCVERSA/TermuxVoid-Theme/arena/d693b190-termuxvoid-theme/windows/install.ps1')))
```

This downloads and runs code from the current development branch. You can [inspect the bootstrap script](install.ps1) and [installer](termuxvoid.ps1) first. The bootstrap downloads those files into a temporary folder and runs setup in a child PowerShell process with a process-only execution-policy bypass; group policies can still prevent execution. It cleans up its temporary files. Run the same command to install or update: existing installations use the guarded update described below. During setup you can opt into a separate TermuxVoid Windows Terminal profile with the original colors.

Alternatively, from a complete repository checkout, run `.\windows\termuxvoid.ps1` for an install or `.\windows\termuxvoid.ps1 -Update` to update.
If Starship is not already on PATH, the installer uses WinGet to install the per-user portable `Starship.Starship` package. This requires an internet connection and WinGet, accepts the WinGet source and package agreements, and changes the user's installed packages/PATH. A missing WinGet or failed installation stops setup before theme files are changed. If Starship is already on PATH, nothing is downloaded. Restart **Windows Terminal** after setup so it picks up PATH changes; open the same PowerShell profile to see the prompt.

Git is only needed for working with Git repositories and is not installed or upgraded. The prompt works without Git; it shows a branch only inside a repository. Colors and font are optional visual customization, not required dependencies; the installer does not rewrite Windows Terminal settings or install fonts.

For offline or managed environments, use `-SkipDependencyInstall` with the local installer to skip WinGet. The prompt won't initialize until Starship is available on PATH. The managed profile block sets `STARSHIP_CONFIG` in that shell session and initializes Starship. It doesn't overwrite your existing Starship config, but that config isn't used while the block is active. Other prompt customizations may conflict.

If Windows blocks scripts, inspect the script and execution-policy requirements first. A temporary process-only option is `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, followed by the command above. This does not override a machine/group policy. Downloaded files may also be marked as coming from the internet.

Windows PowerShell and PowerShell 7 have separate profiles and installations. Run the installer in each edition and host you want to customize. It backs up an existing profile to `~\.config\TermuxVoid-Windows\backups` before changing it; backups may contain sensitive profile content.

## Update an existing Windows installation

Run the quick-install command again in the same PowerShell edition and host used to install. Alternatively, from a **new copy of the repository**, run:

```powershell
.\windows\termuxvoid.ps1 -Update
```

This supports the earlier TermuxVoid Windows installer. It checks installed files against their manifest, backs them up, replaces the theme and installer, and appends a separately marked animation helper block to older profiles. Subsequent updates leave that block unchanged. If you edited an installed file or the managed profile block, the update stops rather than overwriting your changes. Save your customizations and resolve the conflict manually before retrying. If an update fails midway, restore the backed-up files from the printed update directory and, if the profile changed, the separately printed profile backup.

## Optional Windows Terminal profile and font

During installation or update, answer `y` when asked to create a TermuxVoid profile. This creates a Windows Terminal JSON fragment under `%LOCALAPPDATA%\Microsoft\Windows Terminal\Fragments\TermuxVoid-Theme`, containing the original color scheme and a **separate** profile for the current PowerShell edition. Restart Windows Terminal and select **TermuxVoid PowerShell 7** or **TermuxVoid Windows PowerShell** in the profile menu. Your existing profiles and `settings.json` are not modified. Profile overrides or a conflicting scheme in your own Terminal settings can take precedence.

For a local noninteractive install, pass `-TerminalProfile` to opt in or `-SkipTerminalProfile` to skip the prompt. The short command also accepts either switch after the closing parenthesis. Updates preserve a previously installed fragment; they refuse to overwrite a modified or unowned fragment. The uninstaller removes an unchanged fragment but retains a modified one. Settings you manually saved in Windows Terminal may remain after removal.

For the matching font, open `assets\font.ttf` from a complete repository copy in Windows and select **Install**, then set the TermuxVoid profile's **Font face** to `UbuntuMono Nerd Font` in Terminal Settings → Appearance. The installer does not install it automatically: its metadata references the Ubuntu Font Licence 1.0, but this repository does not include complete font provenance or a separate font license. Verify its distribution terms before redistributing it. A different installed Nerd Font is also acceptable.

Alternatively, you can apply [`termuxvoid-scheme.json`](termuxvoid-scheme.json) to an existing profile manually: back up Terminal's `settings.json`, add the JSON object to its top-level `"schemes"` array without replacing existing entries, then select `TermuxVoid` under the profile's Appearance settings.

The original image banner and shell shortcuts are not enabled. This setup does not install Fish, eza or jp2a, or change the default shell.

## Optional animations

Animations are **off by default** and never run after every command. After installing or updating, restart the same PowerShell profile to load the helper commands. No animation engine or runtime is installed until you explicitly request it:

```powershell
# Requires Python 3.8+ with venv and pip on PATH (py.exe or python.exe).
Install-TermuxVoidAnimation -Engine TTE
Enable-TermuxVoidWelcome
```

Open a new Windows Terminal tab for the TTE welcome. Turn it off with `Disable-TermuxVoidWelcome`. To skip it temporarily, set `$env:TERMUXVOID_NO_ANIMATION = '1'` before launching a child shell. Welcome playback only runs in an interactive Windows Terminal session; redirected input/output, `TERM=dumb`, small terminals, and the opt-out use a static message or skip playback. It does not run from the Starship prompt. If TTE is unavailable or fails, the prompt still loads with a plain-text fallback.

Try the other engines **on demand**:

```powershell
# Requires Node.js 18.3+ and npm on PATH.
Install-TermuxVoidAnimation -Engine AsciiRest
Show-TermuxVoidAnimation -Engine AsciiRest

# Requires Python 3.8+ with venv and pip on PATH.
Install-TermuxVoidAnimation -Engine Asciimatics
Show-TermuxVoidAnimation -Engine Asciimatics
```

You can also run `Show-TermuxVoidAnimation -Engine TTE` to preview the inline welcome. ascii.rest shows a two-second neon text banner; Asciimatics opens a short full-screen showcase. Interrupt with Ctrl+C. These features need an interactive terminal and have not been visually verified on every Windows console; the helper attempts to restore cursor visibility on exit.

The explicit install commands download pinned packages: TTE 0.15.0 and Asciimatics 1.15.0 into `~\.config\TermuxVoid-Windows\animation-python`, and ascii.rest 0.4.0 into `~\.config\TermuxVoid-Windows\animation-node`. Asciimatics also installs its dependencies, including pywin32 on Windows. These directories and welcome preferences are retained when the theme is uninstalled; remove them manually if you no longer need them. Python and Node.js themselves are not installed automatically.

## Uninstall or restore

From the same PowerShell edition and host used to install:

```powershell
& "$HOME\.config\TermuxVoid-Windows\$($PSVersionTable.PSEdition)\termuxvoid.ps1" -Uninstall
```

Alternatively, run `./windows/termuxvoid.ps1 -Uninstall` from the repository. The uninstaller backs up the current profile and removes only the unchanged managed block, preserving other profile bytes. If the block was edited, it stops; remove the marked block manually and run uninstall again. Installed files changed since installation are retained. Backups, Starship, fonts, and Windows Terminal settings remain; an unchanged optional Terminal fragment is removed. To restore an original profile instead, choose a backup and copy it to `$PROFILE.CurrentUserCurrentHost` after reviewing later changes.

If installation fails partway through, inspect the profile and the printed backup path. Installation files may remain under `~\.config\TermuxVoid-Windows\<edition>`; review them before removing them. Don't delete backups until you no longer need them.

## Tests

On Windows, run `powershell -NoProfile -File .\tests\windows.test.ps1` and/or `pwsh -NoProfile -File .\tests\windows.test.ps1`. The installer tests use a temporary home, profile, Terminal-fragment directory and fake WinGet; they do not install packages or change Windows Terminal settings. `tests/windows-animation.test.ps1` installs the optional engines into a temporary directory to exercise their setup. Separately verify actual WinGet installation and prompt rendering in a real Terminal, including a Git repository, success/failure and running background jobs.
