# Ollama environment — S15

Read-only survey on 2026-09-27. Nothing installed, started, pulled or configured.

## Machine

| Item | Value | Command |
|---|---|---|
| Architecture | arm64 (Apple M5, 10 cores: 4 performance + 6 efficiency) | `uname -m`, `system_profiler SPHardwareDataType` |
| RAM | 24 GB (`hw.memsize` 25769803776); memory free at check time 55 % | `sysctl -n hw.memsize`, `memory_pressure` |
| Free disk | 749 GiB of 926 GiB on the Data volume | `df -h .` |
| macOS | 27.0 (26A428) | `sw_vers` |

## Ollama state

| Check | Result |
|---|---|
| `command -v ollama` | not found (exit 1) |
| `ollama --version` | not run — command absent |
| `/Applications/Ollama.app`, `~/Applications/Ollama.app`, `/opt/homebrew/bin/ollama`, `/usr/local/bin/ollama` | absent |
| Homebrew formula/cask `ollama` | not installed (Homebrew present at `/opt/homebrew/bin/brew`) |
| `~/.ollama` (models directory) | absent — no models on disk |
| Process | none |
| Listener on TCP 11434 | none |
| `curl --fail --show-error --max-time 5 http://127.0.0.1:11434/api/tags` | exit 7, connection refused (also `localhost` and `[::1]`) |
| Other local runtime (LM Studio) | none found |

Conclusion: **not installed, not running, no model present.** Nothing else uses the runtime, so installing it will not disturb other work. The failed endpoint is explained by the absent install, not by a broken one.

## Model

PLAN does not name a model tag: F01 requires a local model through Ollama, “Model phải configurable, không hard-code architecture vào một model duy nhất”, and no background auto-download (§14). SPEC-MAP: the user approves the tag before S17. **Decision pending — no model chosen.**

Sizing guide for this Mac (24 GB unified memory, shared with macOS and other apps): a quantized model up to about 12–14 B parameters (≈ 5–9 GB download, similar RAM while loaded) leaves headroom; 27 B+ models (≈ 17 GB+) would compete with normal work. Disk is not a constraint.

Candidates for EN↔VI (to verify on the Ollama library at S16/S17 — names, sizes and availability change; no latency is promised before a benchmark in S22/S27):

| Candidate family | Approx. size (Q4) | Notes |
|---|---|---|
| Qwen (7–8 B) | ≈ 5 GB | Strong multilingual incl. Vietnamese; fast on Apple silicon |
| Gemma 3 (4 B / 12 B) | ≈ 3 GB / ≈ 8 GB | Good multilingual; 12 B better quality, slower |
| Translation-tuned Gemma variant (if listed) | 4 B / 12 B | Unverified availability in the Ollama library |
| Llama 3.x 8 B | ≈ 5 GB | Vietnamese weaker than the above |

The app will keep the model tag configurable (S18); the candidate list is not a spec.

## Not verified

- Whether the tags above exist in the Ollama library today, their exact sizes and licences.
- Translation quality and speed on this Mac (S22/S27).
- Ollama behaviour on macOS 27.

# S16 — Install (method A, official app, installed by the user)

Checked 2026-09-28, read-only.

| Check | Result |
|---|---|
| App | `/Applications/Ollama.app`, version 0.34.4 |
| CLI | `/usr/local/bin/ollama` → symlink to `/Applications/Ollama.app/Contents/Resources/ollama` (created by the app’s first-run setup) |
| `ollama --version` | `ollama version is 0.34.4` |
| `curl --fail --show-error --max-time 5 http://127.0.0.1:11434/api/tags` | exit 0, `{"models":[]}` |
| `/api/version` | `{"version":"0.34.4"}` |
| Listener | `ollama` PID 35230, `TCP 127.0.0.1:11434 (LISTEN)` only — not bound to LAN |
| Started by | `Ollama.app` (PID 35224, `hidden`) → `ollama serve` (PID 35230). One daemon, no duplicate |
| `OLLAMA_HOST` | not set (launchctl and shell) — default localhost binding |
| Models | none (`ollama list` empty) |

An interactive `ollama` launcher (PID 35567, “Select model for ChatGPT”) was open in the user’s terminal; it is Ollama’s picker for another integration, unrelated to this app. Nothing was selected by the agent.

## Local-only rule for model tags

Tags ending in `:cloud` or `-cloud` (e.g. `gpt-oss:20b-cloud`, `gemma4:31b-cloud`, `glm-…:cloud`) run on Ollama’s servers and need sign-in. They would send the selected text off this Mac, violating PLAN F01 and AGENTS.md. Never use them; the app should refuse such tags (S18).

## Model survey (ollama.com/library, 2026-09-28)

| Tag | Size | Notes for this app |
|---|---|---|
| `translategemma:4b` / `:12b` / `:27b` | 3.3 / 8.1 / 17 GB | Translation-tuned Gemma 3, 55 languages incl. Vietnamese; fixed translator prompt format; no thinking phase → fastest first token |
| `gpt-oss:20b` | 14 GB | OpenAI open-weight, local, 16 GB+ memory; reasoning model (effort low/medium/high) — emits thinking before the answer, so slower first token; not translation-tuned |
| `gpt-oss:120b` | 65 GB | Too large for 24 GB |
| `gemma4:e2b` / `:e4b` / `:12b` / `:26b` / `:31b` (+ `-mlx`) | 7.2 / 9.6 / 7.6 / 19 / 20 GB | General multimodal; 26b/31b too large to run comfortably on 24 GB |

Sizes from the library page; quality and latency not measured yet (S22/S27).

# S17 — Model `translategemma:12b` (approved by the user)

Pulled 2026-09-28 with `ollama pull translategemma:12b` (exit 0, `.build/logs/S17-pull.log`, ~8 min at ~17 MB/s). Not a cloud tag.

| Item | Value |
|---|---|
| Tag / ID | `translategemma:12b` / `c2f9a9ca1ec7` |
| Digest | `sha256:c2f9a9ca1ec7149f2422581c89937ab0363d9399d9355514d753ee012e99c252` |
| Size | 8,109,827,612 bytes (8.1 GB), GGUF |
| Architecture | gemma3, 12.2 B parameters, Q4_K_M, context length 131072 (Ollama loaded it with 4096) |
| Capabilities | completion, vision |
| Default parameters | `top_p 0.95`, `top_k 64`, `stop "<end_of_turn>"` |
| Chat template | Gemma turns; system messages are rendered as user turns |
| License | Gemma Terms of Use (last modified 2024-02-21) — local personal use; redistribution of the model is not part of this app |

## Prompt format (model card, ollama.com/library/translategemma)

One user message, no separate system prompt; exactly two blank lines before the text:

```text
You are a professional {SOURCE_LANG} ({SOURCE_CODE}) to {TARGET_LANG} ({TARGET_CODE}) translator. Your goal is to accurately convey the meaning and nuances of the original {SOURCE_LANG} text while adhering to {TARGET_LANG} grammar, vocabulary, and cultural sensitivities.
Produce only the {TARGET_LANG} translation, without any additional explanations or commentary. Please translate the following {SOURCE_LANG} text into {TARGET_LANG}:


{TEXT}
```

Codes: English `en`, Vietnamese `vi`. This template is specific to this model (runbook: do not apply one prompt to every model) — S18/S22 keep it per model.

## Smoke test (synthetic sentences, `POST http://127.0.0.1:11434/api/chat`, streaming)

| Direction | Input | Output | First token | Total |
|---|---|---|---|---|
| EN→VI | The payment has been processed and the receipt was sent to your email. | Thanh toán đã được xử lý và hóa đơn đã được gửi đến địa chỉ email của bạn. | 5.81 s (cold: model load 5.12 s) | 7.01 s |
| VI→EN | Cuộc họp sẽ bắt đầu lúc 9 giờ sáng mai. | The meeting will begin at 9:00 AM tomorrow. | 0.37 s (warm) | 1.15 s |

- Generation ≈ 17–18 tokens/s; prompt ≈ 90 tokens; `ollama ps`: 8.1 GB, 100 % GPU, unloaded after 5 min idle (Ollama default keep-alive).
- Implication for S18/S23/S25 (not decided here): the first translation after idle pays ~5 s model load; options are a readiness warm-up or a `keep_alive` choice — needs a decision.
- Single run each, not a benchmark; quality review of more cases is S22, latency p50/p95 is S27.

## Local-only evidence and offline check

- Network-socket evidence (2026-09-28, Wi-Fi on): during a repeat of the smoke test, `lsof -i` sampled every 0.1 s for all Ollama processes (app PID 35224, `ollama serve` 35230, `llama-server` runner 44566) showed only `127.0.0.1` sockets (11434 API, runner port 55394, app port 53915). No connection to any external host during inference. Outputs identical to the first run.
- True offline run: user-run (2026-09-28) following the offline procedure (Wi-Fi off, script run in the user's Terminal); the screenshot shows the output only, network state as reported by the procedure, not independently verified by the agent. Results: EN→VI identical translation, first token 0.24 s, total 1.46 s; VI→EN identical, first token 0.16 s, total 0.95 s; ~17.5 tok/s.
- Earlier: the agent session itself needs the network, so it cannot run the check with Wi-Fi off (an earlier attempt ran with Wi-Fi still on: `Wi-Fi Power (en0): On`, `ollama.com` HTTP 200 — not counted). The user can run it alone, or it is covered by the PLAN §20 offline DoD check in S27.

# S18 — App client

- Endpoint `http://127.0.0.1:11434` (loopback only, redirects refused); model tag from Settings (default `translategemma:12b`); cloud tags refused.
- Readiness: `GET /api/version` + `GET /api/tags` every 20 s; runtime missing and model missing are reported separately.
- Live integration test (`TEST_RUNNER_LT_LIVE_OLLAMA=1 … -only-testing:LocalTranslatorTests/OllamaLiveTests`): PASS, 3.8 s including model load. No ATS exception needed for loopback HTTP.

## Keep-alive options — decided: B (user, 2026-09-28: “B đi”), `keep_alive: "30m"` on translation requests, implemented with the real client in S20

Ollama unloads a model 5 min after its last request; the next translation then waits ~5 s for loading (S17).

| Option | Effect | Cost |
|---|---|---|
| A. Ollama default (5 min) | No change | ~5 s first translation after 5 min idle |
| B. `keep_alive: "30m"` on translation requests | Model stays loaded 30 min after last use | ~8 GB unified memory held during that time |
| C. `keep_alive: -1` | Model always loaded while Ollama runs | ~8 GB held permanently |
| D. Warm-up request when Ollama connects | Removes the first-use wait at the cost of loading at login | ~8 GB loaded even if never used |

Note (S20): every request must carry `keep_alive: "30m"`; a request without it resets Ollama's unload timer to the 5-minute default. Other apps using the same Ollama can also change it.

## Context and prompt (S22)

- Context: translategemma:12b loads with `context_length 4096` here (`/api/ps`); model maximum 131072, sliding window 1024. The app sends `options.num_ctx 4096` on every translation, so its limit is known and no reload happens. Raising it (e.g. 8192) would allow longer selections at some memory cost; not done without a user decision.
- Measured tokens (synthetic text): template 76; 4.8–5.7 UTF-8 bytes per token for en/vi/ja; EN → VI output 1.64 × input, VI → EN 0.69 ×.
- Prompt: model-card template kept unchanged (variants asking for natural tone or kept English terms gave no clear gain on the 15-case fixture, docs/PROGRESS.md S22).

