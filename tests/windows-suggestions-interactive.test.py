"""Test real PSReadLine inline predictions and history persistence via ConPTY."""
from pathlib import Path
import os
import queue
import re
import tempfile
import threading
import time

from winpty import PtyProcess

ROOT = Path(__file__).resolve().parent.parent


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def session(shell, setup, first, legacy):
    env = os.environ.copy()
    if shell == 'powershell.exe':
        if legacy:
            system_modules = Path(env['SYSTEMROOT']) / 'System32/WindowsPowerShell/v1.0/Modules'
            env['PSMODULEPATH'] = env['PV_PS5_LEGACY_MODULE_DIR'] + ';' + str(system_modules)
        else:
            env['PSMODULEPATH'] = env['PV_PS5_MODULE_DIR'] + ';' + env.get('PSMODULEPATH', '')
    proc = PtyProcess.spawn([shell, '-NoProfile', '-NoLogo', '-NoExit', '-File', str(setup)], env=env, dimensions=(30, 120))
    chunks = queue.Queue()
    output = []

    def reader():
        try:
            while True:
                chunks.put(proc.read(4096))
        except (EOFError, OSError):
            pass

    threading.Thread(target=reader, daemon=True).start()

    def wait_for(text, count=1, timeout=20, start=0):
        end = time.monotonic() + timeout
        while time.monotonic() < end:
            try:
                output.append(chunks.get(timeout=.2))
            except queue.Empty:
                pass
            if ''.join(output[start:]).count(text) >= count:
                return
        clean = re.sub(r'\x1b\[[0-?]*[ -/]*[@-~]', '', ''.join(output))
        raise AssertionError(f'{shell}: missing {text!r}, output: {clean[-3500:]}')

    try:
        wait_for('[[PREDICTION-READY]]')
        if first:
            proc.write('Get-VoidSuggestProof\r')
            wait_for('[[HISTORY-EXECUTED]]')
        # Capture only new output. PSReadLine must visibly render the missing suffix
        # before Right Arrow accepts it; Enter alone must not complete the line.
        start = len(output)
        proc.write('G')
        wait_for('Proof', start=start)
        proc.write('\x1b[C\r')
        wait_for('[[HISTORY-EXECUTED]]', count=2 if first else 1)
        proc.write('exit\r')
    finally:
        proc.close(force=True)


def run(shell, legacy=False):
    with tempfile.TemporaryDirectory(prefix='powershell-void-predict-') as tmp:
        folder = Path(tmp)
        setup = folder / 'setup.ps1'
        history = folder / 'history.txt'
        setup.write_text(f"""
$ErrorActionPreference = 'Stop'
$env:WT_SESSION = 'test'
$env:TERMUXVOID_NO_ANIMATION = '1'
if (-not (Get-Module PSReadLine)) {{ Import-Module PSReadLine -MinimumVersion 2.1.0 -ErrorAction Stop }}
if ((Get-Module PSReadLine).Version -lt [version]'2.1.0') {{ throw 'Predictive PSReadLine was not loaded at startup.' }}
if ({'$true' if legacy else '$false'} -and (Get-Module PSReadLine).Version -ne [version]'2.1.0') {{ throw 'Legacy test did not load PSReadLine 2.1.0.' }}
Set-PSReadLineOption -HistorySavePath {quote(history)} -HistorySaveStyle SaveIncrementally -PredictionSource None
$binding = (Get-PSReadLineKeyHandler -Chord 'RightArrow').Function
. {quote(ROOT / 'windows/manager.ps1')}
$opts = Get-PSReadLineOption
if ([string]$opts.PredictionSource -ne 'History') {{ throw 'History predictions were not enabled.' }}
if ((Get-Command Set-PSReadLineOption).Parameters.ContainsKey('PredictionViewStyle') -and [string]$opts.PredictionViewStyle -ne 'InlineView') {{ throw 'Inline view was not selected.' }}
if ((Get-PSReadLineKeyHandler -Chord 'RightArrow').Function -ne $binding) {{ throw 'Right Arrow binding was replaced.' }}
Apply-PVSuggestions $false
if ([string](Get-PSReadLineOption).PredictionSource -ne 'None') {{ throw 'History predictions were not disabled.' }}
Apply-PVSuggestions $true
if ($PSVersionTable.PSEdition -eq 'Core' -and $PSVersionTable.PSVersion -ge [version]'7.2') {{
    Set-PSReadLineOption -PredictionSource HistoryAndPlugin
    Apply-PVSuggestions $false
    if ([string](Get-PSReadLineOption).PredictionSource -ne 'Plugin') {{ throw 'Disabling history removed plugin predictions.' }}
    Apply-PVSuggestions $true
    if ([string](Get-PSReadLineOption).PredictionSource -ne 'HistoryAndPlugin') {{ throw 'Enabling history removed plugin predictions.' }}
}}
function global:Get-VoidSuggestProof {{ Write-Host '[[HISTORY-EXECUTED]]' }}
Write-Host '[[PREDICTION-READY]]'
""", encoding='utf-8')
        session(shell, setup, True, legacy)
        assert history.exists() and 'Get-VoidSuggestProof' in history.read_text(encoding='utf-8-sig')
        session(shell, setup, False, legacy)
        print(f'PASS: {shell} {"PSReadLine 2.1" if legacy else "current PSReadLine"} inline history suggestion, accept and persistence')


if __name__ == '__main__':
    try:
        for shell in ('powershell.exe', 'pwsh.exe'):
            run(shell)
        run('powershell.exe', legacy=True)
    except Exception as exc:
        print('::error::' + str(exc).replace('\n', '%0A').replace('\r', '%0D'), flush=True)
        raise
