"""Fault injection into a process attached only to the private test display."""
from pathlib import Path
import runpy
import sys

program, scenario = sys.argv[1:3]
loaded = runpy.run_path(program)
main = loaded["main"]
env = main.__globals__
base_apply = env["apply"]
base_quiesce = env["quiesce"]
base_update = env["file_update"]
base_atomic = env["atomic_write"]
base_write_json = env["write_json"]
base_release = env["release_visibility"]
desktop = None
injected = False

def apply(d, args):
    global desktop
    desktop = d
    if scenario == "unmount":
        current_mounts = d.mount_groups
        reads = 0
        def snapshot():
            nonlocal reads
            reads += 1
            expected_read = 3 if d.settings.get_boolean("volumes-visible") else 2
            return {"lab.volume": "existing-mount"} if reads == expected_read else current_mounts()
        d.mount_groups = snapshot
    return base_apply(d, args)

def stopped(*args):
    result = base_quiesce(*args)
    if scenario == "logout-stopped":
        print("INJECTED", scenario)
        desktop.ending = True
    return result

def update(*args, **kwargs):
    global injected
    if not kwargs.get("commit") or injected:
        return base_update(*args, **kwargs)
    result = base_update(*args, **kwargs)
    injected = True
    print("INJECTED", scenario)
    if scenario == "logout-gvfs":
        desktop.ending = True
    elif scenario == "create":
        (desktop.desktop_directory() / "concurrent.txt").touch()
    elif scenario == "rename":
        path = desktop.desktop_directory() / "fixture-02.txt"
        path.rename(path.with_name("renamed.txt"))
    elif scenario == "delete":
        (desktop.desktop_directory() / "fixture-02.txt").unlink()
    elif scenario in ("mount", "unmount"):
        desktop.mount_groups = ((lambda: {"lab.volume": "new-mount"}) if scenario == "mount"
                                else (lambda: {}))
    elif scenario == "dbus-timeout":
        raise env["GLib"].Error.new_literal(env["Gio"].dbus_error_quark(),
                                            "Injected D-Bus no reply",
                                            env["Gio"].DBusError.NO_REPLY)
    elif scenario == "gio-busy":
        raise env["GLib"].Error.new_literal(env["Gio"].io_error_quark(), "Injected busy",
                                            env["Gio"].IOErrorEnum.BUSY)
    return result

def atomic(path, *args, **kwargs):
    if path == env["METADATA"] and scenario == "fs-busy":
        raise OSError(env["errno"].EAGAIN, "Injected filesystem retry")
    result = base_atomic(path, *args, **kwargs)
    if path == env["METADATA"] and scenario == "logout-commit":
        desktop.ending = True
    return result

def write_json(path, data):
    result = base_write_json(path, data)
    if (scenario == "logout-prepared" and path == desktop.journal
            and data.get("visibility") == "prepared"):
        print("INJECTED", scenario)
        desktop.ending = True
    return result

def release(d, data):
    result = base_release(d, data)
    if scenario == "logout-remap":
        print("INJECTED", scenario)
        desktop.ending = True
    return result

env.update(apply=apply, quiesce=stopped, file_update=update, atomic_write=atomic,
           write_json=write_json, release_visibility=release)
sys.argv = [program, "--once", "--min-pitch", "104x100", "--pitch", "108x103"]
try:
    main()
except (OSError, RuntimeError, env["GLib"].Error) as error:
    print(error)
    sys.exit(1)
