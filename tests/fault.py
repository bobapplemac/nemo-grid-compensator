import os
from pathlib import Path
import runpy
import sys

program, phase = sys.argv[1:3]
loaded = runpy.run_path(program)
main = loaded["main"]
env = main.__globals__

def at(function, condition):
    def fault(*args, **kwargs):
        result = function(*args, **kwargs)
        if condition(args, kwargs):
            os._exit(86)
        return result
    return fault

if phase == "stopped":
    env["quiesce"] = at(env["quiesce"], lambda *_: True)
elif phase == "gvfs":
    env["file_update"] = at(env["file_update"], lambda _, kw: kw.get("commit"))
elif phase == "committed":
    env["atomic_write"] = at(env["atomic_write"], lambda args, _: args[0] == env["METADATA"])
else:
    raise ValueError(phase)
sys.argv = [program, "--once", "--min-pitch", "104x100", "--pitch", "108x103"]
main()
