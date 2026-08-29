# AI Sub Monitor

Omarchy bar panel for six live-verified coding plans: **Kimi Code** (Moonshot AI), **GLM Coding Plan** (Z.ai), **MiniMax Token Plan** (MiniMax), **Ollama Cloud** (Ollama), **Kilo Pass** (Kilo), **Command Code** (Command Code).

Bar glyph is `md-chart_donut` (󰞯). The panel is a **2-column donut grid** of **configured** plans plus a **Settings** tab for keys. It does not scrape cookies, impersonate OAuth apps, or hit PAYG wallets.

## Install on this machine

Repo is **private**. Cloning it into `~/.config/omarchy/plugins/` hot-reloads omarchy-shell. If the session is locked, that reload can kill the lock screen.

1. `omarchy plugin add git@github.com:spenceriam/ai-sub-monitor.git --enable --yes`
2. If it is not already on the bar: `omarchy plugin enable io.github.spenceriam.ai-sub-monitor --section right --after stappmus.activity-monitor`
3. First click (no keys yet) opens **Settings**: pick one plan → paste the key → **Save and test**.
4. After that: left-click the donut for **Usage**, right-click for **Settings**.
5. Later updates: `omarchy plugin update io.github.spenceriam.ai-sub-monitor --yes`

`omarchy plugin add` refuses the install if this id is already present as a non-git copy. Remove that folder first, or replace it with a clone of this repo. Do not put keys in `shell.json`.

The donut stays on the bar with zero keys so setup is always reachable.

**First-time setup:** any click with no saved keys opens **Settings** — a plan picker, not five empty fields. Pick one service, paste its key, **Save and test** (hits that provider’s usage endpoint; the key is never logged). Until a key is saved, left-click keeps taking you back to that picker.

**After a plan is saved:** left-click opens **Usage**, right-click opens **Settings**. Usage lists saved plans that are not hidden. The Settings eye (󰈈) hides a tile; the crossed eye (󰈉) means it is hidden. Removing every key later shows empty Usage (setup already happened), not the picker. Don't see your plan in the list? **Request it on GitHub** (bottom of Settings).

Click a tile to toggle it open or closed (donut left, LIMITS/models right). Hold or drag a **collapsed** tile to reorder; neighbors slide with the same 380ms easeOutQuint curve as Hyprland window moves. Each provider keeps its own open/closed state. Hero + Usage/Settings stay pinned; only the tiles scroll. The panel grows until **70% of the screen height**, then a 6px themed scrollbar appears under the tabs.

Density is **Comfy** by default (Omarchy `panelPadding` 18 / `panelGap` 14). **Compact** is a Settings toggle. Saved plans have an **eye** in Settings: click to hide the Usage tile without removing the key. Density, order, and hidden plans persist in `$XDG_STATE_HOME/omarchy/ai-sub-monitor/ui.json`.

## Keys (do not put these in `shell.json`)

Preferred file: `~/.config/ai-sub-monitor/keys.env` (directory `0700`, file `0600`). Legacy read: `~/.config/omarchy/ai-sub-monitor.env`. Override path: `AI_SUB_MONITOR_ENV`. Existing environment variables win over the file.

The Settings tab writes that file through `collect.py --save-keys` on stdin (same pattern as Wi-Fi passphrase: never argv, never logged). `--status` prints `{kimi,glm,minimax,ollama,kilo,commandcode}` as booleans only. **Save and test** runs `collect.py --test <id>`: it hits that plan’s usage endpoint and prints `{ok,id,message}` — never the key.

| Plan | Provider | Env var | Endpoint |
|---|---|---|---|
| Kimi Code | Moonshot AI | `KIMI_API_KEY` | `GET https://api.kimi.com/coding/v1/usages` (Bearer) |
| GLM Coding Plan | Z.ai | `ZAI_API_KEY` | `GET https://api.z.ai/api/monitor/usage/quota/limit` (raw `Authorization`) |
| MiniMax Token Plan | MiniMax | `MINIMAX_API_KEY` | `GET https://api.minimax.io/v1/token_plan/remains` (Bearer) |
| Ollama Cloud | Ollama | `OLLAMA_API_KEY` | `GET https://ollama.com/api/usage` (Bearer) |
| Kilo Pass | Kilo | `KILO_API_KEY` | `GET https://app.kilo.ai/api/trpc/kiloPass.getState` + `GET https://api.kilo.ai/api/profile/balance` (Bearer) |
| Command Code | Command Code | `COMMAND_CODE_API_KEY` | `GET https://api.commandcode.ai/alpha/billing/credits` + `GET …/alpha/billing/subscriptions` (Bearer). Studio API key, not a session cookie. |

Wrong keys return the wrong product (Moonshot/Z.AI wallets, MiniMax PAYG, Kilo BYOK provider keys). China hosts: set `ZAI_HOST=https://open.bigmodel.cn` or `MINIMAX_HOST=https://api.minimaxi.com` in the env file. Kilo org wallet: `KILO_ORG_ID`.

Ollama `/api/usage` has no reset timestamps (dashboard does). The panel shows **Resets every 5 hours / every 7 days** until that field exists. GLM coding plan is 5h + weekly, not monthly. MCP/search is not shown.

Empty Save leaves a stored key unchanged. **Remove key** deletes that provider from the file and drops it from the list.

## Notifications

Omarchy’s daemon is `omarchy.notifications`. Plugins send toasts with `omarchy notification send` (wrapper: `omarchy-notification-send`). Do not use `notify-send` — it is treated as ephemeral and its argv parsing is unsafe for untrusted text.

```bash
omarchy notification send -g 󰞯 "Ollama Cloud added" "Connected."
omarchy notification send --app-name "AI Subs" -u normal -g 󰞯 "Ollama Cloud needs attention" "Key rejected"
omarchy notification send --app-name "AI Subs" -u critical -g 󰞯 "Ollama Cloud is at 94%" "Usage is 90% or higher."
```

This plugin fires those three cases: **plan added** (after a successful Save and test of a new key), **plan problem** (auth/usage failure), **≥90% usage**. Each plan notifies once until it recovers (problem cleared, or usage drops below 90%). Clicking a toast opens the panel. Dedup state: `$XDG_STATE_HOME/omarchy/ai-sub-monitor/notify.json`.

## Keys in the panel

- First open with no keys: Settings picker (pick one plan, paste key, Save and test)
- Left click: Usage (closes if Usage is already open)
- Right click: Settings (closes if Settings is already open)
- Middle click: Usage ↔ Settings
- `s` Settings, `u` Usage, `h`/`l` switch tabs, `r` refresh, Esc close

## Not in v1

OpenRouter, Venice, Sakana, Gemini CLI OAuth, Grok, cookie scrapes.

## Mockup

Open `mockup/index.html`. Demo assumes Kimi, MiniMax, Ollama, Kilo Pass, and Command Code are configured; GLM is not. First-run picker: `?onboard=1`. Kilo numbers match the 2026-08-28 profile screenshot (`$0.00 / $73.50` this month, `$208.70` remaining). Command Code numbers match a live Go-plan credits payload (`$1.22 / $10.00` this month). Query flags: `?expanded=kilo&density=compact&only=kimi,minimax,ollama,kilo,commandcode`.

## Tests

```bash
python3 tests/test_collect.py
```
