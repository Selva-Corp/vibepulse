"""The watch wizard and the Claude-only paths of vibepulse_setup."""
import io
import json
import pathlib
import sys
import tempfile
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import vibepulse_setup as setup  # noqa: E402


class FakeResponse:
    def __init__(self, payload):
        self._raw = json.dumps(payload).encode()
        self.status = 200
        self.headers = {"Content-Type": "application/json"}

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def read(self, n=-1):
        return self._raw


def fake_urlopen(routes):
    def open_url(request, timeout=None):
        url = request.full_url if hasattr(request, "full_url") else request
        for suffix, payload in routes.items():
            if url.rstrip("/").endswith(suffix) or (
                    suffix == "/" and url.rstrip("/").endswith(":8737")):
                return FakeResponse(payload)
        raise OSError(f"unrouted {url}")
    return open_url


def ok_run(record):
    """Fake subprocess.run: satisfies the strict python probe, records argv."""
    class Completed:
        def __init__(self, stdout):
            self.returncode = 0
            self.stdout = stdout
            self.stderr = ""

    def run(argv, **kwargs):
        record.append(list(argv))
        if len(argv) >= 2 and argv[1] == "-c":
            return Completed("vibepulse-python-3.11+\n")
        return Completed("")
    return run


class ClaudeOnlyWithoutCodexTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.config = pathlib.Path(self.dir.name) / "config.json"
        self.out = io.StringIO()

    def tearDown(self):
        self.dir.cleanup()

    def main(self, argv, **kw):
        return setup.main(
            argv, config_path=self.config, python=sys.executable,
            codex=None, run=ok_run([]), urlopen=fake_urlopen({}),
            stdin_isatty=False, stdout=self.out, **kw)

    def test_claude_only_install_succeeds_without_codex_cli(self):
        rc = self.main(["install", "--providers", "claude", "--detail"])
        self.assertEqual(rc, 0, self.out.getvalue())
        self.assertIn("no Codex CLI found", self.out.getvalue())
        saved = setup.load_config(self.config)
        self.assertTrue(saved.claude_interactions)
        self.assertTrue(saved.interaction_detail)
        self.assertFalse(saved.codex_interactions)

    def test_codex_providers_still_require_the_cli(self):
        for providers in ("codex", "both"):
            out = io.StringIO()
            rc = setup.main(
                ["install", "--providers", providers],
                config_path=self.config, python=sys.executable, codex=None,
                run=ok_run([]), urlopen=fake_urlopen({}),
                stdin_isatty=False, stdout=out)
            self.assertEqual(rc, 1)
            self.assertIn("Codex executable not found", out.getvalue())

    def test_uninstall_without_cli_disables_codex_only(self):
        self.main(["install", "--providers", "claude"])
        rc = self.main(["uninstall", "codex"])
        self.assertEqual(rc, 0, self.out.getvalue())
        saved = setup.load_config(self.config)
        self.assertTrue(saved.claude_interactions)
        self.assertFalse(saved.codex_interactions)


class HooksMergeTests(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.settings = pathlib.Path(self.dir.name) / "settings.json"
        self.out = io.StringIO()

    def tearDown(self):
        self.dir.cleanup()

    def test_fresh_file_gets_both_hooks(self):
        self.assertTrue(setup._merge_claude_hooks(
            self.settings, stdout=self.out))
        saved = json.loads(self.settings.read_text())
        for event in ("PreToolUse", "PermissionRequest"):
            urls = [h["url"] for entry in saved["hooks"][event]
                    for h in entry["hooks"]]
            self.assertEqual(urls, [setup._HOOK_URLS[event]])

    def test_existing_unrelated_hooks_survive_and_rerun_is_noop(self):
        self.settings.write_text(json.dumps({
            "permissions": {"allow": ["Bash(ls:*)"]},
            "hooks": {"Stop": [{"matcher": "", "hooks": [
                {"type": "command", "command": "echo done"}]}]},
        }))
        self.assertTrue(setup._merge_claude_hooks(
            self.settings, stdout=self.out))
        first = self.settings.read_text()
        saved = json.loads(first)
        self.assertEqual(saved["permissions"], {"allow": ["Bash(ls:*)"]})
        self.assertEqual(saved["hooks"]["Stop"][0]["hooks"][0]["command"],
                         "echo done")
        self.assertTrue(
            self.settings.with_suffix(".json.vibepulse-backup").exists())
        # Idempotent: a second run changes nothing.
        self.assertTrue(setup._merge_claude_hooks(
            self.settings, stdout=self.out))
        self.assertEqual(self.settings.read_text(), first)
        self.assertIn("already installed", self.out.getvalue())

    def test_broken_settings_are_never_touched(self):
        self.settings.write_text("not json {")
        self.assertFalse(setup._merge_claude_hooks(
            self.settings, stdout=self.out))
        self.assertEqual(self.settings.read_text(), "not json {")


class AutostartPlistTests(unittest.TestCase):
    def test_plist_is_personalized_not_the_maintainers(self):
        plist = setup._autostart_plist(
            pathlib.Path("/Users/example/code/vibepulse"),
            pathlib.Path("/Users/example"))
        self.assertIn("/Users/example/code/vibepulse/tools/tokenserver",
                      plist)
        self.assertIn("/Users/example/Library/Logs/torget-tokenserver.log",
                      plist)
        self.assertNotIn("niclasvestlund", plist)
        self.assertIn("se.torget.tokenserver", plist)


class WizardTests(unittest.TestCase):
    def test_full_wizard_reaches_pairing(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            out = io.StringIO()
            calls = []
            rc = setup.main(
                ["watch", "--providers", "claude", "--detail",
                 "--no-autostart"],
                config_path=tmp / "config.json", python=sys.executable,
                codex=None, run=ok_run(calls),
                urlopen=fake_urlopen({
                    "/": {"claudeProbe": "usage_http_200 + ok",
                          "interactions": {"claude": True, "detail": True}},
                    "/api/pair/arm": {"ok": True, "code": "123456",
                                      "expires_in_s": 60},
                }),
                stdin_isatty=False, stdout=out,
                claude_settings_path=tmp / "settings.json",
                launch_agents_dir=tmp / "LaunchAgents")
            text = out.getvalue()
            self.assertEqual(rc, 0, text)
            self.assertIn("Providers saved: claude, detail on", text)
            self.assertIn("hooks installed", text)
            self.assertIn("claudeProbe: usage_http_200 + ok", text)
            self.assertIn("Pairing code:  123 456", text)
            self.assertTrue((tmp / "settings.json").exists())

    def test_stale_server_stops_before_handing_out_a_code(self):
        with tempfile.TemporaryDirectory() as tmp:
            tmp = pathlib.Path(tmp)
            out = io.StringIO()
            rc = setup.main(
                ["watch", "--providers", "claude", "--detail",
                 "--no-autostart"],
                config_path=tmp / "config.json", python=sys.executable,
                codex=None, run=ok_run([]),
                urlopen=fake_urlopen({
                    "/": {"claudeProbe": "ok",
                          "interactions": {"claude": True, "detail": False}},
                }),
                stdin_isatty=False, stdout=out,
                claude_settings_path=tmp / "settings.json",
                launch_agents_dir=tmp / "LaunchAgents")
            self.assertEqual(rc, 0)
            self.assertIn("still serves old choices", out.getvalue())
            self.assertNotIn("Pairing code", out.getvalue())


if __name__ == "__main__":
    unittest.main()
