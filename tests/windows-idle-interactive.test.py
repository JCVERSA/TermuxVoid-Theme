"""Exercise PSReadLine's real OnIdle integration in a Windows pseudoconsole.

A fake showcase writes a marker and briefly sleeps, so the test can inject input
without depending on physical keyboard events in GitHub's headless session.
"""
import os
from pathlib import Path
import queue
import subprocess
import sys
import tempfile
import threading
import time

from winpty import PtyProcess

ROOT = Path(__file__).resolve().parent.parent


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def run(shell):
    with tempfile.TemporaryDirectory(prefix='powershell-void-idle-') as tmp:
        folder = Path(tmp)
        marker = folder / 'idle-fired'
        demo = folder / 'demo.py'
        demo.write_text("import os,time\nopen(os.environ['IDLE_MARKER'],'w').write('started')\ntime.sleep(2)\n", encoding='utf-8')
        setup = folder / 'interactive.ps1'
        setup.write_text(f"""
$ErrorActionPreference = 'Stop'
Import-Module PSReadLine
$env:WT_SESSION = 'test-session'
$env:TERMUXVOID_NO_ANIMATION = '1'
Add-Type -TypeDefinition 'namespace PowerShellVoid {{ public static class Input {{ public static uint IdleMilliseconds() {{ return 999999; }} public static uint LastInputTick() {{ return 1; }} }} }}'
. {quote(ROOT / 'windows/animation.ps1')}
function global:Get-TermuxVoidAnimationPaths {{ return @{{
    Python = {quote(sys.executable)}
    Demo = {quote(demo)}
    NodeRuntime = ''
    Node = ''
    Base = {quote(folder)}
    Settings = {quote(folder / 'settings.json')}
    Setup = ''
}} }}
$env:TERMUXVOID_NO_ANIMATION = $null
$global:PowerShellVoidSettings = @{{ Welcome = $false; Banner = $false; Idle = $true; IdleSeconds = 2 }}
Start-PowerShellVoidIdleMonitor
Write-Host '[[READY]]'
""", encoding='utf-8')
        env = os.environ.copy()
        env['IDLE_MARKER'] = str(marker)
        proc = PtyProcess.spawn([shell, '-NoProfile', '-NoLogo', '-NoExit', '-File', str(setup)], env=env, dimensions=(30, 100))
        chunks = queue.Queue()
        output = []

        def reader():
            try:
                while True:
                    chunks.put(proc.read(4096))
            except (EOFError, OSError):
                pass

        threading.Thread(target=reader, daemon=True).start()

        def wait_output(text, timeout=20):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                try:
                    output.append(chunks.get(timeout=.2))
                except queue.Empty:
                    pass
                if text in ''.join(output):
                    return
            raise AssertionError(f'{shell}: missing {text!r}; output: {"".join(output)[-6000:]}')

        def wait_marker(timeout=12):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                if marker.exists():
                    return
                time.sleep(.1)
            proc.write("Write-Host ('[[DEBUG]] failed=' + $global:PowerShellVoidIdleFailed + ' error=' + $global:PowerShellVoidIdleError)\r")
            time.sleep(1)
            raise AssertionError(f'{shell}: idle event did not trigger; output: {"".join(output)[-6000:]}')

        try:
            wait_output('[[READY]]')
            # A partially typed command must not trigger the idle screen.
            proc.write("Write-Output ('PAR" )
            time.sleep(4)
            assert not marker.exists(), f'{shell}: idle animation interrupted a partial command'
            proc.write("TIAL' + '-OK')\r")
            wait_output('PARTIAL-OK')
            # Running commands must not be interrupted by an idle screen.
            proc.write("Start-Sleep -Seconds 4; Write-Output ('DONE' + '-SLEEP')\r")
            time.sleep(3)
            assert not marker.exists(), f'{shell}: idle animation interrupted a running command'
            wait_output('DONE-SLEEP')
            wait_marker()
            # Input arriving while the showcase is running must reach PSReadLine.
            proc.write("Write-Output ('KEY' + '-PRESERVED')\r")
            wait_output('KEY-PRESERVED')
            proc.write('exit\r')
            print(f'PASS: {shell} PSReadLine idle integration')
        finally:
            proc.close(force=True)


def run_real_showcase(arguments):
    proc = PtyProcess.spawn([sys.executable, str(ROOT / 'windows/animation-demo.py'), *arguments], dimensions=(30, 100))
    output = []

    def reader():
        try:
            while True:
                output.append(proc.read(4096))
        except (EOFError, OSError):
            pass

    threading.Thread(target=reader, daemon=True).start()
    try:
        deadline = time.monotonic() + 15
        while proc.isalive() and time.monotonic() < deadline:
            time.sleep(.1)
        assert not proc.isalive(), f'showcase did not finish: {arguments!r}'
        assert proc.exitstatus == 0, f'showcase failed: {arguments!r}: {"".join(output)[-6000:]}'
        print(f'PASS: Asciimatics in Windows pseudoconsole: {arguments!r}')
    finally:
        proc.close(force=True)


def run_startup_effects():
    with tempfile.TemporaryDirectory(prefix='powershell-void-effects-') as tmp:
        folder = Path(tmp)
        subprocess.run(['cmd.exe', '/c', 'npm.cmd', 'install', '--prefix', str(folder / 'node'),
                        '--no-audit', '--no-fund', '--ignore-scripts', 'ascii.rest@0.4.0'], check=True)
        cli = folder / 'node/node_modules/ascii.rest/dist/cli.js'
        setup = folder / 'effects.ps1'
        setup.write_text(f"""
$ErrorActionPreference = 'Stop'
$env:TERMUXVOID_NO_ANIMATION = '1'
. {quote(ROOT / 'windows/animation.ps1')}
function global:Get-TermuxVoidAnimationPaths {{ return @{{
    Python = {quote(sys.executable)}
    Node = {quote(cli)}
    NodeRuntime = ''
    Demo = {quote(ROOT / 'windows/animation-demo.py')}
    Base = {quote(folder)}
    Settings = {quote(folder / 'settings.json')}
    Setup = ''
}} }}
$env:TERMUXVOID_NO_ANIMATION = $null
Write-Host '[[EFFECT-READY]]'
""", encoding='utf-8')
        proc = PtyProcess.spawn(['pwsh.exe', '-NoProfile', '-NoLogo', '-NoExit', '-File', str(setup)], dimensions=(30, 120))
        chunks = queue.Queue()
        output = []

        def reader():
            try:
                while True:
                    chunks.put(proc.read(4096))
            except (EOFError, OSError):
                pass
        threading.Thread(target=reader, daemon=True).start()

        def wait_for(text, timeout=30):
            end = time.monotonic() + timeout
            while time.monotonic() < end:
                try:
                    output.append(chunks.get(timeout=.2))
                except queue.Empty:
                    pass
                if text in ''.join(output):
                    return
            raise AssertionError(f'missing {text!r}: {"".join(output)[-5000:]}')

        try:
            wait_for('[[EFFECT-READY]]')
            proc.write("Show-PowerShellVoidAnimation -Engine TTE; Write-Host ('FINISHED' + '-TTE')\r")
            wait_for('FINISHED-TTE')
            proc.write("Show-PowerShellVoidAnimation -Engine AsciiRest; Write-Host ('FINISHED' + '-BANNER')\r")
            wait_for('FINISHED-BANNER')
            text = ''.join(output)
            assert 'exited with code' not in text and 'unavailable' not in text and 'Traceback' not in text, text[-5000:]
            print('PASS: TTE and ascii.rest PowerShell helpers in Windows pseudoconsole')
        finally:
            proc.close(force=True)


if __name__ == '__main__':
    for executable in ('powershell.exe', 'pwsh.exe'):
        run(executable)
    run_real_showcase([])
    run_real_showcase(['--idle', '0'])
    run_startup_effects()
