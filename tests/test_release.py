import errno
import json
import os
from pathlib import Path
import runpy
import tempfile
import unittest
from unittest.mock import Mock, patch

app = runpy.run_path(str(Path(__file__).resolve().parents[1] / "nemo-grid-compensator"))
Gio, GLib = app["Gio"], app["GLib"]


class SafetyTests(unittest.TestCase):
    def test_circuit_breaker_survives_restart_and_expires(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "compositor.json"
            guard = app["CrashGuard"](path)
            for second in (10, 30, 55):
                guard.note_loss(second)
            self.assertEqual(guard.resume_at, 145)
            guard = app["CrashGuard"](path)
            self.assertEqual(guard.resume_at, 145)
            guard.note_loss(160)
            self.assertLess(guard.resume_at, 160)

    def test_disallows_symlink_and_hard_link_state(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "target"
            path.write_text("{}")
            symlink = Path(folder) / "symlink"
            symlink.symlink_to(path)
            with self.assertRaises(app["UnsafeRecovery"]):
                app["read_json"](symlink)
            os.link(path, Path(folder) / "other")
            with self.assertRaises(app["UnsafeRecovery"]):
                app["read_json"](path)

    def test_busy_and_timeout_retry_but_bad_permissions_do_not(self):
        retry = app["retryable"]
        self.assertTrue(retry(OSError(errno.EAGAIN, "try again")))
        self.assertFalse(retry(PermissionError(errno.EACCES, "denied")))
        self.assertTrue(retry(GLib.Error.new_literal(Gio.io_error_quark(), "busy", Gio.IOErrorEnum.BUSY)))
        self.assertTrue(retry(GLib.Error.new_literal(Gio.dbus_error_quark(), "timeout", Gio.DBusError.NO_REPLY)))
        self.assertFalse(retry(GLib.Error.new_literal(Gio.io_error_quark(), "failed", Gio.IOErrorEnum.PERMISSION_DENIED)))

    def test_exiting_procfs_race(self):
        with patch.object(Path, "read_text", side_effect=ProcessLookupError):
            self.assertTrue(app["process_exited"](101))

    def test_untrusted_journal_cannot_target_outside_desktop(self):
        class Desktop:
            def desktop_directory(self):
                return Path("/tmp/desktop")
        pending = {"files": [{"path": "/tmp/other", "identity": [], "old": "0,0", "new": "1,1"}]}
        with self.assertRaises(app["UnsafeRecovery"]):
            app["validate_recovery_files"](Desktop(), pending)

    def test_released_journal_cannot_enable_icons(self):
        class Settings:
            def get_boolean(self, key):
                raise AssertionError("Released visibility should not consult current setting")
        class Desktop:
            settings = Settings()
        app["release_visibility"](Desktop(), {"visibility": "released"})

    def recovery_fixture(self, folder):
        desktop = object.__new__(app["Desktop"])
        desktop.journal = folder / "transaction.json"
        desktop.checkpoint = folder / "grid.json"
        desktop.ending = False
        desktop.settings = Mock()
        desktop.settings.get_boolean.side_effect = lambda key: key != app["SETTING"] or desktop.visible
        desktop.visible = False
        desktop.check_session = Mock()
        desktop.require_compositor = Mock(return_value=":1.7")
        desktop.set_enabled = Mock(side_effect=lambda value: setattr(desktop, "visible", value))
        desktop.read = Mock(return_value=(b"[desktop-monitor-0]\ndesktop-grid-adjust=60;100;\n", 0o600))
        desktop.file_icons = Mock(return_value={})
        desktop.mount_groups = Mock(return_value={})
        desktop.area = Mock(return_value=("screen", 1000, 850))
        desktop.vertical_offset = Mock(return_value=45)
        return desktop

    def test_prepared_is_discarded_without_toggling_visibility(self):
        with tempfile.TemporaryDirectory() as path:
            folder = Path(path)
            desktop = self.recovery_fixture(folder)
            pending = {"visibility": "prepared", "old": {"adjust": [60, 100]},
                       "new": {"adjust": [61, 100]}, "files": []}
            app["write_json"](desktop.journal, pending)
            with patch.dict(desktop.recover.__globals__, {"STATE": folder}):
                desktop.recover()
            self.assertFalse(desktop.journal.exists())
            desktop.set_enabled.assert_not_called()

    def test_ambiguity_retains_journal_and_restores_only_owned_visibility(self):
        for initializing in (False, True):
            for phase in ("held", "prepared", "released"):
                with self.subTest(initializing=initializing, phase=phase):
                    with tempfile.TemporaryDirectory() as path:
                        folder = Path(path)
                        desktop = self.recovery_fixture(folder)
                        if initializing:
                            pending = {"initialization": True, "writing": phase != "prepared",
                                       "restore_icons": True, "old": ["before"], "new": ["after"]}
                        else:
                            pending = {"old": {"adjust": [90, 100]}, "new": {"adjust": [99, 100]}, "files": []}
                        pending["visibility"] = phase
                        app["write_json"](desktop.journal, pending)
                        with patch.dict(desktop.recover.__globals__, {"STATE": folder}):
                            with self.assertRaises(app["UnsafeRecovery"]):
                                desktop.recover()
                        expected = dict(pending, visibility="released") if phase == "held" else pending
                        self.assertEqual(json.loads(desktop.journal.read_text()), expected)
                        self.assertEqual(desktop.visible, phase == "held")
                        self.assertFalse(desktop.checkpoint.exists())

    def test_held_initialization_restores_availability_when_metadata_read_fails(self):
        with tempfile.TemporaryDirectory() as path:
            folder = Path(path)
            desktop = self.recovery_fixture(folder)
            desktop.read.side_effect = PermissionError("fixture")
            app["write_json"](desktop.journal, {"initialization": True, "restore_icons": True,
                                                "visibility": "held", "writing": True,
                                                "old": [], "new": []})
            with patch.dict(desktop.recover.__globals__, {"STATE": folder}):
                with self.assertRaises(PermissionError):
                    desktop.recover()
            self.assertTrue(desktop.visible)
            self.assertEqual(json.loads(desktop.journal.read_text())["visibility"], "released")

    def test_verification_skips_changed_identities_but_rejects_wrong_surviving_cell(self):
        for displaced in (False, True):
            with self.subTest(displaced=displaced), tempfile.TemporaryDirectory() as path:
                folder = Path(path)
                desktop = self.recovery_fixture(folder)
                file = "file:/tmp/still-present"
                axes = [app["Axis"].for_area(length, adjust, index, 45)
                        for index, (length, adjust) in enumerate(((1000, 60), (850, 100)))]
                xy = [axes[0].pixel(displaced), axes[1].pixel(0)]
                desktop.file_icons.return_value = {
                    file: {"position": f"{xy[0]},{xy[1]}", "identity": [1]},
                    "file:/tmp/replaced": {"position": "12,20", "identity": [2]},
                }
                desktop.mount_groups.return_value = {"replaced.volume": "new"}
                entries = (file, "file:/tmp/replaced", "file:/tmp/gone",
                           "group:gone.volume", "group:replaced.volume")
                checkpoint = {"area": ["screen", 1000, 850], "adjust": [60, 100],
                              "offset": 45, "cells": {key: {"cell": [0, 0], "identity": [1]}
                                                      for key in entries}}
                app["write_json"](desktop.journal, {"old": {"adjust": [70, 100]}, "new": checkpoint,
                                                    "files": [], "visibility": "released"})
                with patch.dict(desktop.recover.__globals__, {"STATE": folder}):
                    if displaced:
                        with self.assertRaisesRegex(app["UnsafeRecovery"], "different grid cell"):
                            desktop.recover()
                    else:
                        desktop.recover()
                self.assertEqual(desktop.journal.exists(), displaced)
                self.assertEqual(desktop.checkpoint.exists(), not displaced)
                if not displaced:
                    self.assertEqual(list(json.loads(desktop.checkpoint.read_text())["cells"]), [file])
                desktop.set_enabled.assert_not_called()

    def test_partial_bootstrap_leaves_existing_grid_and_explicit_init_fills_keys(self):
        with tempfile.TemporaryDirectory() as path:
            desktop = self.recovery_fixture(Path(path))
            raw = b"[desktop-monitor-0]\ndesktop-grid-adjust=60;100;\n[unrelated]\nretain=yes\n"
            desktop.read.return_value = raw, 0o600
            bootstrap = app["bootstrap_initialization"]
            with patch.dict(bootstrap.__globals__, {"initialize": Mock()}) as env:
                with patch("builtins.print") as output:
                    bootstrap(desktop, object())
                env["initialize"].assert_not_called()
                self.assertIn("--init --dry-run", output.call_args.args[0])
            result = app["initial_metadata"](raw, desktop.settings)
            restored = app["parse_metadata"](result)
            self.assertEqual(app["adjustment"](restored), (60, 100))
            self.assertEqual(dict(restored[app["GROUP"]]), dict(app["INITIAL_KEYS"], **{app["ADJUST"]: "60;100;"}))
            self.assertEqual(restored["unrelated"]["retain"], "yes")


if __name__ == "__main__":
    unittest.main()
