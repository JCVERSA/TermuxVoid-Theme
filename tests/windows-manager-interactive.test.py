"""Exercise the manager's keyboard and numbered UI in a Windows pseudoconsole."""
import json
import os
from pathlib import Path
import queue
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
            (theme / 'manifest.json').write_text(json.dumps({'profilePath': 'test-profile', 'hashes': {'dummy': 'fake'}}))
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
            raise AssertionError(f'{shell}: missing {text!r} count {count}, output: {"".join(output)[-7000:]}')

        try:
            wait_for('[[MENU-READY]]')
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
            proc.write('6\r')
            proc.write("Write-Host ('MENU' + '-DONE')\r")
            wait_for('MENU-DONE')
            setting = base / ('animation-settings-Desktop.json' if shell == 'powershell.exe' else 'animation-settings-Core.json')
            state = json.loads(setting.read_text())
            assert state['Welcome'] is False and state['Banner'] is True
            proc.write('exit\r')
            print(f'PASS: {shell} interactive arrow and numbered manager')
        finally:
            proc.close(force=True)


if __name__ == '__main__':
    for executable in ('powershell.exe', 'pwsh.exe'):
        run(executable)
