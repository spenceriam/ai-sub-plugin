# AI Sub Monitor

Quick glance plugin for AI subscriptions such as Kimi Code, MiniMax Token Plan, Z.ai GLM Coding Plan, Cursor, and others. It sits on the Omarchy bar. Keys stay in a local env file.

Plugin id: `io.github.spenceriam.ai-sub-monitor`. License: MIT.

![AI Subs usage panel](preview.png)

![AI Subs expanded tile](preview-expanded.png)

## Install

```sh
omarchy plugin add https://github.com/spenceriam/ai-sub-plugin.git --enable
```

That clones into `~/.config/omarchy/plugins/` and reloads omarchy-shell. If the session is locked, a reload can kill the lock screen.

`--enable` puts the widget in the bar’s right section at Omarchy’s default slot (after the tray). The pop-down pins to the right screen edge, same as Network, Bluetooth, and Audio.

Python 3 is required (`collect.py` uses the stdlib only). No extra packages, daemons, or sudo.

## Update

`omarchy plugin add` clones `main`. `omarchy plugin update` fast-forwards that clone. Ship a version by bumping `version` in `manifest.json`, pushing `main`, and tagging the same commit `vX.Y.Z`. The first release is `v0.1.0`. A GitHub Action turns that tag into a Release.

```sh
omarchy plugin update io.github.spenceriam.ai-sub-monitor
```

The plugin checks GitHub Releases about every six hours. If the latest tag is newer than the installed `manifest.json` version, you get an Omarchy notification. Settings shows the version and an Update plugin button, which runs the same command in a terminal so you can read the diff first.

## Usage

- First click with no saved plans opens **Settings** (pick one plan, paste the key, **Save and test**). Cursor is **Connect and test** — it uses the Cursor IDE or `cursor-agent login`, not a pasted key.
- After a key is saved: left-click **Usage**, right-click **Settings**, middle-click switches. The same view again closes the panel.
- Click a tile to expand or collapse it. Hold or drag a collapsed tile to reorder.
- `s` Settings, `u` Usage, `h`/`l` switch tabs, `r` refresh, Esc close.

Usage lists saved plans that are not hidden. The Settings eye (󰈈) hides a tile without removing the key. Missing a plan? Request it from the bottom of Settings.

## Configure

```sh
omarchy bar move io.github.spenceriam.ai-sub-monitor --section right
```

Do not put API keys in `shell.json`. Save them in Settings, which writes `~/.config/ai-sub-monitor/keys.env` (directory `0700`, file `0600`). Override path: `AI_SUB_MONITOR_ENV`. Existing environment variables win over the file.

| Plan | Provider | Env var |
|---|---|---|
| Kimi Code | Moonshot AI | `KIMI_API_KEY` |
| GLM Coding Plan | Z.ai | `ZAI_API_KEY` |
| MiniMax Token Plan | MiniMax | `MINIMAX_API_KEY` |
| Ollama Cloud | Ollama | `OLLAMA_API_KEY` |
| Kilo Pass | Kilo | `KILO_API_KEY` |
| Command Code | Command Code | `COMMAND_CODE_API_KEY` |
| Cursor | Anysphere | `CURSOR_ENABLED` (Settings writes this; no session token in the file) |

Use a Code Console / coding-plan / Subscription / gateway / Studio key — not Moonshot/Z.AI wallets, MiniMax PAYG, or Kilo BYOK provider keys. China hosts: `ZAI_HOST` or `MINIMAX_HOST` in the env file. Kilo org wallet: `KILO_ORG_ID`. Cursor reads `~/.config/Cursor/User/globalStorage/state.vscdb` or `~/.config/cursor/auth.json`.

Bar setting `refreshIntervalSec` (30–3600, default 300) is the usage poll interval. Density, tile order, and hidden plans persist in `$XDG_STATE_HOME/omarchy/ai-sub-monitor/ui.json`.

## Remove

Delete saved keys and usage files first (the plugin folder still has to exist for this command). `--yes` is required. Without it, nothing is deleted.

```sh
python3 collect.py --uninstall --yes
omarchy plugin remove io.github.spenceriam.ai-sub-monitor
```

`collect.py --uninstall` only removes this plugin's key directory, the legacy env file, and the usage state directory. It refuses any other path. `omarchy plugin remove` takes the widget off the bar and deletes the plugin checkout.

If the plugin is already gone, run `--uninstall` from a clone of this repo.

## Dependencies

- **Python 3** (stdlib). `collect.py` calls each provider’s usage HTTP API with the saved Bearer/Authorization key. Cursor uses the local IDE/`cursor-agent` session instead.
- **Omarchy notifications** via `omarchy notification send` (not `notify-send`): plan added, key/usage failure, usage ≥ 90%.
- Network to: `api.kimi.com`, `api.z.ai` (or `open.bigmodel.cn`), `api.minimax.io` (or `api.minimaxi.com`), `ollama.com`, `app.kilo.ai` / `api.kilo.ai`, `api.commandcode.ai`, `api2.cursor.sh`.

## Contribute

If a coding plan you use is not in the list, open a GitHub issue. If you already know the usage API, send a pull request too.

- [Request a plan (issue)](https://github.com/spenceriam/ai-sub-plugin/issues/new?title=Request%20a%20plan&body=Plan%20name%3A%0AProvider%20%28and%20site%29%3A%0ADocs%20or%20pricing%20URL%3A%0AUsage%20API%20%28if%20you%20have%20it%29%3A%0A)
- [Open a pull request](https://github.com/spenceriam/ai-sub-plugin/compare)

Paste this into the issue:

```md
Plan name:
Provider (and site):
Docs or pricing URL:
Usage API (if you have it):
```

A PR should add a collector in `collect.py`, a fixture under `tests/fixtures/`, and a Settings picker row. Use the provider's official plan name.

## Credits

Cursor session detection and dashboard usage RPCs follow [mrlarsendk/omarchy-cursor-usage](https://github.com/mrlarsendk/omarchy-cursor-usage) (MIT, Copyright 2026 Michael Larsen). This plugin maps those meters into the same tiles as the other plans.
