"""Exercise the manager's keyboard and numbered UI in a Windows pseudoconsole."""
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import tempfile
import threading
import time

from winpty import PtyProcess

ROOT = Path(__file__).resolve().parent.parent


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def run(shell):
    with tempfile.TemporaryDirectory(prefix='powershell-void-menu-') as tmp:
        folder = Path(tmp)
        base = folder / 'base'
        for edition in ('Core', 'Desktop'):
            theme = base / edition
            theme.mkdir(parents=True)
            hashes = {}
            for name in ('manager.ps1', 'starship.toml', 'termuxvoid-scheme.json'):
                content = (ROOT / 'windows' / name).read_bytes()
                (theme / name).write_bytes(content)
                hashes[name] = hashlib.sha256(content).hexdigest().upper()
            (theme / 'manifest.json').write_text(json.dumps({'profilePath': 'test-profile', 'hashes': hashes}))
        setup = folder / 'setup.ps1'
        setup.write_text(f"""
$ErrorActionPreference = 'Stop'
$env:WT_SESSION = 'test'
$env:TERMUXVOID_NO_ANIMATION = '1'
Import-Module PSReadLine
. {quote(ROOT / 'windows/animation.ps1')}
. {quote(ROOT / 'windows/manager.ps1')}
function global:Get-PVPaths([string]$Edition) {{
    $base = {quote(base)}
    $theme = Join-Path $base $Edition
    return @{{
        Base = $base; Theme = $theme; Manifest = Join-Path $theme 'manifest.json'
        Prompt = Join-Path $base "prompt-$Edition.toml"; PromptSettings = Join-Path $base "prompt-settings-$Edition.json"
        AnimationSettings = Join-Path $base "animation-settings-$Edition.json"; Fragment = Join-Path $base "$Edition.json"
    }}
}}
Write-Host '[[MENU-READY]]'
""", encoding='utf-8')
        proc = PtyProcess.spawn([shell, '-NoProfile', '-NoLogo', '-NoExit', '-File', str(setup)], dimensions=(30, 120))
        chunks = queue.Queue()
        output = []

        def reader():
            try:
                while True:
                    chunks.put(proc.read(4096))
            except (EOFError, OSError):
                pass
        threading.Thread(target=reader, daemon=True).start()

        def wait_for(text, count=1, timeout=20):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                try:
                    output.append(chunks.get(timeout=.2))
                except queue.Empty:
                    pass
                if ''.join(output).count(text) >= count:
                    return
            clean = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', ''.join(output))
            raise AssertionError(f'{shell}: missing {text!r} count {count}, output: {clean[-1800:]}')

        try:
            wait_for('[[MENU-READY]]')
            proc.write("Write-Host ('BINDING:' + (Get-PSReadLineKeyHandler -Chord 'Ctrl+Alt+v').Function)\r")
            wait_for('BINDING:PowerShellVoidManager')
            proc.write('psvoid\r')
            wait_for('=== PowerShell Void Manager')
            proc.write('\x1b[B')
            wait_for('Selected: Prompt components')
            proc.write('\r')
            wait_for('=== Prompt components ===')
            proc.write('\x1b')
            wait_for('=== PowerShell Void Manager', count=2)
            proc.write('1\r')
            wait_for('=== Animations ===')
            proc.write('1\r')
            wait_for('Animation settings saved')
            proc.write('6\r')
            wait_for('=== PowerShell Void Manager', count=3)
            proc.write('2\r')
            wait_for('=== Prompt components ===', count=2)
            proc.write('6\r')
            wait_for('Prompt settings saved')
            proc.write('11\r')
            wait_for('=== PowerShell Void Manager', count=4)
            proc.write('3\r')
            wait_for('=== Windows Terminal colors ===')
            proc.write('4\r')
            wait_for('=== Choose color ===')
            proc.write('1\r')
            wait_for('background (#RRGGBB; Esc cancels):')
            proc.write('#F8F8F8\r')
            wait_for('contrast is below 4.5:1')
            proc.write('1\r')  # Cancel unreadable colors.
            wait_for('=== Windows Terminal colors ===', count=2)
            assert not (base / ('Desktop.json' if shell == 'powershell.exe' else 'Core.json')).exists()
            proc.write('4\r')
            wait_for('=== Choose color ===', count=2)
            proc.write('1\r')
            wait_for('background (#RRGGBB; Esc cancels):', count=2)
            proc.write('#123456\r')
            wait_for('Terminal colors saved')
            proc.write('3\r')
            wait_for('Apply Monochrome to')
            proc.write('1\r')  # Previewing a preset does not apply it.
            wait_for('=== Windows Terminal colors ===', count=4)
            proc.write('6\r')
            wait_for('=== PowerShell Void Manager', count=5)
            # Time now differs: current edition is off, the other remains at its default on.
            proc.write('5\r')
            wait_for('=== PowerShell Void Manager', count=6)
            proc.write('2\r')
            wait_for('=== Prompt components ===', count=3)
            proc.write('6\r')
            wait_for('Values differ (')
            proc.write('1\r')  # Reject the mixed-target change.
            wait_for('=== Prompt components ===', count=4)
            current = 'Desktop' if shell == 'powershell.exe' else 'Core'
            other = 'Core' if current == 'Desktop' else 'Desktop'
            assert json.loads((base / f'prompt-settings-{current}.json').read_text())['Time'] is False
            assert not (base / f'prompt-settings-{other}.json').exists()
            proc.write('6\r')
            wait_for('Values differ (', count=2)
            proc.write('2\r')  # Confirm setting both editions to On.
            wait_for('Prompt settings saved', count=2)
            proc.write('11\r')
            wait_for('=== PowerShell Void Manager', count=7)
            proc.write('6\r')
            proc.write("Write-Host ('MENU' + '-DONE')\r")
            wait_for('MENU-DONE')
            # ConPTY encodes Ctrl+Alt+V as Alt + Ctrl-V.
            proc.write('\x1b\x16')
            wait_for('=== PowerShell Void Manager', count=8)
            proc.write('6\r')
            proc.write("Write-Host ('HOTKEY' + '-DONE')\r")
            wait_for('HOTKEY-DONE')
            setting = base / ('animation-settings-Desktop.json' if shell == 'powershell.exe' else 'animation-settings-Core.json')
            state = json.loads(setting.read_text())
            assert state['Welcome'] is False and state['Banner'] is True
            edition = 'Desktop' if shell == 'powershell.exe' else 'Core'
            prompt = json.loads((base / f'prompt-settings-{edition}.json').read_text())
            fragment = json.loads((base / f'{edition}.json').read_text())
            assert prompt['Time'] is True
            other = 'Core' if edition == 'Desktop' else 'Desktop'
            assert json.loads((base / f'prompt-settings-{other}.json').read_text())['Time'] is True
            assert fragment['schemes'][0]['background'] == '#123456'
            # Invalid animation preferences should return to the main menu with recovery guidance.
            proc.write(f"[IO.File]::WriteAllText({quote(setting)}, '{{invalid'); Write-Host '[[BROKEN-SETTINGS]]'\r")
            wait_for('[[BROKEN-SETTINGS]]')
            proc.write("$env:POWERSHELLVOID_PLAIN_MENU = '1'; psvoid\r")
            wait_for('=== PowerShell Void Manager', count=9)
            proc.write('1\r')
            wait_for('correct this JSON')
            wait_for('=== PowerShell Void Manager', count=10)
            proc.write('6\r')
            proc.write("Write-Host ('RECOVERY' + '-DONE')\r")
            wait_for('RECOVERY-DONE')
            proc.write('exit\r')
            print(f'PASS: {shell} interactive arrow and numbered manager')
        finally:
            proc.close(force=True)


def test_conflicting_shortcut(shell):
    with tempfile.TemporaryDirectory(prefix='powershell-void-conflict-') as tmp:
        setup = Path(tmp) / 'conflict.ps1'
        setup.write_text(f"""
$ErrorActionPreference = 'Stop'
$env:WT_SESSION = 'test'
Import-Module PSReadLine
Set-PSReadLineKeyHandler -Chord 'Ctrl+Alt+v' -BriefDescription 'ExistingBinding' -ScriptBlock {{ }}
Set-Alias -Name psvoid -Value Get-Date -Scope Global
. {quote(ROOT / 'windows/manager.ps1')}
if ((Get-Alias psvoid).Definition -ne 'Get-Date' -or -not (Get-Command Invoke-PowerShellVoidManager)) {{ throw 'Existing command was not preserved.' }}
Write-Host ('[[CONFLICT:' + (Get-PSReadLineKeyHandler -Chord 'Ctrl+Alt+v').Function + ']]')
""", encoding='utf-8')
        proc = PtyProcess.spawn([shell, '-NoProfile', '-NoLogo', '-NoExit', '-File', str(setup)], dimensions=(30, 120))
        result = []
        chunks = queue.Queue()
        def reader():
            try:
                while True:
                    chunks.put(proc.read(4096))
            except (EOFError, OSError):
                pass
        threading.Thread(target=reader, daemon=True).start()
        try:
            end = time.monotonic() + 15
            while time.monotonic() < end:
                try: result.append(chunks.get(timeout=.2))
                except queue.Empty: pass
                if '[[CONFLICT:ExistingBinding]]' in ''.join(result):
                    print(f'PASS: {shell} existing shortcut preserved')
                    return
            raise AssertionError(f'{shell}: existing shortcut not preserved: {"".join(result)[-6000:]}')
        finally:
            proc.close(force=True)


if __name__ == '__main__':
    try:
        for executable in ('powershell.exe', 'pwsh.exe'):
            run(executable)
            test_conflicting_shortcut(executable)
    except Exception as exc:
        print('::error::' + str(exc).replace('\n', '%0A').replace('\r', '%0D'), flush=True)
        raise
