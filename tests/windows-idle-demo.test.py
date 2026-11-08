"""Idle rendering must never consume PSReadLine input and must stop on activity."""
import ctypes
import importlib.util
from pathlib import Path
from types import SimpleNamespace

root = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('animation_demo', root / 'windows/animation-demo.py')
demo = importlib.util.module_from_spec(spec)
spec.loader.exec_module(demo)

class FakeScreen:
    frames = 0
    def set_scenes(self, scenes):
        assert scenes == ['scene']
    def has_resized(self):
        return False
    def draw_next_frame(self, repeat):
        assert repeat
        self.frames += 1
    def get_event(self):
        raise AssertionError('idle animation must not read input')

values = iter((42, 42, 43))
def fake_last_input(ptr):
    ptr._obj.dwTime = next(values)
    return True
old = getattr(ctypes, 'windll', None)
try:
    ctypes.windll = SimpleNamespace(user32=SimpleNamespace(GetLastInputInfo=fake_last_input))
    demo.scene = lambda screen: 'scene'
    demo.time.sleep = lambda seconds: None
    screen = FakeScreen()
    demo.idle_demo(screen, 42)
    assert screen.frames == 2
    assert screen.get_event() is None
finally:
    if old is None:
        del ctypes.windll
    else:
        ctypes.windll = old
print('PASS: idle demo stops on activity without reading input')
