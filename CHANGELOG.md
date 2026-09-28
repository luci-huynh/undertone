# Changelog

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
