import datetime as dt
import importlib.machinery
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[1]


def load_script(name: str, filename: str):
    loader = importlib.machinery.SourceFileLoader(name, str(REPO / filename))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


manager = load_script("codex_manager_account", "codex-account")
runtime = load_script("codex_manager_runtime", "codex-runtime")


class ManagerUnitTests(unittest.TestCase):
    def test_systemd_quote_escapes_percent_specifiers(self):
        quoted = manager.systemd_quote("/tmp/a%b")
        self.assertIn("a%%b", quoted)

    def test_usage_headroom_uses_most_constrained_window(self):
        meta = {
            "usage": {
                "ordinary_usage_allowed": True,
                "windows": [
                    {"used_percent": 20},
                    {"used_percent": 83},
                ],
            }
        }
        self.assertEqual(manager.usage_headroom(meta), 17)

    def test_usage_headroom_blocks_disallowed_usage(self):
        self.assertEqual(
            manager.usage_headroom({"usage": {"ordinary_usage_allowed": False}}),
            -1,
        )

    def test_reset_duration_parser(self):
        before = manager.utcnow()
        parsed = manager.infer_reset("You've hit your usage limit; try again in 2 hours.")
        delta = (parsed - before).total_seconds()
        self.assertGreater(delta, 7100)
        self.assertLess(delta, 7300)

    def test_reset_clock_parser_returns_future_time(self):
        now = dt.datetime.now().astimezone()
        future = now + dt.timedelta(minutes=3)
        text = future.strftime("You've hit your usage limit; try again at %-I:%M %p.")
        parsed = manager.infer_reset(text)
        self.assertGreater(parsed, manager.utcnow())
        self.assertLess(parsed - manager.utcnow(), dt.timedelta(days=1, minutes=5))

    def test_account_scoring_prefers_more_headroom(self):
        old_root = manager.ROOT
        old_cfg = manager.CFG
        with tempfile.TemporaryDirectory() as td:
            manager.ROOT = Path(td)
            manager.CFG = Path(td) / "manager.json"
            st = {
                "preferred": "low",
                "accounts": {
                    "low": {
                        "enabled": True,
                        "priority": 100,
                        "status": "healthy",
                        "cooldown_until": None,
                        "last_success": None,
                        "usage": {
                            "ordinary_usage_allowed": True,
                            "windows": [{"used_percent": 90}],
                        },
                    },
                    "high": {
                        "enabled": True,
                        "priority": 100,
                        "status": "healthy",
                        "cooldown_until": None,
                        "last_success": None,
                        "usage": {
                            "ordinary_usage_allowed": True,
                            "windows": [{"used_percent": 20}],
                        },
                    },
                },
            }
            self.assertEqual(manager.available(st)[0], "high")
        manager.ROOT = old_root
        manager.CFG = old_cfg


class RuntimeUnitTests(unittest.TestCase):
    def test_parse_stable_version(self):
        key, prerelease = runtime.parse_version("codex-cli 0.167.0")
        self.assertEqual(key, (0, 167, 0))
        self.assertFalse(prerelease)

    def test_parse_prerelease_version(self):
        key, prerelease = runtime.parse_version("codex-cli 0.169.0-alpha.2")
        self.assertEqual(key, (0, 169, 0))
        self.assertTrue(prerelease)


if __name__ == "__main__":
    unittest.main()
