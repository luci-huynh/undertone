# QA report — S27

Status: automated measurements done; user ran the Release build 13:33–13:37 and reported “Đã xong, chất lượng ổn, feature hoạt động” (summary, not itemised per app). Results below combine that report with the app's metadata logs; an app that is not installed stays NOT RUN (never PASS).

## Environment (2026-09-28)

| Item | Value |
|---|---|
| Mac | Apple M5, 24 GB unified memory |
| macOS | 27.0 (26A428) |
| Xcode | 27.0 (27A266a) |
| Displays | built-in Liquid Retina XDR 3024 × 1964 (main) + external 1920 × 1080 |
| Ollama | 0.34.4 (Ollama.app), `127.0.0.1:11434` |
| Model | `translategemma:12b`, digest `c2f9a9ca…c252`, Q4_K_M, 8.1 GB, 100 % GPU, context 4096 |
| App build | Release, `.build/DerivedData/Build/Products/Release/LocalTranslator.app`, signed with the Personal Team, not sandboxed |

## Measurements (automated, synthetic text)

PLAN §15 targets: shortcut → popup **< 150 ms**; request Ollama immediately; first token “as fast as local model allows”; app lightweight and does not load the model. No other thresholds exist, so the numbers below are for review, not a claim of “meets target”.

Ollama `/api/chat`, streaming, app prompt and options (`num_ctx 4096`, `keep_alive 30m`):

| Case | First text | Done | Output | Speed |
|---|---|---|---|---|
| Cold (model unloaded) EN → VI, 196 chars | 3.57 s | 7.03 s | 57 tokens | 16.4 tok/s |
| Warm EN → VI, 196 chars | 0.15 s | 3.72 s | 57 tokens | 16.0 tok/s |
| Warm VI → EN, 201 chars | 0.43 s | 2.62 s | 36 tokens | 16.4 tok/s |
| Warm EN → VI, 980 chars | 0.72 s | 19.4 s | 276 tokens | 14.8 tok/s |
| Warm VI → EN, 804 chars | 1.06 s | 10.2 s | 141 tokens | 15.5 tok/s |
| Warm EN → VI, 4.9 KB (S23) | 3.0 s | 98 s | — | — |
| Cold EN → VI, 4.9 KB (S23) | 4.4 s | 115 s | — | — |
| Cold after Ollama restart, short (S18/S20) | 5.9–6.3 s | — | — | — |

App (Release build, idle, 60 × 1 s `top` samples): CPU **0.03 %** average, 1.2 % max; memory footprint 18 MB (`top`), RSS 81.6 MB. Only network socket: `127.0.0.1 → 127.0.0.1:11434` (readiness keep-alive). The app does not load the model; Ollama's `llama-server` holds 8.7 GB RSS while the model is loaded (30 min after last use, user decision B).

### In-app, Release build, user session (17 selections, 18–130 chars, real apps)

| Measure | min | median | p90 | max |
|---|---|---|---|---|
| AX capture | 2 ms | 8 ms | 11 ms | 19 ms |
| Trigger → popup shown | 14 ms | 32 ms | 40 ms | 81 ms |
| Request → first text | 180 ms | 387 ms | 423 ms | 2,009 ms (first request of the session) |
| Request → done | 732 ms | 1,072 ms | 2,691 ms | 2,957 ms |

All 17 trigger → popup values are below PLAN's 150 ms. They start when the app's hot-key handler (or the selection button) runs; the key-press → handler delay is not included.

In-app timings come from metadata logs added in S27 (no text): `Selection captured: <n> chars in <ms>`, `Popup shown <ms> after trigger`, `Translated <in> → <out> chars; first text <ms>, done <ms>`. They are read after the manual run with `log show --predicate 'subsystem == "local.chienhuynh.LocalTranslator"'`. Key-press → hot-key handler latency is not measurable from inside the app.

## Source app matrix (manual)

User summary for the apps tried: features work (⌥T EN/VI, selection button, ⇄, Retry, Copy). The report was not itemised per app, so per-app cells are recorded as “PASS (summary)” only where the app was part of the requested list; details remain for S31 acceptance.

| App | Version | Result | Notes |
|---|---|---|---|
| TextEdit | 1.21 | PASS (summary) | Also PASS S10/S12 |
| Notes | 4.13 | PASS (summary) | |
| Mail | 16.0 | PASS (summary) | |
| Preview (PDF with text layer) | 11.0 | PASS (summary) | Scanned PDF without text layer is out of scope (no OCR), not an AX failure |
| Google Chrome | 153.0.8010.53 | PASS (summary) | Warm-up after launch (S12c) |
| Brave | 153.1.95.102 | PASS (summary) | Warm-up (S12c) |
| Slack | 4.52.162 | PASS (summary) | Warm-up (S12b) |
| Notion | 7.35.1 | PASS (summary) | Warm-up (S12b) |
| VS Code | 1.139.1 | PASS (summary) | |
| Microsoft Outlook | 16.113.2 | PASS (summary) | First check |
| Microsoft Word | 16.113.2 | PASS (summary) | Not in PLAN list |
| Safari | 27.0 | Not reported (optional) | FAIL at S12, low priority (user) |
| Pages | — | NOT RUN | Not installed; not installed by QA |
| Adobe Acrobat Reader | — | NOT RUN | Not installed |

## Scenarios (manual)

| Scenario | Result | Evidence |
|---|---|---|
| Offline | **PASS** | Wi-Fi powered off 13:35:19.8 → on 13:35:55.6 (airportd log); 6 translations finished in that window (incl. ⇄ and Retry), no failures; only socket loopback (Release idle check) |
| Rapid ⌥T | **PASS** | 5 presses 0.22–0.31 s apart (13:34:x); no failure logged, app kept working |
| ⇄ and Retry / ↻ | PASS | 3 direction switches, 3 retries logged, all completed |
| Selection button | PASS | 7 clicks logged |
| Nothing selected | PASS | 2 × “No text selected” notice |
| External display, full-screen app | PASS (summary) | Not visible in logs (anchors are not logged) |
| Accessibility revoked / granted while running | PASS (S23 user check 4) | Not re-run |
| Cold vs warm model | Measured (tables above) | First in-app request 2.0 s to first text, later 0.18–0.44 s |
| Long text (~1 page) and over the limit (> ~5,000 chars) | **Accepted on automated evidence** (user option b, 2026-09-28: long selections not needed in practice); not run manually | Longest selection in the Release session 130 chars; no “too long” event. Covered by S22/S23 automated tests and S23 measurements (4.9 KB: 98–115 s) |
| Translation quality, user's own EN/VI samples | PASS (user: “chất lượng ổn”) | Texts not collected |

## Bugs found

None yet in S27.

## S31 final checks (installed copy, 2026-09-28 14:19)

| Check | Result |
|---|---|
| `/Applications/LocalTranslator.app` identical to the archive | PASS (`diff -rq`, same CDHash) |
| Launch with `-OllamaBaseURL http://127.0.0.1:1` | “Ollama Not running” |
| Launch with `-TranslationModelTag nope:1b` | “Connected, model missing” |
| Launch with `-OllamaBaseURL http://example.com:11434` | “Endpoint not local”, nothing sent |
| Normal launch afterwards | “Connected, model installed”; no override persisted |
| Offline after setup | PASS (S27) |
| Clean machine / clean account | NOT RUN |
| User flow select → ⌥T/button → stream → Copy/Close on the release build | PASS (S29 user: “Đã hoạt động”) |

