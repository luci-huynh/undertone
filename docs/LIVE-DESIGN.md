# Live meeting translation — L01 design

Scope: PLAN §24 (Feature 2). L01 is survey and design only: no code, no model download, no audio permission request. Everything marked *proposed* waits for the user's decision; *unverified* items are checked in the step named.

## 1. Environment (2026-09-28)

| Item | Value |
|---|---|
| Mac | Apple M5, 24 GB, macOS 27.0 (26A428), Xcode 27.0, SDK MacOSX27.0 |
| Translation | Ollama 0.34.4, `translategemma:12b` (Feature 1), ~15–16 tok/s warm |
| Meeting apps installed | Microsoft Teams 26246 (`com.microsoft.teams2`), Slack 4.52 (huddles), FaceTime 36, Telegram 12.10; browsers Chrome 153 / Brave 153 (Google Meet etc.). Zoom, Webex, Discord not installed |
| Text app | Feature 1 accepted; app minimum macOS 14.0 (unchanged) |

## 2. Capture options (evidence: SDK headers + sources)

| | A. Core Audio process tap (**proposed**) | B. ScreenCaptureKit audio |
|---|---|---|
| API | `CATapDescription` + `AudioHardwareCreateProcessTap` (SDK: macOS 14.2; sample code requires 14.4), aggregate device with the tap, IO proc | `SCStream` with `capturesAudio`, `SCContentFilter(display:including applications:)` (macOS 13) |
| Scope | Chosen processes only (`processes`; macOS 26: `bundleIDs`, `processRestoreEnabled` to re-attach when the app restarts) | Chosen applications, but through a screen-capture stream |
| Permission | “System Audio Recording Only” (`NSAudioCaptureUsageDescription`), audio only, prompt on first start | Screen Recording (screen + audio) — broader than needed |
| Mic | Not captured (taps process output) | Not captured unless `captureMicrophone` (macOS 15) |
| Fit | Narrowest permission, audio only | Heavier, broader permission |

Observed on this Mac (Core Audio process list, read-only): browsers and Slack play audio from **helper processes** (`com.google.Chrome.helper`, `com.brave.Browser.helper`, `com.tinyspeck.slackmacgap.helper`), not the main app. So “capture app X” = tap X and its helper bundle IDs.

Limits (to state in the UI and docs):
- A browser is one source: **all tabs** of that browser are captured (tab-level isolation is not possible with process taps).
- The meeting's own output is captured (remote speakers). The user's own voice is not, unless the meeting app plays it back. Echo already in the app's output cannot be removed.
- Teams (new app) and FaceTime audio processes are **unverified** (not running during the survey; FaceTime may play through a system daemon) → L02 checks each chosen app with a real call or test audio.

## 3. Local speech recognition (ASR) options

| | A. Apple SpeechAnalyzer + SpeechTranscriber (**proposed**) | B. WhisperKit (Argmax) | C. whisper.cpp |
|---|---|---|---|
| Runs | On-device, Apple framework (SDK: `@available(anyAppleOS 26)`) | On-device, Core ML | On-device, Metal |
| Streaming | `SpeechTranscriber` preset `progressiveTranscription` (volatile → final results, `fastResults`, `audioTimeRange`) | Chunked streaming | Chunked; more integration |
| Languages | English: `en_US` and 8 other `en_*` supported on this Mac (probe); **no Vietnamese** (not needed for EN → VI) | Multilingual incl. Vietnamese | Multilingual |
| Model | System asset via `AssetInventory`; en asset status on this Mac: `supported` = **not yet downloaded**; size unverified | 40 MB – 1.5 GB from Hugging Face, stored by the app | ggml files 75 MB – 1.6 GB |
| Dependency / license | None (Apple SDK) | Swift package, MIT; Whisper weights MIT | C/C++, MIT |
| Permission | **Unverified** whether Speech Recognition authorization is required (sources disagree; SDK comments silent) → L03 | None | None |

Proposed: **A**, no new dependency, system-managed model, live partial results. If L03 shows accuracy/latency below the agreed thresholds, fall back to B (needs the user's approval for the dependency and model download).

Consequence: Live needs **macOS 26+** at run time (SpeechAnalyzer, tap by bundle ID). The app's minimum stays **14.0**; on older macOS the Live menu item is disabled with a short reason. Feature 1 is unaffected.

## 4. Pipeline (proposed)

```
Start (source chosen) → process tap → 16 kHz mono float ring buffer (≤ 30 s)
   → SpeechAnalyzer/SpeechTranscriber (progressive)
        volatile text → EN line updates immediately (never waits for translation)
        final result  → segment (id, session id, time range, text)
   → translation queue (one request at a time) → Ollama translategemma EN → VI
   → VI line for the same segment id; results for an old session/segment are dropped
Stop / close / quit → stop tap + analyzer, cancel requests, clear buffers and segments
```

- Segmenting: use SpeechTranscriber final results (utterance/sentence level); force-close a segment after 12 s or ~200 characters without a final result. Silence produces no segments (no subtitle when silent).
- Translation unit: one finalized segment per request, reusing Feature 1's client, budget and prompt adapter; each request has its own cancellation.
- Backlog: at most **3** segments waiting. When a 4th arrives, the waiting ones are merged into one request (within the context budget). If the oldest waiting segment is more than 30 s old, it is marked “not translated (behind)” instead of queueing forever.
- Display memory: last **30** segment pairs in RAM; older ones dropped. No transcript/audio/translation is written to disk or logs; logs stay metadata-only.
- Coexistence with Feature 1: separate session, window and queue. While a ⌥T request runs, Live does not start a new translation request (text first); Live continues capture/ASR. Start/Stop Live never touches the text popup, and ⌥T never resets Live. Measured at L06.
- Direction: EN → VI only (PLAN §24.1; user confirmed no VI → EN for Live).

## 5. Acceptance thresholds (proposed, provisional until L03/L04 measurements)

Measured basis: translategemma warm first text 0.15–0.43 s and done 2.6–3.7 s for ~200 characters (S27); ASR latency not measured yet (model not downloaded).

| Measure | Proposed threshold | Confirmed at |
|---|---|---|
| Speech → EN partial text on screen | p50 ≤ 1.0 s, p95 ≤ 2.0 s | L03 |
| Segment final → VI translation complete | p50 ≤ 3 s, p95 ≤ 6 s | L04 |
| End of utterance → VI complete (end-to-end) | p50 ≤ 5 s, p95 ≤ 9 s | L04/L07 |
| Backlog | never > 3 waiting; nothing waits > 30 s | L04/L07 |
| Resources (app + ASR, excluding Ollama) | CPU ≤ 25 % of one core average while speaking; RAM ≤ 400 MB and flat over 30 min | L07 |
| Session | 30 min continuous without growth in queue or memory | L07 |
| Quality | EN transcript and VI translation judged acceptable by the user on synthetic test audio (macOS `say`) and allowed recordings | L03/L04/L08 |

## 6. Test audio

Synthetic English speech generated locally with `say -o` (no real meeting content), played from a local player or browser tab while that app is the chosen source. Real meetings are tested only by the user.

## 7. Decisions (user, 2026-09-28)

| # | Decision |
|---|---|
| 1 | Sources, first: **Microsoft Teams** app, **Google Meet in Chrome**, **Slack huddles** (FaceTime, Telegram, Brave not in scope yet) |
| 2 | Capture **A**: Core Audio process tap (“System Audio Recording Only”) |
| 3 | ASR **A**: Apple SpeechAnalyzer / SpeechTranscriber; system model download at L03 with approval |
| 4 | Live requires **macOS 26+**; app minimum stays 14.0 |
| 5 | Thresholds in §5 **accepted as proposed** (provisional values confirmed by measurement at L03/L04) |
| — | Direction **EN → VI only**; no VI → EN for Live |

Chrome note: choosing Chrome captures every Chrome tab (helper processes are shared), so other audio playing in Chrome during a meeting is also transcribed.

### Options that were presented

1. Main meeting sources to support first (Teams app, Google Meet in Chrome/Brave, Slack huddles, FaceTime, Telegram…).
2. Capture: A (process tap, audio-only permission) or B (ScreenCaptureKit).
3. ASR: A (Apple SpeechAnalyzer, macOS 26+, system model download at L03) or B/C (Whisper, dependency + model download).
4. Live available only on macOS 26+ while the app stays 14.0+: yes/no.
5. Thresholds in §5 (accept, or change numbers).

## Not verified in L01

Teams/FaceTime audio process identity; whether SpeechAnalyzer needs Speech Recognition authorization; ASR model size, latency and accuracy; process-tap behaviour when a meeting app restarts or changes output device; CPU/RAM of ASR + Ollama together.

## Sources

- SDK MacOSX27.0: `CoreAudio/AudioHardwareTapping.h`, `CoreAudio/CATapDescription.h`, `ScreenCaptureKit/SCStream.h`, `Speech.swiftmodule` (arm64e-apple-macos.swiftinterface).
- Local probes (read-only): SpeechTranscriber availability/locales/asset status; Core Audio process object list.
- [Apple: Capturing system audio with Core Audio taps](https://developer.apple.com/documentation/CoreAudio/capturing-system-audio-with-core-audio-taps) (page content not retrievable as text; referenced via the sample below).
- [insidegui/AudioCap](https://github.com/insidegui/AudioCap) (BSD-2-Clause sample: tap → aggregate device → IO proc; `NSAudioCaptureUsageDescription`; macOS 14.4).
- [Capturing System Audio on macOS in 2026 (DGR Labs)](https://dgrlabs.co/blog/2026-04-25-capturing-system-audio-on-macos-in-2026.html) and [SystemAudioKit](https://github.com/pieralukasz/SystemAudioKit) (taps vs ScreenCaptureKit, “System Audio Recording Only”).

## L02 findings (2026-09-28)

- Implemented as designed: private process tap on bundle IDs with process restore, mono mixdown, private aggregate device clocked by the default output (MacBook Pro Speakers, no input), IO block → 30 s ring buffer + level meter.
- A tap delivers IO callbacks **only while a tapped process outputs audio**; with the source quiet there are no callbacks at all. Status logic uses this: “blocked” = source reported playing ≥ 4 s with no block since.
- Isolation evidence (Debug and Hardened Runtime QA builds, synthetic audio): a non-selected process (`afplay`) playing for 7 s → peak −999 dBFS, 0 s buffered; the same kind of clip in Chrome → “listening”, peak −12 dBFS, 9 s buffered; 1,207–1,215 callbacks / ~618,000 frames per 28 s run, 0 empty callbacks.
- Chrome's audio came from `com.google.Chrome.helper` (matched by the source rules).
- Teams (user test call, 2026-09-28): captured, 3 bundle IDs tapped (app + helpers found at Start), listening within ~1 s, peak −12…−20 dBFS over 118 s. Slack huddle: NOT RUN (user could not test); the source rules follow the observed `com.tinyspeck.slackmacgap.helper` process.

## L03 findings (2026-09-28)

- Model: `SpeechTranscriber` en_US asset status `supported` → `installed` after `AssetInventory.assetInstallationRequest(...).downloadAndInstall()` in **0.0 s**; `/System/Library/AssetsV2/com_apple_MobileAsset_UAF_Speech_AutomaticSpeechRecognition` stayed at 349 MB (asset already on this Mac, shared with system dictation). The app also reserves the locale (`AssetInventory.reserve`). On a Mac without the asset the first Start downloads it once with progress shown; no cloud fallback.
- Authorization: `SFSpeechRecognizer.authorizationStatus()` was `notDetermined` and SpeechAnalyzer still transcribed — **no Speech Recognition permission is needed** (resolves the L01 open point). No usage string added.
- Pipeline: tap 48 kHz mono → `AnalyzerFeed` (AVAudioConverter to the analyzer's best format, 16 kHz mono; up to 1 s of silence inserted when the source pauses so sentence breaks survive; bounded input stream `bufferingNewest(256)`) → `SpeechAnalyzer` + `SpeechTranscriber(.progressiveTranscription)` → volatile/final events → `LiveTranscript` (≤ 30 segments with IDs, volatile line). Monologues without a pause are finalized after 12 s or 200 characters. Stop: `cancelAndFinishNow()`, results of the stopped session dropped.
- Latency definition: time from capture of the audio at a result's end (`result.range.end` mapped back to the capture wall clock) to the result's arrival.
- Measured (synthetic `say` speech, meeting-like real-time feed): adapter test p50 3 ms, p95 940 ms (84 results); end-to-end tap from Chrome in the Hardened Runtime QA build p50 3 ms, p95 704 ms (134 results) — within the L01 thresholds (p50 ≤ 1 s, p95 ≤ 2 s). App CPU while recognizing 4.9 % average / 7.4 % max, footprint 26 MB (RSS 81 MB). Recognition itself runs in a system process, not counted here.
- Accuracy on the synthetic meeting text: all six sentences correct except “bugs” → “bogs” and the Vietnamese name “Minh” → “men”. 5 s of silence → no text.
- Not verified yet: accented/real meeting speech, interruptions (overlapping speakers), offline run (SpeechTranscriber is an on-device API; confirmed by the user at L07).

## L04 findings (2026-09-28)

- `LiveTranslationQueue`: finalized segments only (never partials), one Ollama request at a time through the Feature 1 `OllamaTranslationService` (same prompt adapter, budget, watchdog, keep-alive, loopback policy), EN → VI only. ≤ 3 waiting; a 4th merges the waiting ones into one request (oldest first, within the context budget; the Vietnamese shows under the last segment of the group, the others are marked merged); anything waiting > 30 s is marked “Not translated — Live fell behind”. While a ⌥T request is loading/streaming, no new Live request starts (polled every 200 ms). Stop/reset cancels the running request (HTTP cancelled through the stream) and drops late deltas via a generation counter. States are pruned with the bounded transcript.
- SpeechTranscriber finals do not change afterwards; recognizer corrections happen only in volatile text, which is never translated, so there is nothing to retranslate.
- Real Ollama (synthetic meeting sentences, 2 s apart): 6/6 translated in order, meaning preserved (“Chào buổi sáng, mọi người.” … “Có ai có câu hỏi nào trước khi chúng ta chuyển sang phần tiếp theo không?”); segment final → Vietnamese complete p50 2.0 s, p95 2.2 s.
- End-to-end in the Hardened Runtime QA build (Chrome → tap → ASR → Ollama): 6/6 segments translated, waiting ≤ 1, none merged/skipped; translation p50 2.2 s, p95 2.6 s; ASR p95 0.85 s → end-of-utterance → Vietnamese ≈ 3.5 s at p95 (sum of the two measured stages). CPU: app 4.1 % avg / 5.7 % max, footprint 26 MB; llama-server 4.9 % avg / 19.4 % max; recognition runs in `corespeechd`.
- Thresholds (L01): translation p50 ≤ 3 s / p95 ≤ 6 s ✔; end-to-end p50 ≤ 5 s / p95 ≤ 9 s ✔ (estimate); backlog ≤ 3 ✔.
- Not verified yet: offline run (L07), a fast talker overflowing the queue in a real meeting, ⌥T during a busy Live session with a real model (priority rule covered by tests only).

## L05 findings (2026-09-28)

- Window: `LiveWindowController` — `NSPanel` (titled, closable, resizable, non-activating, utility), floating level, `fullScreenAuxiliary` + `moveToActiveSpace` (appears over a full-screen meeting on the current Space), frame autosaved as `LiveWindow` (reset to centre if saved off-screen), “Live…” calls `orderFrontRegardless()` without activating the app. Closing it stops the session. Replaces the L02 SwiftUI `Window`.
- Layout per PLAN §24.2: header “● LIVE” + status (+ “n waiting to translate”) + source picker (locked while running) + Start/Stop; body EN over VI per pair (`LivePairs`: merged segments form one pair with one translation), states Translating… / Waiting to translate… / Not translated — Live fell behind / error; the English still being recognized is the last line, lighter, without VI; auto-follows the newest line unless the reader scrolled up (shared `BottomFollowTracker`); footer with level and the privacy/Chrome note. 16 pt, line spacing 3 (stacked Vietnamese marks).
- Kept in RAM: 50 segments (user decision, was 30).
- Render review (light/dark, synthetic pairs incl. long Vietnamese): matches the mockup; no clipping.

### L05a (user feedback, 2026-09-28)

- Follow-to-bottom did not resume: `LazyVStack` re-measured content height while scrolling, and the tracker ignores height changes → replaced by a plain `VStack` (≤ 50 pairs) and a 24 pt “at the bottom” tolerance for Live (popup keeps 4 pt).
- Clicking the body did not focus the window and resize only worked after a title-bar click; no minimize; always on top → the Live window is now a normal `NSWindow` (titled, closable, **miniaturizable**, resizable; focus and resize on any click; no drag-to-move on the body), still shown with `orderFrontRegardless()` so opening it never takes focus from the meeting app. A pin button in the header toggles **Keep on top** (default on, stored as `LiveKeepsWindowOnTop`): on = floating level + full-screen auxiliary, off = normal level. “Live…” also restores a minimized window. Status moved to its own header row (was truncated).

## L06 findings (2026-09-28)

- Contention measured (translategemma:12b, Ollama 0.34.4, this Mac serves one request at a time): a text request alone first token 0.15–0.24 s; started 0.3 s into a Live request it waited **4.1–4.2 s** (first token) / 5.3–5.4 s (done). Fix (simplest): a starting ⌥T request **preempts** the running Live request — the Live stream is cancelled (Ollama stops it), the unit goes back to the front of the queue and is translated again after the text request. Measured after the fix (real Ollama, 3 rounds): text first token **0.44–0.46 s** (includes the model-metadata check), every preempted Live segment finished afterwards; those segments took ~6 s instead of ~2 s.
- Recovery: the capture is rebuilt (tap + aggregate device) after a default/system output change, a device list change or wake from sleep; bursts restart once (300 ms debounce); recognition, subtitles and queue are kept; a failed rebuild shows its error. Not exercised on real hardware here (only one output device connected; no sleep) → user check.
- Ollama quit during a Live run (QA build, synthetic audio): 2 segments showed “Ollama is not running.”, recognition continued; after Ollama restarted the following segments translated (first one ~6.6 s, model reload).
- Unchanged from L02/L03: permission revoked → “no sound arrives” status; source app closed → “The chosen app isn't running”, process restore re-attaches when it starts again; model missing → Live fails with its message, ⌥T unaffected (tests).
