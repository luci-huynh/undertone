# Release checklist — Feature 1 (text translation) 0.1.0 (1) — S31

Route A (personal use, S28). Not published, tagged, pushed or notarized.

## Handoff artifact

| Item | Value |
|---|---|
| Archive | `.build/LocalTranslator.xcarchive` (outside Git) |
| Zip | `.build/release/LocalTranslator-0.1.0-1.zip`, 1,352,550 bytes |
| SHA-256 | `6d7e2a0790d2c6d7b3b679454a113474ae71dc0a9125f2f298f1078d8c8b56d3` (`.build/release/SHA256SUMS`) |
| Installed | `/Applications/LocalTranslator.app` — identical to the archive (`diff -rq`, CDHash `a6862d40…e357`) |
| Signature | Apple Development (Personal Team 6T9Y4G54XN), Hardened Runtime, no entitlements; `codesign --verify --deep --strict` valid; Gatekeeper `spctl` rejected (not notarized; expected for route A); zip round-trip keeps a valid signature |
| Previous build (rollback) | `.build/DerivedData/Build/Products/Release/LocalTranslator.app` |

## Requirements vs evidence (SPEC-MAP)

| PLAN | Requirement | Status | Evidence |
|---|---|---|---|
| §1, §10 | Select → ⌥T → read; no browser/switch app | PASS | S14/S20, S27 user session (17 selections), S29 installed copy |
| §2 F01 | Local Ollama, configurable model, offline/model missing no crash | PASS | S18 readiness, S22 adapter; S31 installed copy: not running / model missing / non-local endpoint states; S27 offline |
| §3 F02 | Background menu bar app, AX selected text, no browser extension | PASS | S06–S12; app matrix S27 |
| §4 F03 | Floating popup near selection, no focus loss, Esc/Close/Copy, loading, resize/max/scroll | PASS | S13–S15, S20a/b, S25 render review, S25a drag |
| §5 F04 | Streaming, cancel previous | PASS | S19/S20, S23 watchdog, tests (TESTING.md) |
| §6 F05 | Local EN ↔ VI detection, no manual choice normally | PASS | S21 + user decisions (guess + ⇄, other → VI), S21a links |
| §7 F06 | Global ⌥T in background | PASS | S09, S27 (incl. rapid presses) |
| §8 F07 | Menu status, Settings, Open Ollama, Quit, Launch at Login | PASS | S18, S25 (login item), S29 re-registered for `/Applications` |
| §9 F08 | No cloud/analytics/history; metadata-only logs | PASS | S28 PRIVACY.md (code review, sockets, two marker searches), S27 offline |
| §12 | Bounds + fallback | PASS | S11/S12 (pointer fallback where apps give no bounds) |
| §14 | Permission, Ollama offline + Retry, model missing, nothing selected | PASS | S07/S08, S23 user checks, S31 fault launches |
| §15 | Shortcut → popup < 150 ms; request immediately; lightweight | PASS (measured) | S27: 14–81 ms (median 32) from the hot-key handler; idle CPU 0.03 %, 18 MB footprint; model held by Ollama |
| §16 | 0.1.0, 10 MVP items stable | PASS | This table; version 0.1.0 (1) |
| §17 | No out-of-scope features | PASS | No OCR, history, cloud, extension, analytics; S24 selection button approved by the user (PLAN §1 “small translate trigger”) |
| §19 | Unit tests + case list + manual app matrix | PASS | 239 tests in 42 suites (S26–S29); app matrix S27 |
| §20 | Slack EN → VI streams → Copy, also with Internet off | PASS | S27 user session (Slack in matrix, offline window 13:35:19–55 with 6 translations) |
| — | Clean install on another Mac / clean account | **NOT RUN** | Only this Mac; the other local (admin) account was not used. README/RELEASE.md describe setup on another Mac |
| — | Upgrade | N/A | PLAN defines no updater. Replacing the app in place kept settings and the Accessibility grant (S28 Hardened Runtime rebuild, S29 move to `/Applications`) |

## Known issues (carried into handoff)

- Safari: selected text not readable (S12; low priority, user).
- Chromium/Electron apps need a 10–30 s accessibility warm-up after launch; popup may anchor at the pointer.
- Selection button: mouse selections only; stays up to 4 s while typing (no keyboard monitor by design); dragging a window with an existing selection can show it.
- Length limit ~5,000 UTF-8 bytes; long text is slow (≈ 1 KB per 10–20 s).
- EN → VI output accurate but formal (model limit; user kept translategemma, S22 X).
- Popup font fixed at 14 pt; only Esc as popup shortcut (user K3).
- Not notarized: other Macs need a local build or a manual Gatekeeper override.
- Git: only the S01–S07 checkpoint is committed; S08 onward is uncommitted; the earlier push was refused for the signed-in GitHub account.

## Rollback

Quit the app, delete `/Applications/LocalTranslator.app`, and run the previous build from `.build/DerivedData/Build/Products/Release/` (or rebuild from source). Models, Ollama, Accessibility permission and settings are not touched by rollback.
