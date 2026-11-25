"""Exercise the installer against private HTTP archives, never GitHub or a live HOME."""
import io
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tarfile
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import quote


ROOT = Path(__file__).resolve().parents[1]
INPUTS = ("install.sh", "uninstall.sh", "nemo-grid-compensator",
          "startup/nemo-grid-compensator-session", "startup/nemo-grid-compensator.desktop")


@unittest.skipUnless(sys.platform == "linux" and os.geteuid() != 0,
                     "requires Linux, installed runtime dependencies, and a non-root user")
class InstallTests(unittest.TestCase):
    def setUp(self):
        self.workspace = tempfile.TemporaryDirectory(prefix="nemo install tests ")
        self.addCleanup(self.workspace.cleanup)
        self.folder = Path(self.workspace.name)
        self.home = self.folder / "home"
        self.home.mkdir()
        self.temp = self.folder / "temporary"
        self.temp.mkdir()
        self.bin = self.folder / "bin"
        self.bin.mkdir()
        # Deliberately no Git and no curl unless this test explicitly adds it.
        for name in ("id", "dirname", "mktemp", "rm", "mkdir", "install", "cmp",
                     "stat", "mv", "sh", "systemd-run", "systemctl", "xrandr",
                     "xwininfo", "xprop", "stdbuf", "gsettings", "flock"):
            source = shutil.which(name)
            self.assertIsNotNone(source, f"Missing test dependency: {name}")
            (self.bin / name).symlink_to(source)
        self.env = dict(os.environ, HOME=str(self.home), PATH=str(self.bin),
                        TMPDIR=str(self.temp), XDG_CONFIG_HOME=str(self.home / "config"),
                        XDG_STATE_HOME=str(self.home / "state"))
        self.env.pop("NEMO_GRID_COMPENSATOR_LOCAL", None)
        for key in ("DISPLAY", "XDG_SESSION_TYPE", "XDG_SESSION_ID"):
            self.env.pop(key, None)
        self.requests = []
        self.status = 200
        self.archive = self.make_archive()
        self.requested = threading.Event()
        self.release = threading.Event()
        self.slow = False
        fixture = self

        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                fixture.requests.append(self.path)
                self.send_response(fixture.status)
                self.end_headers()
                fixture.requested.set()
                if fixture.slow:
                    fixture.release.wait(10)
                try:
                    self.wfile.write(fixture.archive)
                except (BrokenPipeError, ConnectionResetError):
                    pass

            def log_message(self, *_args):
                pass

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(self.close_server)

    def close_server(self):
        self.release.set()
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def make_archive(self, replacements=None, extras=(), omit=()):
        output = io.BytesIO()
        with tarfile.open(fileobj=output, mode="w:gz") as archive:
            for relative in INPUTS:
                if relative in omit:
                    continue
                data = (replacements or {}).get(relative, (ROOT / relative).read_bytes())
                member = tarfile.TarInfo("project-revision/" + relative)
                member.size = len(data)
                archive.addfile(member, io.BytesIO(data))
            for member, data in extras:
                archive.addfile(member, io.BytesIO(data))
        return output.getvalue()

    def downloader(self, name):
        actual = shutil.which(name)
        self.assertIsNotNone(actual, f"Install {name} to run both download paths")
        # Only this test shim changes HTTPS URLs to loopback HTTP. The production
        # installer has a fixed GitHub endpoint and no mirror/environment override.
        script = f'''#!/usr/bin/python3
import subprocess, sys
from urllib.parse import urlsplit
args = sys.argv[1:]
url = args[-1]
assert url.startswith("https://api.github.com/repos/bobapplemac/nemo-grid-compensator/tarball/")
if {name!r} == "curl":
    for option in ("--proto", "--proto-redir"):
        index = args.index(option)
        assert args[index + 1] == "=https"
        del args[index:index + 2]
else:
    args.remove("--https-only")
args[-1] = "http://127.0.0.1:{self.server.server_port}" + urlsplit(url).path
sys.exit(subprocess.call([{actual!r}, *args]))
'''
        target = self.bin / name
        target.write_text(script)
        target.chmod(0o755)

    def run_install(self, *args, path=None, env=None):
        command = ["/bin/sh", str(path), *args] if path else ["/bin/bash", "-s", "--", *args]
        result = subprocess.run(command, input=None if path else (ROOT / "install.sh").read_bytes(),
                                cwd=self.folder, env=env or self.env, capture_output=True, timeout=30)
        self.assertEqual(list(self.temp.iterdir()), [], result.stderr.decode())
        return result

    def successful(self, result):
        self.assertEqual(result.returncode, 0, result.stdout.decode() + result.stderr.decode())

    def assert_installed(self):
        for source, destination in (
            ("nemo-grid-compensator", ".local/bin/nemo-grid-compensator"),
            ("uninstall.sh", ".local/libexec/nemo-grid-compensator-uninstall"),
            ("startup/nemo-grid-compensator-session", ".local/libexec/nemo-grid-compensator-session"),
            ("startup/nemo-grid-compensator.desktop", "config/autostart/nemo-grid-compensator.desktop"),
        ):
            path = self.home / destination
            self.assertEqual(path.read_bytes(), (ROOT / source).read_bytes())
            self.assertEqual(path.stat().st_mode & 0o777, 0o644 if destination.endswith(".desktop") else 0o755)

    def test_curl_stdin_and_offline_uninstall(self):
        self.downloader("curl")
        self.successful(self.run_install())
        self.assert_installed()
        self.assertEqual(self.requests, ["/repos/bobapplemac/nemo-grid-compensator/tarball/main"])
        (self.bin / "curl").unlink()
        uninstall = self.home / ".local/libexec/nemo-grid-compensator-uninstall"
        result = subprocess.run(["/bin/sh", str(uninstall), "--files-only"], env=self.env,
                                capture_output=True, timeout=10)
        self.successful(result)
        self.assertFalse(uninstall.exists())
        self.assertFalse((self.home / ".local/bin/nemo-grid-compensator").exists())
        self.assertEqual(len(self.requests), 1)

    def test_wget_stdin(self):
        self.downloader("wget")
        self.successful(self.run_install())
        self.assert_installed()

    def test_explicit_refs(self):
        self.downloader("curl")
        for ref in ("feature/remote-install", "v0.1.0rc2", "976f9d52859ae33157d83e9fea10f1364f6b5e44"):
            with self.subTest(ref=ref):
                self.successful(self.run_install("--ref", ref))
                self.assertEqual(self.requests[-1], "/repos/bobapplemac/nemo-grid-compensator/tarball/" + quote(ref, safe=""))
        self.assertEqual(len(self.requests), 3)

    def test_checkout_installs_offline(self):
        self.successful(self.run_install(path=ROOT / "install.sh"))
        self.assert_installed()
        self.assertEqual(self.requests, [])

    def test_extracted_archive_installs_offline(self):
        extracted = self.folder / "extracted archive"
        for relative in INPUTS:
            target = extracted / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes((ROOT / relative).read_bytes())
        self.successful(self.run_install(path=extracted / "install.sh"))
        self.assert_installed()
        self.assertEqual(self.requests, [])

    def test_standalone_downloaded_script(self):
        self.downloader("curl")
        installer = self.folder / "downloaded-installer.sh"
        installer.write_bytes((ROOT / "install.sh").read_bytes())
        self.successful(self.run_install(path=installer))
        self.assert_installed()

    def test_ref_overrides_checkout_and_uses_archive_revision(self):
        self.downloader("curl")
        newer = (ROOT / "nemo-grid-compensator").read_bytes().replace(
            b'VERSION = "0.1.0rc2"', b'VERSION = "0.1.0rc2-fixture"')
        launcher = b"#!/bin/sh\n# Another revision's launcher\n"
        self.archive = self.make_archive({"nemo-grid-compensator": newer,
                                          "startup/nemo-grid-compensator-session": launcher})
        result = self.run_install("--ref=fixture", path=ROOT / "install.sh")
        self.successful(result)
        self.assertIn(b"0.1.0rc2-fixture", result.stdout)
        self.assertEqual((self.home / ".local/bin/nemo-grid-compensator").read_bytes(), newer)
        self.assertEqual((self.home / ".local/libexec/nemo-grid-compensator-session").read_bytes(), launcher)

    def test_reinstall_preserves_nemo_configuration_and_recovery(self):
        self.downloader("curl")
        self.successful(self.run_install())
        saved = {}
        for relative in ("config/nemo/desktop-metadata", "state/nemo-grid-compensator/transaction.json",
                         "state/nemo-grid-compensator/grid.json", ".local/libexec/custom-launcher"):
            path = self.home / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text("preserve this fixture exactly\n")
            saved[path] = path.read_bytes()
        self.successful(self.run_install())
        for path, expected in saved.items():
            self.assertEqual(path.read_bytes(), expected)
        self.assertEqual(len(self.requests), 2)
        # The installed offline uninstaller must retain pending journals too.
        result = subprocess.run(["/bin/sh", str(self.home / ".local/libexec/nemo-grid-compensator-uninstall"),
                                 "--files-only", "--purge-state"], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"transaction is pending", result.stderr)
        for path, expected in saved.items():
            self.assertEqual(path.read_bytes(), expected)

    def start_fixture(self, active=False):
        # Exercise startup without contacting the live user manager or display.
        systemctl = self.bin / "systemctl"
        systemctl.unlink()
        systemctl.write_text('''#!/bin/sh
printf '%s\\n' "$*" >> "$HOME/systemctl.calls"
case "$*" in
    '--user show-environment') exit 0 ;;
    '--user is-active --quiet nemo-grid-compensator.service') [ -f "$HOME/active" ] ;;
    '--user stop nemo-grid-compensator.service') rm -f "$HOME/active" ;;
    *) exit 2 ;;
esac
''')
        systemctl.chmod(0o755)
        if active:
            (self.home / "active").touch()
        app = b'''#!/usr/bin/python3
import os, sys
from pathlib import Path
home = Path.home()
if "--init" in sys.argv:
    with (home / "actions").open("a") as stream:
        stream.write("initialize\\n")
    state = Path(os.environ["XDG_STATE_HOME"]) / "nemo-grid-compensator"
    state.mkdir(parents=True, exist_ok=True)
    (state / "grid.json").write_text("initialized fixture")
else:
    print("nemo-grid-compensator 0.1.0rc2")
'''
        launcher = b'#!/bin/sh\nprintf "launch\\n" >> "$HOME/actions"\n: > "$HOME/active"\n'
        self.archive = self.make_archive({"startup/nemo-grid-compensator-session": launcher,
                                          "nemo-grid-compensator": app})
        return dict(self.env, XDG_SESSION_TYPE="x11", DISPLAY=":fixture", XDG_SESSION_ID="fixture")

    def test_start_delegates_to_existing_supervision_path(self):
        self.downloader("curl")
        env = self.start_fixture(active=True)
        self.successful(self.run_install("--ref", "fixture", "--start", env=env))
        self.assertEqual((self.home / "actions").read_text(), "initialize\nlaunch\n")
        calls = (self.home / "systemctl.calls").read_text().splitlines()
        self.assertEqual(calls.count("--user stop nemo-grid-compensator.service"), 1)

    def test_default_graphical_install_initializes_and_starts_once(self):
        self.downloader("curl")
        env = self.start_fixture()
        self.successful(self.run_install(env=env))
        self.assertEqual((self.home / "actions").read_text(), "initialize\nlaunch\n")
        self.successful(self.run_install(env=env))
        self.assertEqual((self.home / "actions").read_text(), "initialize\nlaunch\n")

    def test_no_start_overrides_graphical_default_through_bootstrap(self):
        self.downloader("curl")
        env = self.start_fixture()
        result = self.run_install("--no-start", env=env)
        self.successful(result)
        self.assertFalse((self.home / "actions").exists())
        self.assertFalse((self.home / "systemctl.calls").exists())
        self.assertIn(b"next Cinnamon login", result.stdout)

    def test_graphical_upgrade_preserves_checkpoint_and_pending_journal(self):
        self.downloader("curl")
        env = self.start_fixture(active=True)
        state = self.home / "state/nemo-grid-compensator"
        state.mkdir(parents=True)
        for name in ("grid.json", "transaction.json"):
            (state / name).write_text("retain existing recovery state")
        self.successful(self.run_install(env=env))
        self.assertEqual((self.home / "actions").read_text(), "launch\n")
        for name in ("grid.json", "transaction.json"):
            self.assertEqual((state / name).read_text(), "retain existing recovery state")

    def test_explicit_start_requires_graphical_session(self):
        self.downloader("curl")
        result = self.run_install("--start")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"X11 Cinnamon login", result.stderr)
        self.assertFalse((self.home / ".local").exists())

    def test_nongraphical_default_defers_start(self):
        self.downloader("curl")
        result = self.run_install()
        self.successful(result)
        self.assertIn(b"next Cinnamon login", result.stdout)
        self.assert_installed()

    def test_rejects_invalid_archives_before_executing_installer(self):
        self.downloader("curl")
        marker = b'#!/bin/sh\n: > "$HOME/executed"\n'
        traversal = tarfile.TarInfo("project-revision/../escaped")
        symlink = tarfile.TarInfo("project-revision/link")
        symlink.type, symlink.linkname = tarfile.SYMTYPE, "/tmp/escaped"
        hardlink = tarfile.TarInfo("project-revision/hardlink")
        hardlink.type, hardlink.linkname = tarfile.LNKTYPE, "project-revision/install.sh"
        duplicate = tarfile.TarInfo("project-revision/install.sh")
        other_root = tarfile.TarInfo("other-revision/file")
        valid = self.make_archive()
        cases = [b"<html>not an archive</html>", valid[:100], valid[:-8],
                 valid[:-8] + bytes([valid[-8] ^ 1]) + valid[-7:]]
        for extra in (traversal, symlink, hardlink, duplicate, other_root):
            cases.append(self.make_archive({"install.sh": marker}, [(extra, b"")]))
        cases.append(self.make_archive({"install.sh": marker}, omit=("uninstall.sh",)))
        cases.append(self.make_archive({"install.sh": b"if then\n"}))
        cases.append(self.make_archive({"nemo-grid-compensator": b"invalid Python syntax!\n"}))
        for index, data in enumerate(cases):
            with self.subTest(case=index):
                self.archive = data
                self.assertNotEqual(self.run_install().returncode, 0)
                self.assertFalse((self.home / "executed").exists())
                self.assertFalse((self.home / ".local").exists())

    def test_http_error_cleans_up(self):
        for tool in ("curl", "wget"):
            with self.subTest(tool=tool):
                self.downloader(tool)
                self.status = 404
                self.assertNotEqual(self.run_install().returncode, 0)
                (self.bin / tool).unlink()
        self.assertFalse((self.home / ".local").exists())

    def test_missing_downloader_and_bad_arguments(self):
        self.assertNotEqual(self.run_install().returncode, 0)
        self.assertEqual(self.run_install("--ref").returncode, 2)
        self.assertEqual(self.run_install("--ref=").returncode, 2)
        self.assertEqual(self.run_install("--ref", "--start").returncode, 2)
        self.assertEqual(self.run_install("--unknown").returncode, 2)
        self.assertEqual(self.requests, [])

    def test_local_dependency_detection_is_retained(self):
        (self.bin / "xrandr").unlink()
        result = self.run_install(path=ROOT / "install.sh")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"Missing dependency: xrandr", result.stderr)
        self.assertFalse((self.home / ".local").exists())

    def test_recursive_bootstrap_is_blocked(self):
        self.downloader("curl")
        result = self.run_install(env=dict(self.env, NEMO_GRID_COMPENSATOR_LOCAL="1"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b"bootstrap again", result.stderr)
        self.assertEqual(self.requests, [])

    def test_sigterm_cleans_up_download(self):
        self.downloader("curl")
        self.slow = True
        process = subprocess.Popen(["/bin/bash", "-s"], stdin=subprocess.PIPE,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   cwd=self.folder, env=self.env, start_new_session=True)
        try:
            process.stdin.write((ROOT / "install.sh").read_bytes())
            process.stdin.close()
            process.stdin = None
            self.assertTrue(self.requested.wait(10), "download never started")
            os.killpg(process.pid, signal.SIGTERM)
            process.communicate(timeout=10)
            self.assertNotEqual(process.returncode, 0)
            self.assertEqual(list(self.temp.iterdir()), [])
        finally:
            self.release.set()
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()


if __name__ == "__main__":
    unittest.main()
