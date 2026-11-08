"""Static checks for the Windows prompt and its original Termux palette."""
import json
from pathlib import Path
import tomllib

ROOT = Path(__file__).resolve().parent.parent
config = tomllib.loads((ROOT / 'windows/starship.toml').read_text(encoding='utf-8'))
assert all(f'${module}' in config['format'] for module in (
    'directory', 'git_branch', 'git_status', 'nodejs', 'python', 'rust', 'dotnet', 'package', 'cmd_duration', 'time', 'jobs', 'character'
))
assert '${env_var.USERNAME}' in config['format']
assert '$env_value' in config['env_var']['USERNAME']['format']
assert config['time']['disabled'] is False
assert config['character']['success_symbol'] != config['character']['error_symbol']
assert config['jobs']['symbol']

colors = {}
for line in (ROOT / 'assets/colors.properties').read_text().splitlines():
    if line and not line.startswith('#'):
        key, value = line.split('=', 1)
        colors[key] = value.lower()
scheme = json.loads((ROOT / 'windows/termuxvoid-scheme.json').read_text())
keys = ['black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
        'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue',
        'brightPurple', 'brightCyan', 'brightWhite']
for index, key in enumerate(keys):
    assert scheme[key].lower() == colors[f'color{index}'], key
for key in ('foreground', 'background'):
    assert scheme[key].lower() == colors[key], key
print('PASS: Windows prompt configuration and palette')
