"""Optional short full-screen Asciimatics showcase for Windows Terminal."""
from asciimatics.effects import Cycle, Stars
from asciimatics.renderers import FigletText
from asciimatics.scene import Scene
from asciimatics.screen import Screen


def demo(screen):
    title = FigletText('TermuxVoid', font='small')
    effects = [Stars(screen, 50), Cycle(screen, title, max(0, screen.height // 2 - 3))]
    screen.play([Scene(effects, 100)], stop_on_resize=True, repeat=False, allow_int=True)


if __name__ == '__main__':
    try:
        Screen.wrapper(demo)
    except KeyboardInterrupt:
        pass
