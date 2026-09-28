# Changelog

## 0.3.0 (build 4) — 2026-09-28

- Renamed to **Undertone** (user decision): `Undertone.app`, bundle ID `local.chienhuynh.Undertone`, Swift module `Undertone`, log subsystem `local.chienhuynh.Undertone`, `Config/Undertone-Info.plist`; menu, messages and permission text say Undertone. Source folders and the Xcode project/target/scheme keep the internal name `LocalTranslator`.
- macOS treats it as a new app: Accessibility, System Audio Recording and Launch at Login must be granted again. Settings were copied from the old bundle ID on this Mac.
- No behaviour change otherwise.

## 0.2.1 (build 3) — 2026-09-28

- Live: the Vietnamese line is a muted slate blue (light and dark), standing out a little from the English while staying neutral.
- Live: the placeholder text could be drawn upside down on screen; it is no longer selectable text and the subtitle area always fills the window.
- Tests: two timing-sensitive text-flow tests made deterministic (test-only).
- Release: the 0.1.0 artifacts were removed at the user's request; 0.2.0 is kept for rollback.

## 0.2.0 (build 2) — 2026-09-28

Feature 2 (Live meeting translation) and the L08 full-code review, personal use (route A). Text translation keeps its behaviour except for the fixes below.

### Live meeting translation (macOS 26+; the app still runs on macOS 14 for text)
- Menu → Live Meeting Translation…: a window with the English subtitles and the Vietnamese translation of each sentence below them (PLAN §24.2 layout); newest at the bottom, it follows while scrolled to the bottom.
- Sources: Microsoft Teams, Google Chrome (Google Meet; every Chrome tab is captured) and Slack huddles. Only the chosen app's audio (Core Audio process tap, “System Audio Recording Only”), never the microphone.
- On-device English speech recognition (Apple SpeechTranscriber; model managed by macOS); EN → VI translation through the same local Ollama. ⌥T goes first: a running Live request is paused and resumed after it.
- Bounded: 30 s of audio, 50 sentences, at most 3 sentences waiting (more are merged), a sentence waiting over 30 s is skipped and marked. RAM only; Stop, closing the window or Quit clear everything; logs are metadata only.
- Statuses: starting / model download progress, listening, no sound, app not running (named), no audio arriving and refused capture (with an Open System Settings button), translation problems (with Open Ollama), errors.
- Recovers from output-device changes and wake; keep-on-top pin (default on), minimize, resize, remembered position; menu shows “Live: On — <app>”.

### Fixes from the L08 review
- Language detection could freeze the app for seconds (8 s for 1,500 characters without spaces) because of a backtracking e-mail pattern; the pattern is linear now and detection reads at most 2,000 characters.
- Popup: a new translation comes to the front of other floating windows (the Live window); without the global Esc key it takes keyboard focus once per request, not on every streaming render.
- Stream watchdog ignores time the Mac spends asleep; Ollama 4xx errors (e.g. a model that can't chat) no longer offer a Retry that fails the same way; a readiness timeout shows “Not responding” instead of “Unexpected response”.
- Selection capture: timeouts are reported as “The app didn't respond” instead of “focus/selection changed”; helper processes (e.g. a browser's web content process) are no longer taken for another app; the secure-input check fails closed; selection bounds are read last and capped.
- Live: the capture clock prefers an output-only device and only the tap's streams are read; audio processing moved off the Core Audio thread; a device event caused by our own restart no longer restarts again; a failed restart or a recognizer that stops ends the session visibly (subtitles stay readable); one recognizer per session; a sentence is closed 1 s after the audio stops; no final result dropped while busy; merged requests are judged by their newest sentence; per-session metrics reset; the waiting count updates live.

### UI
- Settings entirely in Vietnamese; one status style (symbol + colour) for Ollama, Accessibility and the shortcut; one “Kiểm tra lại” button; `ollama pull` shown in monospace; the recommended model marked; permission hints only when they apply; the ⌥T press counter only in Debug builds.
- Live window: Return starts but never stops (Stop no longer wipes the session by accident); the Chrome note sits under the picker; Vietnamese text in the primary colour (not the system accent); readable placeholder colours; title “Live Meeting Translation”.
- Popup: Copy shows ✓ after copying without shifting the other buttons; the selection button's glyph is larger.

Known limitations and rollback to 0.1.0: see README.

## 0.1.0 (build 1) — release candidate, 2026-09-28

First release candidate of Feature 1 (text translation), personal use (route A).

- Menu bar app: Ollama and model status, Settings, Open Ollama, Quit; optional Launch at Login.
- Accessibility permission flow with System Settings link; secure fields never read.
- Selected text from any app exposing Accessibility, with consistency checks, bounds and pointer fallback; Chromium/Electron accessibility activation.
- Global ⌥T and an optional translate button beside the pointer after a mouse selection.
- Floating non-activating popup: streaming, Copy, ⇄ direction switch, ↻ translate again, Retry, drag to move, Esc/Close, “Incomplete” label for partial output.
- Local translation through Ollama `translategemma:12b` (model-card prompt, `keep_alive 30m`, context 4096, loopback-only endpoint, cloud models refused).
- Automatic EN ↔ VI direction; other languages → Vietnamese; ambiguous text marked “(guessed)”; links/numbers only → “Nothing to translate.”
- Error handling: runtime/model/timeout/stall/malformed/interrupted/too-long/truncated, each with a short message and Retry where it helps.
- Privacy: no cloud, analytics, history or text in logs.
- Branding: app icon and menu bar icon (DESIGN01/DESIGN02, added separately by the user).
- Release build: Hardened Runtime on.

Known limitations: see README.
