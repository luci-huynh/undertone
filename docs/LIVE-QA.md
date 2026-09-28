# Live QA — L07 (2026-09-28)

Target Mac: Apple M5, 24 GB, macOS 27.0, Xcode 27.0; Ollama 0.34.4 with `translategemma:12b`; English speech model: system SpeechTranscriber asset (en_US). Builds: Release (shipped config) and a local QA build (Release + `-D LIVE_QA_HOOK`, `.build/QA`) that starts Live at launch for unattended runs; the shipped binary has no hook (`strings` check).

## Meeting source matrix

| Source | Result | Evidence |
|---|---|---|
| Microsoft Teams (app, 26246) | PASS | User test call (L02): listening within ~1 s, 118 s session; user check of subtitles/translation (L03/L04 used Chrome) |
| Google Meet / any page in Chrome 153 | PASS | User (L03/L04: English video with subtitles + translation) and automated runs below |
| Slack huddles 4.52 | NOT RUN | User could not test; source rules follow the observed `com.tinyspeck.slackmacgap.helper` |
| Other apps (Zoom, Webex, FaceTime, Brave…) | Not supported | Not in the L01 scope |

## Long session (synthetic speech, 31 min)

Audio: 32.6 min of `say`-generated English meeting speech, repeating blocks of normal (180 wpm), fast (250), slow (140) speech, a 60-word monologue without pause and a 20 s silence; played in a Chrome tab, system output muted (the tap captures process audio before the volume; verified). QA build auto-start, 18:04:46 → 18:35:48. The user browsed (Brave YouTube) at the same time.

| Measure (threshold from L01) | Result | Verdict |
|---|---|---|
| Speech → English text on screen (p50 ≤ 1 s, p95 ≤ 2 s) | p50 9 ms, p95 26 ms (last 200 results); p95 up to 389 ms in 5-min windows | PASS |
| Segment final → Vietnamese complete (p50 ≤ 3 s, p95 ≤ 6 s) | p50 1.9 s, p95 3.8 s (stable over the run) | PASS |
| End of utterance → Vietnamese (p50 ≤ 5 s, p95 ≤ 9 s) | ≈ 2–4.5 s (sum of the two measured stages; not measured end-to-end directly) | PASS (estimate) |
| Backlog (≤ 3 waiting, nothing > 30 s) | 0 waiting at every 5 s sample; 0 merges; 0 skipped | PASS |
| Segments | 325 recognized and translated, 0 translation failures; kept in RAM: 50 | PASS |
| Silence gives no subtitles | status listening ↔ silent 25/26 times, matching the 24 silences; no segment during them | PASS |
| Long monologue | 23 segments closed at the 200-character limit (max 226 chars) — one per monologue block | PASS |
| App CPU (≤ 25 % of one core) | avg 5.6 %, max 19.7 % (64 samples) | PASS |
| App memory (≤ 400 MB, flat) | 25–26 MB for 21 min, then a step to 63–66 MB at ~18:26 (cause not identified; possibly the Live window being opened), flat afterwards | PASS (flat after the step; step unexplained) |
| Ollama llama-server CPU | avg 4.4 %, max 14 % | — |
| Duration ≥ 30 min without growth of queue/memory | 31 min | PASS |

A first attempt (17:28) is **invalid**: the Chrome tab stopped playing after ~15 s (tab closed or paused; Chrome itself played the same file continuously in a 60 s check afterwards), so only 1 segment was produced. It still showed 33 min of stable idle Live: CPU 2.7 %, memory flat at 38 MB.

## Scenarios

| Scenario | Result | Evidence |
|---|---|---|
| Fast / slow speech, monologue, silence | PASS | Long session above |
| Source quiet / source closed | PASS (quiet), source closed by tests + process restore | L02 status logic; `LiveSessionTests` |
| Ollama stopped and restarted during Live | PASS | L06 real run: segments show “Ollama is not running.”, recognition continues, translation resumes |
| ⌥T while Live translates | PASS | L06: first token 0.41–0.47 s with Live busy (was 4.1–4.2 s before preemption) |
| Output device change, sleep/wake | NOT RUN on hardware (deferred by the user); unit tests PASS | L06 |
| Accessibility / audio permission revoked | Audio: status “no sound arrives” (tests); text: S23 | — |
| **Offline** (Wi-Fi off, audio played on this Mac) | **PASS** (user, 2026-09-28: “Offline ổn”) | Plus design (on-device SpeechTranscriber, loopback Ollama) and socket evidence below |

## Privacy and scope audit

- Network: during the session the app's only sockets were `127.0.0.1 → 127.0.0.1:11434` (two Ollama connections: readiness + translation). Live code has no networking; translation reuses the Feature 1 loopback-only client.
- Capture scope: process tap on the chosen app's bundle IDs only (Chrome: `com.google.Chrome`, `.helper`); another process (`afplay`) and Brave were not captured (L02 isolation runs). Browser = all tabs of that browser (stated in the window footer).
- Microphone: no microphone code, no `NSMicrophoneUsageDescription`; Core Audio's microphone preflight is refused by the Hardened Runtime policy — the app cannot use the microphone.
- Storage: no files; UserDefaults holds only `LiveSource`, `LiveKeepsWindowOnTop` and window frames (one stale `NSWindow Frame live` from the L02 SwiftUI window). Audio (≤ 30 s), subtitles and translations (≤ 50 segments) live in RAM and are cleared on Stop/close/quit.
- Logs: 18 Live log calls, metadata only (counts, ms, dBFS, status, error categories); no transcript or translation text.

## Text regression (Feature 1)

298 unit/integration tests; live Ollama suites incl. the 15-case quality fixture (15/15 this run) and the Live contention test; ⌥T with Live off / running / just stopped, no cross-cancel (L06 tests).

## L08 re-check after the review fixes (75 s, Chrome)

The L08 review changed the capture path (clock device choice, tap streams only, processing off the IO thread) and the session logic, so a short end-to-end run repeated the L07 method on a QA build of the final code (Release + `-D LIVE_QA_HOOK`, Hardened Runtime): 43 s of `say` meeting speech (10 sentences with pauses) played in a Chrome tab, system output muted and restored afterwards; nothing else was playing audio.

| Measure | Result |
|---|---|
| Capture | 2 bundle IDs, 48 kHz mono; 6,632 IO callbacks, 0 without data |
| English subtitles | 10/10 sentences, each its own segment; speech → text p50 4 ms, p95 975 ms (138 results; the p95 is the end-of-sentence final, as in the L03 adapter test) |
| Vietnamese | 10/10 translated, 0 failures, 0 waiting; p50 1.5 s, p95 2.3 s |
| Silence | listening ↔ silent at every pause; no subtitle during silence |
| App CPU / memory | 2.2–3.8 % while listening, 25 MB |

## Open for the user's acceptance

Slack huddle; L06 hardware checks (output switch, sleep/wake, quit/reopen Teams, ⌥T during Live); a headset with a microphone as the only output device; unexplained memory step (flat, within limits).
