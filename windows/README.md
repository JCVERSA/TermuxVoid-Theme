# TermuxVoid for Windows Terminal + PowerShell

This separate Windows setup reuses the TermuxVoid Starship prompt and palette. It does not alter the Termux installation. The installer adds a managed block to the **current host's current-user PowerShell profile** and writes a private Starship configuration. It does not install packages or modify Windows Terminal settings automatically.

## Requirements

- Windows Terminal and Windows PowerShell 5.1 or PowerShell 7, running in the Terminal profile you want to customize.
- A complete copy of this repository, including `windows` and `assets` (not just the installer script).
- [Starship](https://starship.rs/) on your PATH. For example, if you use WinGet, run `winget install --id Starship.Starship --exact`, then open a new PowerShell tab. Installing Starship is optional at setup time, but the prompt will not activate until it is available.
- A Nerd Font for the icons. The repository's `assets/font.ttf` identifies itself as **UbuntuMono Nerd Font**; see the licensing note below.

## Install the prompt

1. Open the PowerShell profile in Windows Terminal that you want to customize, and change directory to this repository.
2. Run:

   ```powershell
   .\windows\termuxvoid.ps1
   ```

   To use a different prompt label instead of `TermuxVoid`:

   ```powershell
   .\windows\termuxvoid.ps1 -Name 'My PC'
   ```

   The label accepts 1–40 ASCII letters, numbers, spaces, underscores, or hyphens. To change it later, uninstall and reinstall, or edit the installed `starship.toml` yourself.

3. Open a new tab of the **same PowerShell profile**. The managed block sets `STARSHIP_CONFIG` for that shell session and initializes Starship if it is available. Your previous Starship configuration is not overwritten, but will not be used in that session while this block is active. Existing prompt customizations in the profile may conflict with Starship; inspect the profile if the prompt does not appear.

If Windows blocks local scripts, inspect the script and Windows execution-policy requirements first. A temporary, process-only option is `Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass`, followed by the command above. This does not override a machine/group policy. Downloaded files may also be marked as coming from the internet.

Windows PowerShell and PowerShell 7 use different profiles and have separate installations. Run the installer in each edition you want to customize. The installer refuses to overwrite an existing installation or a profile with TermuxVoid markers. It backs up an existing profile before changing it under `~\.config\TermuxVoid-Windows\backups` (these backups may contain sensitive profile content).

## Apply the colors and font

The installer deliberately does not rewrite `settings.json` (which may contain comments and personal settings). In Windows Terminal:

1. Open **Settings → Open JSON file**. Back it up first.
2. Copy the JSON object in [`termuxvoid-scheme.json`](termuxvoid-scheme.json) into the existing top-level `"schemes"` array. Create the array if necessary; do not replace existing schemes. Avoid adding a second scheme with the same name. Save the file.
3. In Settings, select your PowerShell profile → **Appearance** → set **Color scheme** to `TermuxVoid`.
4. For the matching font, open `assets\font.ttf` in Windows and select **Install**, then set that profile's **Font face** to `UbuntuMono Nerd Font` in **Appearance**. A different installed Nerd Font is also acceptable.

The color and font settings are per Windows Terminal profile; apply them to each profile you want to theme. They are not removed by the uninstaller. The existing font metadata references the Ubuntu Font Licence 1.0; this repository does not currently include complete font provenance or a separate font license. Verify its distribution terms before redistributing it.

The image banner is not enabled by this version. It does not install Fish, eza, jp2a, or change the Windows default shell.

## Uninstall or restore

From the **same PowerShell edition and host** used to install, run:

```powershell
& "$HOME\.config\TermuxVoid-Windows\$($PSVersionTable.PSEdition)\termuxvoid.ps1" -Uninstall
```

Alternatively, run `./windows/termuxvoid.ps1 -Uninstall` from the repository. The uninstaller backs up the current profile and removes only the unchanged managed block, preserving other profile bytes. If the block was edited, it stops; remove the marked block manually and run uninstall again. Installed files changed since installation are retained for manual review. Backups, Starship, fonts, and Windows Terminal settings remain in place. To restore the exact original profile instead, choose a backup and copy it to `$PROFILE.CurrentUserCurrentHost` after reviewing any changes made since that backup.

If installation fails partway through, inspect the profile and the printed backup path. The installer may leave its own files under `~\.config\TermuxVoid-Windows\<edition>`; review them before removing them. Do not delete backups until you no longer need them.

## Tests

On Windows, run `powershell -NoProfile -File .\tests\windows.test.ps1` and/or `pwsh -NoProfile -File .\tests\windows.test.ps1` from the repository root. The integration tests use a temporary home and profile; they do not install Starship or change Windows Terminal settings. For visual verification, separately check a real Terminal profile, font glyphs, colors, Git status and prompt behavior.
