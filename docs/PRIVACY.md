# Privacy review — S28

0.3.0 (4): renamed to Undertone — bundle ID `local.chienhuynh.Undertone`, log subsystem `local.chienhuynh.Undertone`; entries below keep their historical names.

PLAN F08: selected text goes only to localhost → Ollama; no OpenAI, Google Translate, analytics or external logging; no translation history; debug logs metadata only.

## Data flow

1. **Read.** On ⌥T, or a mouse selection when the selection button is on, the app reads the focused element's selected text through Accessibility (`kAXSelectedTextAttribute`). It never reads secure fields (secure input check first) or its own windows. The selection button's read only checks the text is non-empty and drops it.
2. **Route.** Language is detected on the Mac with Apple NaturalLanguage (no network).
3. **Send.** The text goes in one `POST http://127.0.0.1:11434/api/chat` (streaming, `keep_alive 30m`, `num_ctx 4096`). `LocalEndpointPolicy` allows only plain-HTTP loopback hosts (`127.0.0.1`, `localhost`, `[::1]`, no user-info) for the base URL, for every request, and for every response URL. Redirects are refused. Cloud model tags (`:cloud`, `-cloud`, remote hosts) are refused before sending.
4. **Show.** The output is kept in memory only while the popup is open, together with the source text needed for ⇄/Retry. Close, Esc, a new ⌥T or quitting clears both.
5. **Copy.** The pasteboard is written only when Copy is clicked, and only with finished output.

## Stored on disk

| Where | Content |
|---|---|
| `~/Library/Preferences/local.chienhuynh.LocalTranslator.plist` | Settings only: model tag and endpoint override (when changed), selection-button switch (when changed), Settings window frame. Observed now: only `NSWindow Frame …Settings_window` |
| Login item | State kept by macOS (SMAppService) when the user turns it on |
| Nothing else | No caches, cookies, HTTP storage, saved application state, Application Support, history, keychain or database (checked 2026-09-28) |

Leftovers from earlier development (not written by the current build): the sandbox container from S05–S07 was deleted in S28 with user approval (macOS keeps only its metadata plist); one crash report `LocalTranslator-2026-09-28-102107.ips` from a unit-test host crash in S21 (stack trace; synthetic marker not found in it).

## Logs

All 16 `Logger` calls use subsystem `local.chienhuynh.LocalTranslator` and log only counts, milliseconds, direction codes (e.g. `EN → VI`), status labels and error categories — never selected text, output or Ollama error text (Ollama messages are shown in the popup only). No `print`/`NSLog`.

## Network and dependencies

- One network client: `URLSessionTransport` (ephemeral session: no cache, cookies or credential storage; redirects refused). No other networking API is used.
- Dependencies: Apple frameworks only (AppKit, SwiftUI, Foundation, ApplicationServices, Carbon.HIToolbox, CoreGraphics, NaturalLanguage, Observation, ServiceManagement, os). No Swift packages, no analytics, crash-reporting or update SDK, no cloud fallback path.

## Evidence (2026-09-28)

- Code review above (grep of network APIs, URLs, logging, storage, imports).
- Sockets: Release build idle — only `127.0.0.1 → 127.0.0.1:11434` (S27).
- Offline: Wi-Fi off 13:35:19–13:35:55, 6 translations completed (S27; airportd log).
- User marker check: the user selected “Zebra quartz marker 7431 is ready.” in TextEdit and pressed ⌥T (Release build, 13:56); the popup showed a Vietnamese translation. The phrase, its translation (“thạch anh”) and “zebra” were searched in the unified log (30 min), `~/.ollama/logs`, the app's preferences, the old container, `$TMPDIR`, `~/Library/Caches` and Ollama's Application Support: not found (only unrelated numeric IDs containing “7431”). The app logged only `Selection captured: 34 chars`.
- Marker search: the synthetic S22 fixture phrase “merchant settlement”, sent through the app's translation path today, was searched in the unified log (last 8 h), all 12 files in `~/.ollama/logs`, the crash report and the app's storage. Only match: the `log show` command line itself. Not found anywhere else.
- Tests: `PipelineIntegrationTests` assert every request is loopback; `LocalEndpointPolicyTests` cover look-alike hosts; `TranslationErrorTests` assert the log label never includes Ollama's message.

## Outside this app

- Ollama is a separate app: its update checks, model downloads and settings (e.g. debug logging via `OLLAMA_DEBUG`, which may log prompts) are not controlled by Local Translator. Other apps on the Mac can also use the same Ollama.
- macOS itself: the unified log keeps the app's metadata lines for a limited time.

## Not verified

- Behaviour under a future macOS or Ollama version.

## Live meeting translation (Feature 2, L07 audit)

Audio of the chosen meeting app only (Core Audio process tap, “System Audio Recording Only”), never the microphone (no usage string; refused by Hardened Runtime policy). Speech recognition on this Mac (Apple SpeechTranscriber, no Speech Recognition permission); translation through the same loopback-only Ollama client. RAM only: ≤ 30 s audio, ≤ 50 subtitle segments with translations, cleared on Stop/close/quit; no files; logs metadata only. Details: `LIVE-QA.md`.
