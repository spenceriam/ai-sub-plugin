#!/usr/bin/env python3
"""Collect coding-plan usage for Kimi, GLM, MiniMax, Ollama Cloud, Kilo Pass, and Command Code.

Each adapter writes one JSON record under
$XDG_STATE_HOME/omarchy/ai-sub-monitor/<id>.json. Missing keys skip that
provider. Wrong-product wallets are not queried.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Callable

SCHEMA_VERSION = 1
USER_AGENT = "ai-sub-monitor/0.1.0"
TIMEOUT_SEC = 15
PROVIDER_ORDER = ("kimi", "glm", "minimax", "ollama", "kilo", "commandcode")
PROVIDER_ENV = {
    "kimi": "KIMI_API_KEY",
    "glm": "ZAI_API_KEY",
    "minimax": "MINIMAX_API_KEY",
    "ollama": "OLLAMA_API_KEY",
    "kilo": "KILO_API_KEY",
    "commandcode": "COMMAND_CODE_API_KEY",
}
ENV_VALUE_KEYS = tuple(PROVIDER_ENV.values()) + (
    "ZAI_HOST",
    "MINIMAX_HOST",
    "KILO_HOST",
    "KILO_ORG_ID",
    "COMMAND_CODE_HOST",
)


def config_dir() -> Path:
    return Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "ai-sub-monitor"


def keys_path() -> Path:
    override = os.environ.get("AI_SUB_MONITOR_ENV")
    if override:
        return Path(override)
    return config_dir() / "keys.env"


def legacy_keys_path() -> Path:
    return Path.home() / ".config" / "omarchy" / "ai-sub-monitor.env"


def parse_env_file(path: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    if not path.is_file():
        return out
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip().strip("'").strip('"')
        if key:
            out[key] = value
    return out


def load_env_file(path: Path | None = None) -> None:
    if path is None:
        for candidate in (keys_path(), legacy_keys_path()):
            load_env_file(candidate)
        return
    parsed = parse_env_file(path)
    for key, value in parsed.items():
        if key not in os.environ:
            os.environ[key] = value


def key_status() -> dict[str, bool]:
    load_env_file()
    return {provider_id: bool((os.environ.get(env_name) or "").strip()) for provider_id, env_name in PROVIDER_ENV.items()}


def atomic_write_secret(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.parent.name == "ai-sub-monitor":
        os.chmod(path.parent, 0o700)
    fd, tmp = tempfile.mkstemp(prefix=".keys.", dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
            if not text.endswith("\n"):
                handle.write("\n")
        os.replace(tmp, path)
        os.chmod(path, 0o600)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def save_keys(updates: dict[str, Any]) -> dict[str, bool]:
    path = keys_path()
    current = parse_env_file(path)
    if not current and legacy_keys_path().is_file() and path != legacy_keys_path():
        current = parse_env_file(legacy_keys_path())
    for provider_id, env_name in PROVIDER_ENV.items():
        if provider_id not in updates:
            continue
        value = updates[provider_id]
        if value is None:
            continue
        text = str(value).strip()
        if text:
            current[env_name] = text
        else:
            current.pop(env_name, None)
    lines = ["# ai-sub-monitor keys. Directory mode 0700, file mode 0600. Do not commit.", ""]
    for env_name in ENV_VALUE_KEYS:
        if current.get(env_name):
            lines.append(f"{env_name}={current[env_name]}")
    atomic_write_secret(path, "\n".join(lines) + "\n")
    for env_name in ENV_VALUE_KEYS:
        os.environ.pop(env_name, None)
    load_env_file(path)
    return key_status()


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def usage_dir() -> Path:
    state = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    path = state / "omarchy" / "ai-sub-monitor"
    path.mkdir(parents=True, exist_ok=True)
    return path


def number(value: Any) -> float | None:
    if value is None or value is False:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def clamp_unit(value: float) -> float:
    return max(0.0, min(1.0, value))


def usd(value: Any) -> str:
    amount = number(value)
    if amount is None:
        amount = 0.0
    return f"${amount:.2f}"


def percent_used(used: Any, limit: Any) -> float | None:
    cap = number(limit)
    taken = number(used)
    if cap is None or taken is None or cap <= 0:
        return None
    return clamp_unit(taken / cap)


def remaining_to_used(remaining: Any, limit: Any | None = None) -> float | None:
    left = number(remaining)
    if left is None:
        return None
    cap = number(limit)
    if cap is not None and cap > 0:
        return clamp_unit((cap - left) / cap)
    if left > 1:
        return clamp_unit(1.0 - left / 100.0)
    return clamp_unit(1.0 - left)


def api_percent(value: Any) -> float | None:
    raw = number(value)
    if raw is None:
        return None
    if raw > 1:
        return clamp_unit(raw / 100.0)
    return clamp_unit(raw)


def iso_from_ms(ms: Any) -> str:
    raw = number(ms)
    if raw is None or raw <= 0:
        return ""
    seconds = raw / 1000.0 if raw > 1e12 else raw
    try:
        return datetime.fromtimestamp(seconds, tz=timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    except (OSError, OverflowError, ValueError):
        return ""


def iso_from_any(value: Any) -> str:
    if value is None or value is False:
        return ""
    if isinstance(value, (int, float)):
        return iso_from_ms(value)
    text = str(value).strip()
    return text


def record(
    provider_id: str,
    name: str,
    chip: str,
    *,
    ready: bool = False,
    tier_label: str = "",
    limits: list[dict[str, Any]] | None = None,
    models: list[dict[str, Any]] | None = None,
    usage_status: str = "",
    auth_help: str = "",
    retry: bool = False,
    balance: dict[str, Any] | None = None,
) -> dict[str, Any]:
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "id": provider_id,
        "name": name,
        "chip": chip,
        "updatedAt": utc_now(),
        "ready": ready,
        "tierLabel": tier_label,
        "usageStatusText": usage_status,
        "authHelpText": auth_help,
        "retryAdvised": retry,
        "limits": limits or [],
        "models": models or [],
    }
    if balance is not None:
        payload["balance"] = balance
    return payload


def http_json(
    url: str,
    headers: dict[str, str],
    *,
    opener: Callable[..., Any] | None = None,
) -> tuple[int, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json", **headers})
    fetch = opener or urllib.request.urlopen
    try:
        with fetch(request, timeout=TIMEOUT_SEC) as response:
            body = response.read().decode("utf-8")
            status = getattr(response, "status", 200)
            return status, json.loads(body) if body else {}
    except urllib.error.HTTPError as err:
        body = err.read().decode("utf-8", errors="replace")
        try:
            parsed = json.loads(body) if body else {}
        except json.JSONDecodeError:
            parsed = {"error": body[:200]}
        return err.code, parsed


class FetchError(Exception):
    def __init__(self, message: str, *, retry: bool = True, auth: bool = False):
        super().__init__(message)
        self.retry = retry
        self.auth = auth


def require_key(name: str) -> str | None:
    value = (os.environ.get(name) or "").strip()
    return value or None


def parse_kimi(payload: dict[str, Any]) -> dict[str, Any]:
    membership = ((payload.get("user") or {}).get("membership") or {})
    level = str(membership.get("level") or "")
    tier = level.replace("LEVEL_", "").replace("_", " ").title() if level else "Standard"
    limits: list[dict[str, Any]] = []

    windows = payload.get("limits") or []
    if windows:
        detail = (windows[0] or {}).get("detail") or {}
        session = remaining_to_used(detail.get("remaining"), detail.get("limit"))
        if session is None:
            session = percent_used(detail.get("used"), detail.get("limit"))
        if session is not None:
            limits.append(
                {
                    "title": "Session",
                    "percent": session,
                    "resetsAt": iso_from_any(detail.get("resetTime")),
                }
            )

    weekly = payload.get("usage") or {}
    weekly_pct = percent_used(weekly.get("used"), weekly.get("limit"))
    if weekly_pct is None:
        weekly_pct = remaining_to_used(weekly.get("remaining"), weekly.get("limit"))
    if weekly_pct is not None:
        limits.append(
            {
                "title": "Weekly",
                "percent": weekly_pct,
                "resetsAt": iso_from_any(weekly.get("resetTime")),
            }
        )

    return record("kimi", "Kimi Code", "Kimi", ready=bool(limits), tier_label=tier, limits=limits)


def collect_kimi(opener: Callable[..., Any] | None = None) -> dict[str, Any] | None:
    key = require_key("KIMI_API_KEY")
    if not key:
        return None
    status, payload = http_json(
        "https://api.kimi.com/coding/v1/usages",
        {"Authorization": f"Bearer {key}"},
        opener=opener,
    )
    if status in (401, 403):
        raise FetchError(
            "Kimi rejected the key. Use a Code Console key, not a Moonshot wallet key.",
            retry=False,
            auth=True,
        )
    if status >= 400 or not isinstance(payload, dict):
        raise FetchError(f"Kimi usage HTTP {status}")
    parsed = parse_kimi(payload)
    if not parsed["limits"]:
        raise FetchError("Kimi usage payload had no windows")
    return parsed


def glm_row_percent(row: dict[str, Any]) -> float | None:
    usage = number(row.get("usage"))
    current = number(row.get("currentValue"))
    remaining = number(row.get("remaining"))
    if usage is not None and usage > 0 and current is not None:
        return clamp_unit(current / usage)
    if usage is not None and usage > 0 and remaining is not None:
        return clamp_unit((usage - remaining) / usage)
    return api_percent(row.get("percentage"))


def glm_row_title(row: dict[str, Any]) -> str | None:
    kind = str(row.get("type") or "")
    unit = int(number(row.get("unit")) or 0)
    # TIME_LIMIT unit 5 is MCP/search tools (monthly-ish). Coding plan is 5h + weekly only.
    if kind == "TIME_LIMIT" and unit == 5:
        return None
    if unit == 6:
        return "Weekly"
    if kind in {"TOKENS_LIMIT", "CREDIT_LIMIT"} or unit == 3:
        return "Session"
    return "Limit"


def parse_glm(payload: dict[str, Any]) -> dict[str, Any]:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else payload
    level = str((data or {}).get("level") or "").strip()
    tier = level.title() if level else "Coding Plan"
    limits: list[dict[str, Any]] = []
    seen = set()
    for row in data.get("limits") or []:
        if not isinstance(row, dict):
            continue
        title = glm_row_title(row)
        if not title:
            continue
        pct = glm_row_percent(row)
        if pct is None:
            continue
        reset_at = iso_from_any(row.get("nextResetTime"))
        entry = {"title": title, "percent": pct, "resetsAt": reset_at}
        if title == "Session" and not reset_at:
            entry["resetNote"] = "5 hours after use"
        if title == "Weekly" and not reset_at:
            entry["resetNote"] = "every 7 days"
        limits.append(entry)
        seen.add(title)
    if "Weekly" not in seen:
        limits.append({"title": "Weekly", "percent": -1, "resetsAt": "", "resetNote": "every 7 days"})
    if "Session" not in seen:
        limits.append({"title": "Session", "percent": -1, "resetsAt": "", "resetNote": "5 hours after use"})
    order = {"Session": 0, "Weekly": 1}
    limits.sort(key=lambda row: order.get(row["title"], 9))
    return record("glm", "GLM Coding Plan", "GLM", ready=any(row.get("percent", -1) >= 0 for row in limits), tier_label=tier, limits=limits)


def collect_glm(opener: Callable[..., Any] | None = None) -> dict[str, Any] | None:
    key = require_key("ZAI_API_KEY")
    if not key:
        return None
    host = (os.environ.get("ZAI_HOST") or "https://api.z.ai").rstrip("/")
    url = f"{host}/api/monitor/usage/quota/limit"
    last_error = "GLM usage request failed"
    for header in ({"Authorization": key, "Accept-Language": "en-US,en"}, {"Authorization": f"Bearer {key}", "Accept-Language": "en-US,en"}):
        status, payload = http_json(url, header, opener=opener)
        if status in (401, 403):
            last_error = "GLM rejected the key."
            continue
        if status >= 400 or not isinstance(payload, dict):
            last_error = f"GLM usage HTTP {status}"
            continue
        parsed = parse_glm(payload)
        if parsed["limits"]:
            return parsed
        last_error = "GLM usage payload had no windows"
    raise FetchError(last_error, retry=True, auth="rejected the key" in last_error)


def parse_minimax(payload: dict[str, Any]) -> dict[str, Any]:
    base = payload.get("base_resp") or {}
    code = number(base.get("status_code"))
    if code not in (None, 0):
        raise FetchError(f"MiniMax status_code {int(code)}", retry=code not in (2049,), auth=code in (2049,))

    general = None
    for row in payload.get("model_remains") or []:
        if isinstance(row, dict) and row.get("model_name") == "general":
            general = row
            break
    if not general:
        raise FetchError("MiniMax payload had no general plan row", retry=False)

    limits: list[dict[str, Any]] = []
    session = remaining_to_used(general.get("current_interval_remaining_percent"))
    if session is not None:
        limits.append(
            {
                "title": "Session",
                "percent": session,
                "resetsAt": iso_from_ms(general.get("end_time")),
            }
        )
    weekly_status = int(number(general.get("current_weekly_status")) or 0)
    if weekly_status == 3:
        limits.append(
            {
                "title": "Weekly",
                "percent": -1,
                "unlimited": True,
                "resetsAt": "",
            }
        )
    else:
        weekly = remaining_to_used(general.get("current_weekly_remaining_percent"))
        if weekly is not None:
            limits.append(
                {
                    "title": "Weekly",
                    "percent": weekly,
                    "resetsAt": iso_from_ms(general.get("weekly_end_time")),
                }
            )
    return record("minimax", "MiniMax Token Plan", "MiniMax", ready=bool(limits), tier_label="Token Plan", limits=limits)


def collect_minimax(opener: Callable[..., Any] | None = None) -> dict[str, Any] | None:
    key = require_key("MINIMAX_API_KEY")
    if not key:
        return None
    host = (os.environ.get("MINIMAX_HOST") or "https://api.minimax.io").rstrip("/")
    status, payload = http_json(
        f"{host}/v1/token_plan/remains",
        {"Authorization": f"Bearer {key}", "Content-Type": "application/json"},
        opener=opener,
    )
    if status in (401, 403):
        raise FetchError("MiniMax rejected the key. Use a Token Plan Subscription Key.", retry=False, auth=True)
    if status >= 400 or not isinstance(payload, dict):
        raise FetchError(f"MiniMax usage HTTP {status}")
    return parse_minimax(payload)


def ollama_reset(bucket: dict[str, Any], fallback_note: str) -> tuple[str, str]:
    if not isinstance(bucket, dict):
        return "", fallback_note
    for key in ("resets_at", "resetsAt", "reset_at", "resetAt", "nextResetTime"):
        stamp = iso_from_any(bucket.get(key))
        if stamp:
            return stamp, ""
    return "", fallback_note


def parse_ollama(payload: dict[str, Any]) -> dict[str, Any]:
    buckets = payload.get("limits") or {}
    limits: list[dict[str, Any]] = []
    session = (buckets.get("session") or {}) if isinstance(buckets, dict) else {}
    weekly = (buckets.get("weekly") or {}) if isinstance(buckets, dict) else {}
    session_pct = api_percent(session.get("usage"))
    if session_pct is not None:
        reset_at, note = ollama_reset(session, "every 5 hours")
        limits.append({"title": "Session", "percent": session_pct, "resetsAt": reset_at, "resetNote": note})
    weekly_pct = api_percent(weekly.get("usage"))
    if weekly_pct is not None:
        reset_at, note = ollama_reset(weekly, "every 7 days")
        limits.append({"title": "Weekly", "percent": weekly_pct, "resetsAt": reset_at, "resetNote": note})

    models: list[dict[str, Any]] = []
    for row in weekly.get("models") or []:
        if not isinstance(row, dict):
            continue
        name = str(row.get("name") or "").strip()
        total = number(row.get("request_count"))
        if name and total is not None:
            models.append({"name": name, "total": int(total)})
    models.sort(key=lambda item: item["total"], reverse=True)
    return record(
        "ollama",
        "Ollama Cloud",
        "Ollama",
        ready=bool(limits),
        tier_label="",
        limits=limits,
        models=models[:4],
    )


def collect_ollama(opener: Callable[..., Any] | None = None) -> dict[str, Any] | None:
    key = require_key("OLLAMA_API_KEY")
    if not key:
        return None
    last_error = "Ollama usage request failed"
    for header in ({"Authorization": f"Bearer {key}"}, {"Authorization": key}):
        status, payload = http_json("https://ollama.com/api/usage", header, opener=opener)
        if status in (401, 403):
            last_error = "Ollama rejected the key."
            continue
        if status >= 400 or not isinstance(payload, dict):
            last_error = f"Ollama usage HTTP {status}"
            continue
        parsed = parse_ollama(payload)
        if parsed["limits"]:
            return parsed
        last_error = "Ollama usage payload had no windows"
    raise FetchError(last_error, retry=True, auth="rejected the key" in last_error)


def as_record(value: Any) -> dict[str, Any] | None:
    return value if isinstance(value, dict) else None


def kilo_pass_root(payload: Any) -> dict[str, Any] | None:
    item = payload[0] if isinstance(payload, list) and payload else payload
    rec = as_record(item)
    if rec is None:
        return None
    result = as_record(rec.get("result"))
    data = as_record(result.get("data")) if result else None
    if data is None:
        return rec if "subscription" in rec else None
    nested = as_record(data.get("json"))
    return nested or data


def kilo_subscription(payload: Any) -> dict[str, Any] | None:
    root = kilo_pass_root(payload)
    if root is None:
        return None
    sub = as_record(root.get("subscription"))
    if sub is None:
        return None
    if sub.get("currentPeriodBaseCreditsUsd") is None and sub.get("currentPeriodUsageUsd") is None:
        return None
    return sub


def kilo_truthy(value: Any) -> bool:
    return value is True or str(value).strip().lower() in ("1", "true", "yes")


def kilo_tier_label(sub: dict[str, Any]) -> str:
    bits: list[str] = []
    for key in ("planName", "productName", "nickname", "plan"):
        text = str(sub.get(key) or "").strip()
        if not text or text.lower() in ("kilo pass", "kilopass", "subscription"):
            continue
        bits.append(text.replace("_", " ").title() if "_" in text or text.islower() else text)
        break
    interval = str(sub.get("interval") or sub.get("billingInterval") or sub.get("billing_interval") or "").strip()
    if interval:
        mapped = {"year": "Yearly", "month": "Monthly", "week": "Weekly", "day": "Daily"}
        bits.append(mapped.get(interval.lower(), interval.replace("_", " ").title()))
    if kilo_truthy(sub.get("cancelAtPeriodEnd")) or kilo_truthy(sub.get("cancel_at_period_end")):
        bits.append("ending")
    return " · ".join(bits) if bits else "Kilo Pass"


def kilo_hosts() -> list[str]:
    primary = (os.environ.get("KILO_HOST") or "https://api.kilo.ai").rstrip("/")
    hosts = [primary]
    if "api.kilo.ai" in primary:
        hosts.append("https://app.kilo.ai")
    elif "app.kilo.ai" in primary:
        hosts.append("https://api.kilo.ai")
    return hosts


def kilo_pass_url(host: str) -> str:
    query = urllib.parse.urlencode({"batch": "1", "input": json.dumps({"0": None}, separators=(",", ":"))})
    return f"{host.rstrip('/')}/api/trpc/kiloPass.getState?{query}"


def kilo_auth_headers(key: str) -> dict[str, str]:
    headers = {"Authorization": f"Bearer {key}"}
    org = (os.environ.get("KILO_ORG_ID") or "").strip()
    if org:
        headers["X-KiloCode-OrganizationId"] = org
    return headers


def parse_kilo(pass_payload: Any, balance_payload: Any = None) -> dict[str, Any]:
    limits: list[dict[str, Any]] = []
    sub = kilo_subscription(pass_payload)
    if sub:
        base = number(sub.get("currentPeriodBaseCreditsUsd")) or 0.0
        bonus = number(sub.get("currentPeriodBonusCreditsUsd")) or 0.0
        used = number(sub.get("currentPeriodUsageUsd"))
        if used is None:
            used = 0.0
        total = base + bonus
        pct = percent_used(used, total) if total > 0 else None
        reset_at = iso_from_any(sub.get("nextBillingAt") or sub.get("nextRenewalAt"))
        reset_bits: list[str] = []
        if kilo_truthy(sub.get("cancelAtPeriodEnd")) or kilo_truthy(sub.get("cancel_at_period_end")):
            reset_bits.append("cancellation pending")
        if bonus > 0:
            reset_bits.append(f"{usd(base)} paid + {usd(bonus)} bonus")
        row: dict[str, Any] = {
            "title": "This month",
            "percent": pct if pct is not None else -1,
            "resetsAt": reset_at,
            "resetNote": " · ".join(reset_bits),
        }
        if total > 0:
            row["valueLabel"] = f"{usd(used)} / {usd(total)}"
        limits.append(row)

    remaining = None
    if isinstance(balance_payload, dict):
        remaining = number(balance_payload.get("balance"))
    balance = None
    if remaining is not None and remaining >= 0:
        balance = {"remaining": remaining, "currency": "USD"}

    tier = kilo_tier_label(sub) if sub else ("Credits" if balance else "")
    return record(
        "kilo",
        "Kilo Pass",
        "Kilo",
        ready=bool(limits) or balance is not None,
        tier_label=tier,
        limits=limits,
        balance=balance,
    )


def collect_kilo(opener: Callable[..., Any] | None = None) -> dict[str, Any] | None:
    key = require_key("KILO_API_KEY")
    if not key:
        return None
    headers = kilo_auth_headers(key)
    last_error = "Kilo usage request failed"
    pass_payload: Any = None
    for host in kilo_hosts():
        status, payload = http_json(kilo_pass_url(host), headers, opener=opener)
        if status in (401, 403):
            last_error = "Kilo rejected the key. Use the Gateway API key from app.kilo.ai/profile, not a BYOK provider key."
            continue
        if status >= 400:
            last_error = f"Kilo Pass HTTP {status}"
            continue
        if kilo_subscription(payload) is not None:
            pass_payload = payload
            break
        last_error = "Kilo Pass payload had no subscription"
        pass_payload = payload

    balance_payload: Any = None
    balance_error = ""
    for host in kilo_hosts():
        status, payload = http_json(f"{host}/api/profile/balance", headers, opener=opener)
        if status in (401, 403):
            balance_error = "Kilo rejected the key. Use the Gateway API key from app.kilo.ai/profile, not a BYOK provider key."
            continue
        if status >= 400 or not isinstance(payload, dict):
            balance_error = f"Kilo balance HTTP {status}"
            continue
        if number(payload.get("balance")) is not None:
            balance_payload = payload
            break
        balance_error = "Kilo balance payload had no amount"

    parsed = parse_kilo(pass_payload, balance_payload)
    if parsed["ready"]:
        return parsed
    if "rejected the key" in last_error or "rejected the key" in balance_error:
        raise FetchError(last_error or balance_error, retry=False, auth=True)
    raise FetchError(last_error or balance_error or "Kilo returned no Pass and no balance", retry=True)


# Official names and caps from https://commandcode.ai/docs/resources/usage-limits (checked 2026-08-28).
# /alpha/billing/credits reports remaining monthlyCredits, not the grant total.
# Trust a catalogued total only when the live 5-hour and weekly caps match the published plan.
COMMAND_CODE_PLAN_LABELS = {
    "individual-go": "Go",
    "individual-goat": "GOAT",
    "individual-pro": "Pro",
    "individual-pro-v1": "Pro",
    "individual-max": "Max 10×",
    "individual-ultra": "Max 20×",
    "team-pro": "Team Pro",
}
COMMAND_CODE_CAPS = {
    (3.0, 6.0): ("Go", 10.0),
    (14.0, 35.0): ("GOAT", 70.0),
    (16.0, 40.0): ("Pro", 80.0),
    (45.0, 90.0): ("Max 10×", 150.0),
    (90.0, 180.0): ("Max 20×", 300.0),
    (12.0, 24.0): ("Team Pro", 40.0),
}


def commandcode_headers(key: str) -> dict[str, str]:
    return {"Authorization": f"Bearer {key}", "Accept": "application/json"}


def commandcode_host() -> str:
    return (os.environ.get("COMMAND_CODE_HOST") or "https://api.commandcode.ai").rstrip("/")


def commandcode_object(payload: Any, *keys: str) -> dict[str, Any] | None:
    if not isinstance(payload, dict):
        return None
    for key in keys:
        value = payload.get(key)
        if isinstance(value, dict):
            return value
    return None


def commandcode_window_limits(payload: dict[str, Any]) -> dict[str, Any]:
    credits = commandcode_object(payload, "credits") or {}
    windows = commandcode_object(credits, "windowLimits", "window_limits")
    if windows is None:
        windows = commandcode_object(payload, "windowLimits", "window_limits")
    return windows or {}


def commandcode_pick(mapping: Any, *keys: str) -> Any:
    if not isinstance(mapping, dict):
        return None
    for key in keys:
        if key in mapping and mapping[key] is not None:
            return mapping[key]
    return None


def commandcode_cap(raw: Any) -> float | None:
    if not isinstance(raw, dict):
        return None
    return number(commandcode_pick(raw, "cap", "limit"))


def commandcode_rolling(title: str, raw: Any, fallback_note: str) -> dict[str, Any] | None:
    cap = commandcode_cap(raw)
    if cap is None or cap <= 0 or not isinstance(raw, dict):
        return None
    used = number(raw.get("used")) or 0.0
    pct = percent_used(used, cap)
    reset_at = iso_from_any(commandcode_pick(raw, "resetAt", "reset_at"))
    row: dict[str, Any] = {
        "title": title,
        "percent": pct if pct is not None else 0.0,
        "resetsAt": reset_at,
    }
    if not reset_at:
        row["resetNote"] = fallback_note
    return row


def commandcode_subscription(payload: Any) -> dict[str, Any] | None:
    if not isinstance(payload, dict) or payload.get("success") is not True:
        return None
    data = payload.get("data")
    if not isinstance(data, dict):
        return None
    plan_id = str(data.get("planId") or data.get("plan_id") or "").strip()
    if not plan_id:
        return None
    return data


def commandcode_plan(plan_id: str, five_cap: float | None, weekly_cap: float | None, remaining: float) -> tuple[str, float | None]:
    label = COMMAND_CODE_PLAN_LABELS.get(plan_id.lower(), "")
    if five_cap is None or weekly_cap is None:
        return label, None
    match = COMMAND_CODE_CAPS.get((round(five_cap, 4), round(weekly_cap, 4)))
    if not match:
        return label, None
    cap_label, allowance = match
    if remaining > allowance:
        return cap_label or label, None
    return cap_label or label, allowance


def parse_commandcode(credits_payload: Any, subscription_payload: Any = None) -> dict[str, Any]:
    credits = commandcode_object(credits_payload, "credits") if isinstance(credits_payload, dict) else None
    if not credits:
        raise FetchError("Command Code payload had no credits", retry=False)
    remaining = number(commandcode_pick(credits, "monthlyCredits", "monthly_credits"))
    if remaining is None:
        raise FetchError("Command Code payload had no monthlyCredits", retry=False)
    purchased = number(commandcode_pick(credits, "purchasedCredits", "purchased_credits")) or 0.0
    windows = commandcode_window_limits(credits_payload if isinstance(credits_payload, dict) else {})
    raw_five = commandcode_pick(windows, "fiveHour", "five_hour")
    raw_week = commandcode_pick(windows, "weekly")
    five = commandcode_rolling("5-hour", raw_five, "every 5 hours")
    weekly = commandcode_rolling("Weekly", raw_week, "every 7 days")
    five_cap = commandcode_cap(raw_five)
    weekly_cap = commandcode_cap(raw_week)

    sub = commandcode_subscription(subscription_payload)
    plan_id = str((sub or {}).get("planId") or (sub or {}).get("plan_id") or "").strip()
    tier, allowance = commandcode_plan(plan_id, five_cap, weekly_cap, remaining)
    period_end = iso_from_any((sub or {}).get("currentPeriodEnd") or (sub or {}).get("current_period_end")) if sub else ""

    limits: list[dict[str, Any]] = []
    if five:
        limits.append(five)
    if weekly:
        limits.append(weekly)

    month: dict[str, Any] = {"title": "This month", "resetsAt": period_end, "resetNote": ""}
    if allowance is not None and allowance > 0:
        used = max(0.0, allowance - remaining)
        pct = percent_used(used, allowance)
        month["percent"] = pct if pct is not None else 0.0
        month["valueLabel"] = f"{usd(used)} / {usd(allowance)}"
    else:
        month["percent"] = -1
        month["valueLabel"] = f"{usd(remaining)} left"
    limits.append(month)

    balance = None
    if purchased > 0:
        balance = {"remaining": purchased, "currency": "USD"}

    return record(
        "commandcode",
        "Command Code",
        "Command",
        ready=True,
        tier_label=tier,
        limits=limits,
        balance=balance,
    )


def collect_commandcode(opener: Callable[..., Any] | None = None) -> dict[str, Any] | None:
    key = require_key("COMMAND_CODE_API_KEY")
    if not key:
        return None
    host = commandcode_host()
    headers = commandcode_headers(key)
    status, payload = http_json(f"{host}/alpha/billing/credits", headers, opener=opener)
    if status in (401, 403):
        raise FetchError(
            "Command Code rejected the key. Use a Studio API key from commandcode.ai.",
            retry=False,
            auth=True,
        )
    if status >= 400 or not isinstance(payload, dict):
        raise FetchError(f"Command Code credits HTTP {status}")
    sub_status, sub_payload = http_json(f"{host}/alpha/billing/subscriptions", headers, opener=opener)
    subscription = sub_payload if sub_status < 400 else None
    parsed = parse_commandcode(payload, subscription)
    if parsed["ready"]:
        return parsed
    raise FetchError("Command Code returned no credits")


COLLECTORS: dict[str, Callable[..., dict[str, Any] | None]] = {
    "kimi": collect_kimi,
    "glm": collect_glm,
    "minimax": collect_minimax,
    "ollama": collect_ollama,
    "kilo": collect_kilo,
    "commandcode": collect_commandcode,
}

HELP = {
    "kimi": "Set KIMI_API_KEY to a Kimi Code Console key.",
    "glm": "Set ZAI_API_KEY to a GLM Coding Plan key.",
    "minimax": "Set MINIMAX_API_KEY to a MiniMax Token Plan Subscription Key.",
    "ollama": "Set OLLAMA_API_KEY from ollama.com/settings/keys.",
    "kilo": "Set KILO_API_KEY to the Gateway key at the bottom of app.kilo.ai/profile.",
    "commandcode": "Set COMMAND_CODE_API_KEY to a Studio API key from commandcode.ai.",
}


def write_record(path: Path, payload: dict[str, Any]) -> None:
    fd, tmp = tempfile.mkstemp(prefix="." + path.stem + ".", dir=path.parent)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, indent=2)
            handle.write("\n")
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def run_one(provider_id: str) -> int:
    dest = usage_dir() / f"{provider_id}.json"
    names = {
        "kimi": "Kimi Code",
        "glm": "GLM Coding Plan",
        "minimax": "MiniMax Token Plan",
        "ollama": "Ollama Cloud",
        "kilo": "Kilo Pass",
        "commandcode": "Command Code",
    }
    chips = {
        "kimi": "Kimi",
        "glm": "GLM",
        "minimax": "MiniMax",
        "ollama": "Ollama",
        "kilo": "Kilo",
        "commandcode": "Command",
    }
    try:
        result = COLLECTORS[provider_id]()
    except FetchError as err:
        write_record(
            dest,
            record(
                provider_id,
                names[provider_id],
                chips[provider_id],
                usage_status=str(err),
                auth_help=HELP[provider_id] if err.auth else "",
                retry=err.retry,
            ),
        )
        print(f"ai-sub-monitor: {provider_id}: {err}", file=sys.stderr)
        return 1
    except Exception as err:
        write_record(
            dest,
            record(
                provider_id,
                names[provider_id],
                chips[provider_id],
                usage_status="Usage request failed",
                retry=True,
            ),
        )
        print(f"ai-sub-monitor: {provider_id}: {err}", file=sys.stderr)
        return 1
    if result is None:
        if dest.exists():
            dest.unlink()
        return 0
    write_record(dest, result)
    return 0


def probe_provider(provider_id: str) -> dict[str, Any]:
    load_env_file()
    env_name = PROVIDER_ENV[provider_id]
    if not (os.environ.get(env_name) or "").strip():
        return {"ok": False, "id": provider_id, "message": "No key saved for this plan"}
    dest = usage_dir() / f"{provider_id}.json"
    dest.parent.mkdir(parents=True, exist_ok=True)
    run_one(provider_id)
    if not dest.is_file():
        return {"ok": False, "id": provider_id, "message": "No key saved for this plan"}
    rec = json.loads(dest.read_text(encoding="utf-8"))
    if rec.get("ready"):
        return {"ok": True, "id": provider_id, "message": "Connected"}
    message = rec.get("usageStatusText") or rec.get("authHelpText") or "Could not read usage"
    return {"ok": False, "id": provider_id, "message": str(message)}


def main() -> int:
    parser = argparse.ArgumentParser(description="Collect AI coding-plan usage")
    parser.add_argument("providers", nargs="*", choices=PROVIDER_ORDER)
    parser.add_argument("--except", dest="excluded", action="append", default=[], choices=PROVIDER_ORDER)
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--limits-only", action="store_true")
    parser.add_argument("--status", action="store_true", help="print which providers have keys; never print the keys")
    parser.add_argument("--save-keys", action="store_true", help="read one JSON object from stdin and write keys.env")
    parser.add_argument("--test", choices=PROVIDER_ORDER, help="probe one provider; print {ok,id,message}, never the key")
    args = parser.parse_args()

    if args.save_keys:
        raw = sys.stdin.readline()
        try:
            payload = json.loads(raw) if raw.strip() else {}
        except json.JSONDecodeError:
            print("ai-sub-monitor: invalid JSON on stdin", file=sys.stderr)
            return 1
        if not isinstance(payload, dict):
            print("ai-sub-monitor: stdin must be a JSON object", file=sys.stderr)
            return 1
        print(json.dumps(save_keys(payload)))
        return 0

    if args.test:
        print(json.dumps(probe_provider(args.test)))
        return 0

    load_env_file()
    if args.status:
        print(json.dumps(key_status()))
        return 0

    wanted = list(args.providers) if args.providers else list(PROVIDER_ORDER)
    excluded = set(args.excluded)
    status = 0
    ran = False
    for provider_id in PROVIDER_ORDER:
        if provider_id not in wanted or provider_id in excluded:
            continue
        ran = True
        if run_one(provider_id) != 0:
            status = 1
    if not ran:
        print("ai-sub-monitor: no providers selected", file=sys.stderr)
        return 1
    return status


if __name__ == "__main__":
    sys.exit(main())
