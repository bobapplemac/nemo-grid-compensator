"""Hold a virtual primary button on the isolated X11 display while applying."""
from ctypes import CDLL, c_char_p, c_int, c_ulong, c_uint, c_void_p
import subprocess
import sys

x11 = CDLL("libX11.so.6")
xtst = CDLL("libXtst.so.6")
x11.XOpenDisplay.argtypes = [c_char_p]
x11.XOpenDisplay.restype = c_void_p
x11.XSync.argtypes = [c_void_p, c_int]
x11.XCloseDisplay.argtypes = [c_void_p]
fake = xtst.XTestFakeButtonEvent
fake.argtypes = [c_void_p, c_uint, c_int, c_ulong]
display = x11.XOpenDisplay(None)
assert display, "Missing isolated X11 display"
try:
    fake(display, 1, True, 0)
    x11.XSync(display, False)
    result = subprocess.run([sys.argv[1], "--once", "--min-pitch", "104x100",
                             "--pitch", "108x103"], text=True, capture_output=True)
    assert result.returncode and "primary mouse button" in result.stderr, result
    print("PASS: X11 primary button held deferred the planned adjustment")
finally:
    fake(display, 1, False, 0)
    x11.XSync(display, False)
    x11.XCloseDisplay(display)
