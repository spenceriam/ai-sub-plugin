#!/usr/bin/env python3
import json
import unittest
from pathlib import Path
import importlib.util

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("collect", ROOT / "collect.py")
collect = importlib.util.module_from_spec(spec)
spec.loader.exec_module(collect)

FIXTURES = Path(__file__).resolve().parent / "fixtures"


def load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text())


class ParseLivePayloads(unittest.TestCase):
    def test_kimi_weekly_and_session(self):
        record = collect.parse_kimi(load("kimi.json"))
        self.assertEqual(record["id"], "kimi")
        self.assertEqual(record["name"], "Kimi Code")
        self.assertEqual(record["tierLabel"], "Standard")
        by_title = {row["title"]: row for row in record["limits"]}
        self.assertEqual(by_title["Session"]["percent"], 0.0)
        self.assertEqual(by_title["Session"]["resetsAt"], "2026-08-28T02:18:43.898399Z")
        self.assertAlmostEqual(by_title["Weekly"]["percent"], 0.07)
        self.assertEqual(by_title["Weekly"]["resetsAt"], "2026-09-01T14:18:43.898399Z")

    def test_glm_session_and_weekly_not_mcp_month(self):
        record = collect.parse_glm(load("glm.json"))
        self.assertEqual(record["name"], "GLM Coding Plan")
        self.assertEqual(record["tierLabel"], "Max")
        titles = [row["title"] for row in record["limits"]]
        self.assertEqual(titles, ["Session", "Weekly"])
        by_title = {row["title"]: row for row in record["limits"]}
        self.assertEqual(by_title["Session"]["percent"], 0.0)
        self.assertEqual(by_title["Session"]["resetsAt"], "")
        self.assertEqual(by_title["Session"]["resetNote"], "5 hours after use")
        self.assertEqual(by_title["Weekly"]["percent"], -1)
        self.assertEqual(by_title["Weekly"]["resetNote"], "every 7 days")
        self.assertNotIn("MCP", by_title)

    def test_minimax_inverts_remaining_unlimited_weekly(self):
        record = collect.parse_minimax(load("minimax.json"))
        self.assertEqual(record["name"], "MiniMax Token Plan")
        self.assertEqual(record["tierLabel"], "Token Plan")
        by_title = {row["title"]: row for row in record["limits"]}
        self.assertEqual(by_title["Session"]["percent"], 0.0)
        self.assertEqual(by_title["Session"]["resetsAt"], "2026-08-28T00:00:00Z")
        self.assertTrue(by_title["Weekly"]["unlimited"])
        self.assertEqual(by_title["Weekly"]["percent"], -1)

    def test_ollama_fractions_and_top_models(self):
        record = collect.parse_ollama(load("ollama.json"))
        by_title = {row["title"]: row for row in record["limits"]}
        self.assertEqual(by_title["Session"]["percent"], 0.0)
        self.assertEqual(by_title["Session"]["resetsAt"], "")
        self.assertEqual(by_title["Session"]["resetNote"], "every 5 hours")
        self.assertAlmostEqual(by_title["Weekly"]["percent"], 0.105)
        self.assertEqual(by_title["Weekly"]["resetsAt"], "")
        self.assertEqual(by_title["Weekly"]["resetNote"], "every 7 days")
        self.assertEqual(
            [row["name"] for row in record["models"]],
            ["deepseek-v4-pro:0813", "glm-5.3-flash", "minimax-m3", "deepseek-v4-flash:0731"],
        )
        self.assertEqual(record["models"][0]["total"], 402)

    def test_kilo_pass_month_and_wallet(self):
        record = collect.parse_kilo(load("kilo-pass.json"), load("kilo-balance.json"))
        self.assertEqual(record["id"], "kilo")
        self.assertEqual(record["name"], "Kilo Pass")
        self.assertEqual(record["tierLabel"], "Pro · Yearly · ending")
        by_title = {row["title"]: row for row in record["limits"]}
        month = by_title["This month"]
        self.assertEqual(month["percent"], 0.0)
        self.assertEqual(month["valueLabel"], "$0.00 / $73.50")
        self.assertEqual(month["resetsAt"], "2026-09-21T00:00:00.000Z")
        self.assertIn("cancellation pending", month["resetNote"])
        self.assertIn("$49.00 paid", month["resetNote"])
        self.assertAlmostEqual(record["balance"]["remaining"], 208.7)
        self.assertEqual(record["balance"]["currency"], "USD")

    def test_commandcode_go_windows_and_month(self):
        record = collect.parse_commandcode(load("commandcode-credits.json"), load("commandcode-subscription.json"))
        self.assertEqual(record["id"], "commandcode")
        self.assertEqual(record["name"], "Command Code")
        self.assertEqual(record["tierLabel"], "Go")
        by_title = {row["title"]: row for row in record["limits"]}
        self.assertAlmostEqual(by_title["5-hour"]["percent"], 1.2216 / 3)
        self.assertEqual(by_title["5-hour"]["resetsAt"], collect.iso_from_ms(1786700000000))
        self.assertAlmostEqual(by_title["Weekly"]["percent"], 1.2216 / 6)
        self.assertEqual(by_title["Weekly"]["resetsAt"], collect.iso_from_ms(1787000000000))
        month = by_title["This month"]
        self.assertAlmostEqual(month["percent"], 1.2216 / 10)
        self.assertEqual(month["valueLabel"], "$1.22 / $10.00")
        self.assertEqual(month["resetsAt"], "2026-06-06T07:28:50.000Z")
        self.assertIsNone(record.get("balance"))

    def test_commandcode_nested_windows_and_untrusted_month(self):
        nested = {
            "credits": {
                "monthlyCredits": 35,
                "purchasedCredits": 4.5,
                "windowLimits": {
                    "fiveHour": {"cap": 14, "used": 7, "resetAt": 0},
                    "weekly": {"cap": 35, "used": 14},
                },
            }
        }
        record = collect.parse_commandcode(nested, {"success": True, "data": {"planId": "individual-goat", "status": "active"}})
        self.assertEqual(record["tierLabel"], "GOAT")
        by_title = {row["title"]: row for row in record["limits"]}
        self.assertEqual(by_title["5-hour"]["percent"], 0.5)
        self.assertEqual(by_title["5-hour"]["resetNote"], "every 5 hours")
        self.assertEqual(by_title["Weekly"]["percent"], 0.4)
        self.assertEqual(by_title["Weekly"]["resetNote"], "every 7 days")
        self.assertEqual(by_title["This month"]["valueLabel"], "$35.00 / $70.00")
        self.assertAlmostEqual(record["balance"]["remaining"], 4.5)

        leftover = {
            "credits": {"monthlyCredits": 42, "purchasedCredits": 0},
            "windowLimits": {
                "fiveHour": {"cap": 3, "used": 0},
                "weekly": {"cap": 6, "used": 0},
            },
        }
        untrusted = collect.parse_commandcode(leftover, {"success": True, "data": {"planId": "individual-go"}})
        month = {row["title"]: row for row in untrusted["limits"]}["This month"]
        self.assertEqual(month["percent"], -1)
        self.assertEqual(month["valueLabel"], "$42.00 left")


class KeyFile(unittest.TestCase):
    def test_save_keys_writes_0600_and_omits_cleared(self):
        import os
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "keys.env"
            os.environ["AI_SUB_MONITOR_ENV"] = str(path)
            for name in collect.ENV_VALUE_KEYS:
                os.environ.pop(name, None)
            status = collect.save_keys({"kimi": "kimi-secret", "ollama": "ollama-secret", "glm": ""})
            self.assertTrue(status["kimi"])
            self.assertFalse(status["glm"])
            self.assertTrue(status["ollama"])
            text = path.read_text()
            self.assertIn("KIMI_API_KEY=kimi-secret", text)
            self.assertNotIn("ZAI_API_KEY", text)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            collect.save_keys({"kimi": ""})
            text = Path(os.environ["AI_SUB_MONITOR_ENV"]).read_text()
            self.assertNotIn("KIMI_API_KEY", text)
            self.assertIn("OLLAMA_API_KEY=ollama-secret", text)
            os.environ.pop("AI_SUB_MONITOR_ENV", None)

    def test_status_json_is_bools_never_secrets(self):
        import json
        import os
        import tempfile
        from pathlib import Path

        secret = "super-secret-value-xyz"
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "keys.env"
            os.environ["AI_SUB_MONITOR_ENV"] = str(path)
            for name in collect.ENV_VALUE_KEYS:
                os.environ.pop(name, None)
            collect.save_keys({"kimi": secret, "ollama": secret})
            dumped = json.dumps(collect.key_status())
            self.assertNotIn(secret, dumped)
            self.assertEqual(
                json.loads(dumped),
                {"kimi": True, "glm": False, "minimax": False, "ollama": True, "kilo": False, "commandcode": False},
            )
            os.environ.pop("AI_SUB_MONITOR_ENV", None)

    def test_save_keys_chmods_ai_sub_monitor_dir_not_random_parent(self):
        import os
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "ai-sub-monitor" / "keys.env"
            os.environ["AI_SUB_MONITOR_ENV"] = str(path)
            for name in collect.ENV_VALUE_KEYS:
                os.environ.pop(name, None)
            collect.save_keys({"ollama": "x"})
            self.assertEqual(path.parent.stat().st_mode & 0o777, 0o700)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            os.environ.pop("AI_SUB_MONITOR_ENV", None)

    def test_probe_no_key_never_prints_secret(self):
        import json
        import os
        import tempfile
        from pathlib import Path

        secret = "super-secret-value-xyz"
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["AI_SUB_MONITOR_ENV"] = str(Path(tmp) / "keys.env")
            os.environ["XDG_STATE_HOME"] = str(Path(tmp) / "state")
            for name in collect.ENV_VALUE_KEYS:
                os.environ.pop(name, None)
            result = collect.probe_provider("kimi")
            dumped = json.dumps(result)
            self.assertNotIn(secret, dumped)
            self.assertFalse(result["ok"])
            self.assertEqual(result["id"], "kimi")
            self.assertIn("No key", result["message"])
            os.environ.pop("AI_SUB_MONITOR_ENV", None)
            os.environ.pop("XDG_STATE_HOME", None)

    def test_probe_rejected_key_message_never_prints_secret(self):
        import json
        import os
        import tempfile
        from pathlib import Path
        from unittest.mock import patch

        secret = "super-secret-value-xyz"
        with tempfile.TemporaryDirectory() as tmp:
            os.environ["AI_SUB_MONITOR_ENV"] = str(Path(tmp) / "keys.env")
            os.environ["XDG_STATE_HOME"] = str(Path(tmp) / "state")
            os.environ["KIMI_API_KEY"] = secret
            for name in collect.ENV_VALUE_KEYS:
                if name != "KIMI_API_KEY":
                    os.environ.pop(name, None)

            def boom():
                raise collect.FetchError(
                    "Kimi rejected the key. Use a Code Console key, not a Moonshot wallet key.",
                    retry=False,
                    auth=True,
                )

            with patch.dict(collect.COLLECTORS, {"kimi": boom}):
                result = collect.probe_provider("kimi")
            dumped = json.dumps(result)
            self.assertNotIn(secret, dumped)
            self.assertFalse(result["ok"])
            self.assertEqual(result["id"], "kimi")
            self.assertIn("rejected the key", result["message"])
            os.environ.pop("KIMI_API_KEY", None)
            os.environ.pop("AI_SUB_MONITOR_ENV", None)
            os.environ.pop("XDG_STATE_HOME", None)


class ReleaseCheck(unittest.TestCase):
    def test_semver_newer(self):
        self.assertTrue(collect.version_newer("0.2.0", "0.1.0"))
        self.assertTrue(collect.version_newer("v0.1.1", "0.1.0"))
        self.assertFalse(collect.version_newer("0.1.0", "0.1.0"))
        self.assertFalse(collect.version_newer("0.1.0", "0.2.0"))
        self.assertFalse(collect.version_newer("nope", "0.1.0"))

    def test_plugin_version_matches_manifest(self):
        self.assertEqual(collect.plugin_version(), "0.1.0")

    def test_latest_release_404_is_not_newer(self):
        from unittest.mock import patch

        with patch.object(collect, "http_json", return_value=(404, {"message": "Not Found"})):
            result = collect.check_latest_release()
        self.assertTrue(result["ok"])
        self.assertEqual(result["installed"], "0.1.0")
        self.assertFalse(result["newer"])
        self.assertEqual(result["latest"], "")

    def test_latest_release_newer_tag(self):
        from unittest.mock import patch

        payload = {
            "tag_name": "v0.2.0",
            "html_url": "https://github.com/spenceriam/ai-sub-plugin/releases/tag/v0.2.0",
        }
        with patch.object(collect, "http_json", return_value=(200, payload)):
            result = collect.check_latest_release()
        self.assertTrue(result["ok"])
        self.assertTrue(result["newer"])
        self.assertEqual(result["latest"], "0.2.0")
        self.assertEqual(result["tag"], "v0.2.0")


class UninstallData(unittest.TestCase):
    def test_dry_run_does_not_delete(self):
        import os
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config"
            state = Path(tmp) / "state"
            os.environ["XDG_CONFIG_HOME"] = str(config)
            os.environ["XDG_STATE_HOME"] = str(state)
            keys = config / "ai-sub-monitor"
            keys.mkdir(parents=True)
            (keys / "keys.env").write_text("KIMI_API_KEY=secret\n")
            usage = state / "omarchy" / "ai-sub-monitor"
            usage.mkdir(parents=True)
            (usage / "ui.json").write_text("{}\n")
            result = collect.uninstall_user_data(yes=False)
            self.assertFalse(result["ok"])
            self.assertTrue((keys / "keys.env").is_file())
            self.assertTrue((usage / "ui.json").is_file())
            self.assertEqual(result["removed"], [])
            os.environ.pop("XDG_CONFIG_HOME", None)
            os.environ.pop("XDG_STATE_HOME", None)

    def test_yes_deletes_only_plugin_dirs(self):
        import os
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            config = Path(tmp) / "config"
            state = Path(tmp) / "state"
            os.environ["XDG_CONFIG_HOME"] = str(config)
            os.environ["XDG_STATE_HOME"] = str(state)
            keys = config / "ai-sub-monitor"
            keys.mkdir(parents=True)
            (keys / "keys.env").write_text("KIMI_API_KEY=secret\n")
            other = config / "keep-me"
            other.mkdir()
            (other / "file").write_text("stay\n")
            usage = state / "omarchy" / "ai-sub-monitor"
            usage.mkdir(parents=True)
            (usage / "ui.json").write_text("{}\n")
            result = collect.uninstall_user_data(yes=True)
            self.assertTrue(result["ok"])
            self.assertFalse(keys.exists())
            self.assertFalse(usage.exists())
            self.assertTrue((other / "file").is_file())
            os.environ.pop("XDG_CONFIG_HOME", None)
            os.environ.pop("XDG_STATE_HOME", None)

    def test_refuses_unrelated_path(self):
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as tmp:
            evil = Path(tmp) / "not-this-plugin"
            evil.mkdir()
            self.assertIsNone(collect.remove_allowed_path(evil))
            self.assertTrue(evil.is_dir())


if __name__ == "__main__":
    unittest.main()
