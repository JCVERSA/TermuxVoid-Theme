"""PowerShell Void full-screen showcase, with a non-consuming idle mode."""
import sys
import time

from asciimatics.effects import Cycle, Stars
from asciimatics.renderers import FigletText
from asciimatics.scene import Scene
from asciimatics.screen import Screen


def scene(screen):
    title = FigletText('PowerShell Void', font='small')
    return Scene([Stars(screen, 50), Cycle(screen, title, max(0, screen.height // 2 - 3))], 100)


def demo(screen):
    screen.play([scene(screen)], stop_on_resize=True, repeat=False, allow_int=True)


def idle_demo(screen, baseline):
    # PSReadLine owns the input queue. Never consume its input in idle mode.
    # Windows' session input tick notices keyboard/mouse activity even when
    # PSReadLine has already queued the keystroke on its own reader thread.
    import ctypes
    from ctypes import wintypes

    class LastInputInfo(ctypes.Structure):
        _fields_ = [('cbSize', wintypes.UINT), ('dwTime', wintypes.DWORD)]

    def last_input_tick():
        value = LastInputInfo(ctypes.sizeof(LastInputInfo), 0)
        if not ctypes.windll.user32.GetLastInputInfo(ctypes.byref(value)):
            raise OSError('GetLastInputInfo failed')
        return value.dwTime

    screen.get_event = lambda: None
    screen.set_scenes([scene(screen)])
    while last_input_tick() == baseline and not screen.has_resized():
        screen.draw_next_frame(repeat=True)
        time.sleep(0.05)


if __name__ == '__main__':
    try:
        if len(sys.argv) == 3 and sys.argv[1] == '--idle':
            Screen.wrapper(idle_demo, arguments=[int(sys.argv[2])])
        else:
            Screen.wrapper(demo)
    except KeyboardInterrupt:
        pass
