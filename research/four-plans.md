# Four-plan usage API research

Date: 2026-08-27. No live keys were used in this pass.

Goal: can Spencer's four subscriptions expose 5-hour / weekly / monthly usage via an API key?

## Verdict

| Plan | 5-hour | Weekly | Monthly | Reset times | Via API key? |
|------|--------|--------|---------|-------------|--------------|
| Kimi Code | Yes | Yes | Product exists; not a reliable API field | Yes (5h + weekly) | Yes, undocumented first-party route |
| GLM Coding Plan (Z.AI) | Yes | Yes | No coding-credit month; MCP/search may be monthly | Yes | Yes, first-party plugin route, not in OpenAPI |
| MiniMax Token Plan | Yes | Yes | Billing cycle only, no meter in API | Yes | Yes, **official** FAQ endpoint |
| Ollama Cloud | Yes | Yes | Extra-usage balance, not a third window | Dashboard has countdowns; `/api/usage` does **not** return reset timestamps | Yes via undocumented `GET https://ollama.com/api/usage` |

Wrong keys look like they work and return the **wrong product** (wallet CNY/USD). That is how AI Subs mis-reports Kimi and Z.AI.

## 1. Kimi Code

- Product: Kimi membership coding plan. Host `https://api.kimi.com/coding/v1`. Not `api.moonshot.ai` / `api.moonshot.cn` PAYG wallet.
- Docs: 7-day quota from subscribe date + rolling 5-hour window. Monthly Kimi membership freeze is dashboard-only ([membership](https://www.kimi.com/code/docs/en/kimi-code/membership)).
- Usage URL (first-party CLI + Moonshot staff, **not** in the public API catalog): `GET https://api.kimi.com/coding/v1/usages` with `Authorization: Bearer <Kimi Code Console key>`.
- Public docs: [overview](https://www.kimi.com/code/docs/en/), [membership](https://www.kimi.com/code/docs/en/kimi-code/membership), [CLI `/usage`](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/slash-commands.html).
- PAYG wallet (wrong product): `GET https://api.moonshot.ai/v1/users/me/balance` or `.cn`.

Confirm:

```bash
curl -sS -H "Authorization: Bearer $KIMI_API_KEY" -H "Accept: application/json" \
  "https://api.kimi.com/coding/v1/usages"
```

Expect `usage` (weekly) plus `limits[]` (5-hour). 401 = platform/PAYG key, not a Code Console key.

## 2. GLM Coding Plan (Z.AI / Zhipu)

- Product: GLM Coding Plan on `api.z.ai` (global) or `open.bigmodel.cn` (CN). Inference base is `/api/coding/paas/v4`, not `/api/paas/v4`.
- Docs: 5-hour credits + weekly credits. [overview](https://docs.z.ai/devpack/overview).
- Usage URL used by Z.AI's own `glm-plan-usage` plugin: `GET https://api.z.ai/api/monitor/usage/quota/limit` with `Authorization: <key>` (often **no** `Bearer `; try both). CN: `https://open.bigmodel.cn/api/monitor/usage/quota/limit`.
- Not in [OpenAPI](https://docs.z.ai/openapi.json). Schema has drifted (`TOKENS_LIMIT` → `CREDIT_LIMIT`). Unstable.
- Wallet (wrong product): `GET https://open.bigmodel.cn/api/paas/v4/user/balance`.

Confirm (try raw header first, then Bearer; try `api.z.ai` then `open.bigmodel.cn`):

```bash
curl -sS -H "Authorization: $ZAI_API_KEY" -H "Accept-Language: en-US,en" \
  "https://api.z.ai/api/monitor/usage/quota/limit"
```

Expect `data.limits[]`. 5h ≈ `unit` 3; weekly ≈ `unit` 6; `nextResetTime` in ms.

## 3. MiniMax Token Plan

- Product: Token Plan **Subscription Key**, not PAYG `sk-api-…` key. Global `api.minimax.io` vs CN `api.minimaxi.com` are separate.
- Official FAQ: [Global](https://platform.minimax.io/docs/token-plan/faq), [subscribe page](https://platform.minimax.io/subscribe/token-plan).
- Usage URL: `GET /v1/token_plan/remains` with `Authorization: Bearer <Subscription Key>`.
- Success is `base_resp.status_code === 0` (HTTP 200 can still be a login fail).
- `general` row: interval remaining % + weekly remaining %. No monthly meter.

Confirm:

```bash
curl -sS -H "Authorization: Bearer $MINIMAX_API_KEY" \
  -H "Content-Type: application/json" \
  "https://api.minimax.io/v1/token_plan/remains"
```

China host: `https://api.minimaxi.com/v1/token_plan/remains`. 2049 = wrong region or PAYG key.

## 4. Ollama Cloud (not LlamaIndex)

Correction: the fourth plan is **Ollama Cloud** (`ollama.com`), not LlamaIndex LlamaCloud.

- Product: Free / Pro / Max. Official pricing: session limits reset every **5 hours**, weekly limits reset every **7 days**. Usage is compute-weighted, not a fixed token cap. [pricing](https://ollama.com/pricing)
- Official docs page titled “Usage” is **per-response** token timings (`prompt_eval_count`, `eval_count`). That is **not** account quota. [docs.ollama.com/api/usage](https://docs.ollama.com/api/usage)
- Account quota URL used by community tools (Pi, menu-bar widgets) and named by Ollama maintainers on GitHub: `GET https://ollama.com/api/usage` with `Authorization: Bearer $OLLAMA_API_KEY`. **Not in the public API catalog.** Feature requests for a documented quota API are still open ([#12532](https://github.com/ollama/ollama/issues/12532), [#15663](https://github.com/ollama/ollama/issues/15663)).
- Observed JSON shape (community parsers): `limits.session.usage` and `limits.weekly.usage` as **0–1 fractions**, plus per-model `request_count`. Optional `activity.cost` (4-week). **No `resets_at` field** in that schema.
- Dashboard `https://ollama.com/settings` has the countdowns. Exact reset clocks are not in `/api/usage`; some people infer global 5h/7d wall-clock windows — unverified as a contract.

Confirm:

```bash
curl -sS -H "Authorization: Bearer $OLLAMA_API_KEY" \
  "https://ollama.com/api/usage"
```

Expect `limits.session.usage` and `limits.weekly.usage`. Key from [ollama.com/settings/keys](https://ollama.com/settings/keys). Also try without `Bearer` if 401.

## 5. OpenRouter (credits, not windows)

- Official: `GET https://openrouter.ai/api/v1/credits` — [docs](https://openrouter.ai/docs/api/api-reference/credits/get-remaining-credits)
- Response: `data.total_credits`, `data.total_usage` (USD). Remaining = credits − usage.
- Docs now say a **Management** key is required. A normal inference key may 401/403.

```bash
curl -sS -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  "https://openrouter.ai/api/v1/credits"
```

## 6. Venice.ai (credits, not windows)

- Official: `GET https://api.venice.ai/api/v1/billing/balance` — [docs](https://docs.venice.ai/api-reference/endpoint/billing/balance)
- Returns remaining USD / DIEM. Bundled “AI credits” may **not** be in this payload (`canConsume` ignores bundled credits).
- Needs an **Admin** key. Inference-only keys 401.

```bash
curl -sS -H "Authorization: Bearer $VENICE_API_KEY" \
  "https://api.venice.ai/api/v1/billing/balance"
```

## Existing plugins vs these four

- `meviusisback/omarchy-ai-subs`: Kimi + Z.AI hit **wallets**. MiniMax and Ollama Cloud absent.
- `akitaonrails.ai-usagebar`: Kimi `/usages`, Z.AI `quota/limit`, MiniMax `token_plan/remains`. No Ollama Cloud.
- Built-in `omarchy.agents`: Claude / Codex / Fireworks only.
