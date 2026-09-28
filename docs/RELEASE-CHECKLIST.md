# Release checklists

## 0.3.0 (4) — renamed to Undertone

| Item | Value |
|---|---|
| Identity | `Undertone.app`, `local.chienhuynh.Undertone`, executable/module `Undertone`, Apple Development (Personal Team 6T9Y4G54XN), Hardened Runtime, no entitlements, `--verify --deep --strict` valid, no QA hook, no old bundle ID string in the binary |
| Archive | `.build/Undertone-0.3.0-4.xcarchive` |
| Zip | `.build/release/Undertone-0.3.0-4.zip`, 1,641,892 bytes (SHA-256 in `.build/release/SHA256SUMS`, all three lines OK) |
| Installed | `/Applications/Undertone.app`, identical to the archive, CDHash `5383104a…4e8d`; launched: ⌥T registered, Ollama connected, logs under the new subsystem |
| Tests | 320 tests in 58 suites pass |
| Old app removed | Every `LocalTranslator.app` copy deleted (`/Applications`, the moved 0.2.0 copy, DerivedData Release, QA build); `tccutil reset All local.chienhuynh.LocalTranslator` (that ID only); old settings domain copied to the new ID (5 keys, no text) then deleted. Kept for rollback: 0.2.0 and 0.2.1 zips/archives |
| User check | Grant Accessibility and System Audio Recording to Undertone; turn Launch at Login on again if wanted; check System Settings → Login Items for a leftover “LocalTranslator” entry; Live placeholder upright and Vietnamese colour |

## 0.2.1 (3) — L08 follow-up

| Item | Value |
|---|---|
| Changes | Vietnamese Live line colour; upside-down placeholder fix; two test-only fixes (CHANGELOG) |
| Archive | `.build/LocalTranslator-0.2.1-3.xcarchive` |
| Zip | `.build/release/LocalTranslator-0.2.1-3.zip`, 1,642,374 bytes, SHA-256 `37acfde2b34002bd7a75771cefe95b4a49c61370a045afbba92fbd393b9acc15` |
| Installed | `/Applications/LocalTranslator.app` 0.2.1 (3), identical to the archive, CDHash `adc77fd9…9360`; launched: ⌥T registered, Ollama connected |
| Signature | Apple Development (Personal Team 6T9Y4G54XN), Hardened Runtime, no entitlements, `--verify --deep --strict` valid, no QA hook |
| Tests | 320 tests in 58 suites pass |
| Rollback | 0.2.0 zip and archive (below); the replaced 0.2.0 copy moved to `/private/tmp/local-translator-l08-before/installed-0.2.0/` |
| Removed (user request, L08) | 0.1.0 zip, 0.1.0 archive and the moved 0.1.0 app copy; its `SHA256SUMS` line removed. 0.1.0 can be rebuilt from commit `3b3290d` |
| User check | Live placeholder upright and Vietnamese colour on screen (off-screen renders could not reproduce the upside-down text) |

## 0.2.0 (2) — text translation + Live meeting — L08

Route A (personal use). Not published, tagged, pushed or notarized. (The 0.1.0 artifact was kept at delivery and removed later at the user's request — see 0.2.1.)

### Handoff artifact

| Item | Value |
|---|---|
| Archive | `.build/LocalTranslator-0.2.0-2.xcarchive` (outside Git; the 0.1.0 archive `.build/LocalTranslator.xcarchive` is untouched) |
| Zip | `.build/release/LocalTranslator-0.2.0-2.zip`, 1,637,251 bytes |
| SHA-256 | `2faa0af03140b9843b21de68e61364c7d64e6818f870528d8a5f0786d5e6e376` (`.build/release/SHA256SUMS`, which also keeps the 0.1.0 line; `shasum -a 256 -c` OK for both) |
| Installed | `/Applications/LocalTranslator.app` 0.2.0 (2) — identical to the archive (`diff -rq`), CDHash `584004ec…ab25`; launched from `/Applications`: ⌥T registered, Ollama connected |
| Signature | Apple Development (Personal Team 6T9Y4G54XN), Hardened Runtime (`0x10000`), no entitlements; `codesign --verify --deep --strict` valid; zip round-trip identical and valid; universal (arm64 + x86_64); macOS 14.0+; `NSAudioCaptureUsageDescription` present; no QA hook in the binary (`strings`: 0 matches) |
| Replaced copy | 0.1.0 moved (not deleted) to `/private/tmp/local-translator-l08-before/installed-0.1.0/` (temporary folder; the durable rollback is the 0.1.0 zip) |

### PLAN §24.5 — Live Definition of Done

| # | Requirement | Status | Evidence |
|---|---|---|---|
| 1 | Source → Start → English and Vietnamese update in one window, nothing per sentence | PASS (automated + user on earlier builds); user check on 0.2.0 pending | L04/L07; L08 run on the new capture code: 10/10 sentences recognized and translated (`LIVE-QA.md`); user L03/L04 (Chrome video) |
| 2 | Subtitles never wait for translation; correct pairs; nothing from a stopped session; quality judged by the user | PASS | Tests (subtitles before translation, pairs/merge grouping, late results after Stop dropped, stale session cannot touch the next); user L04 “khá đúng” |
| 3 | Stop/close/quit stop capture and free the buffer; repeated Start/Stop, silence, long sentence, interruption, source loss, revoked permission, missing model, Ollama error → clear status | PASS (automated); hardware cases partly NOT RUN | Tests (teardown, restart failure ends the session, recognizer end, pause close, 200-char/12 s close); L06 real Ollama quit/restart; NOT RUN: output switch, sleep/wake, quit/reopen Teams (deferred by the user) |
| 4 | Offline after setup | PASS | User L07 (“Offline ổn”) |
| 5 | Code + network + storage/log audit: local only, no microphone, nothing stored | PASS | L07 audit (`PRIVACY.md`, `LIVE-QA.md`); L08 changes add no network, storage or text logging (reviewed) |
| 6 | Latency/backlog/CPU/RAM on this Mac, ≥ 30 min, within the L01 thresholds | PASS | L07 31 min (speech p50 9 ms / p95 26 ms, translation p50 1.9 s / p95 3.8 s, backlog 0, CPU 5.6 % avg); L08 75 s re-check: speech p50 4 ms / p95 975 ms, translation p50 1.5 s / p95 2.3 s, CPU ≤ 3.8 %, 25 MB |
| 7 | Text regression with Live off, running and just stopped; per-app limits; untested marked NOT RUN | PASS (automated); user check on 0.2.0 pending | 320 tests in 58 suites ×2; live Ollama suites (quality 15/15 on rerun), live speech suite; Teams + Chrome tested, **Slack huddle NOT RUN** |
| 8 | User accepts Feature 2 separately | **PENDING** | — |

### PLAN §20 — text DoD on 0.2.0

Automated regression PASS (unit suites, live Ollama, popup render). The user's check on the installed 0.2.0 build (Slack EN → VI streams → Copy, offline) is pending.

### For the user on the installed 0.2.0

- [ ] ⌥T EN → VI and VI → EN, Copy (shows ✓), ⇄, ↻, Esc; the selection button.
- [ ] Accessibility still granted after the upgrade (same signature); if not, Settings → Quyền Accessibility.
- [ ] Live with Teams or Chrome: Start → EN + VI; Return does not stop; Stop clears; pin, minimize; menu shows “Live: On — …”.
- [ ] Quit and relaunch; Launch at Login still on if it was.
- [ ] Optional: Safari selection (may work now; NOT RUN), Slack huddle, output switch, sleep/wake, quit/reopen Teams.
- [ ] The finished `l08-e2e.m4a` tab can be closed in Chrome (left open by the L08 run).

### Rollback

Quit the app; unzip `.build/release/LocalTranslator-0.2.0-2.zip` (to leave 0.2.1) and copy `LocalTranslator.app` to `/Applications` (README “Quay lại bản 0.2.0”). The 0.1.0 zip no longer exists. Models, Ollama, Accessibility permission and settings are not touched.

## 0.1.0 (1) — Feature 1 (text translation) — S31

Route A (personal use, S28). Not published, tagged, pushed or notarized.

### Handoff artifact

| Item | Value |
|---|---|
| Archive | `.build/LocalTranslator.xcarchive` (outside Git) |
| Zip | `.build/release/LocalTranslator-0.1.0-1.zip`, 1,352,550 bytes |
| SHA-256 | `6d7e2a0790d2c6d7b3b679454a113474ae71dc0a9125f2f298f1078d8c8b56d3` (`.build/release/SHA256SUMS`) |
| Installed | `/Applications/LocalTranslator.app` — identical to the archive (`diff -rq`, CDHash `a6862d40…e357`) |
| Signature | Apple Development (Personal Team 6T9Y4G54XN), Hardened Runtime, no entitlements; `codesign --verify --deep --strict` valid; Gatekeeper `spctl` rejected (not notarized; expected for route A); zip round-trip keeps a valid signature |
| Previous build (rollback) | `.build/DerivedData/Build/Products/Release/LocalTranslator.app` |

### Requirements vs evidence (SPEC-MAP)

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

### Known issues (carried into handoff)

- Safari: selected text not readable (S12; low priority, user).
- Chromium/Electron apps need a 10–30 s accessibility warm-up after launch; popup may anchor at the pointer.
- Selection button: mouse selections only; stays up to 4 s while typing (no keyboard monitor by design); dragging a window with an existing selection can show it.
- Length limit ~5,000 UTF-8 bytes; long text is slow (≈ 1 KB per 10–20 s).
- EN → VI output accurate but formal (model limit; user kept translategemma, S22 X).
- Popup font fixed at 14 pt; only Esc as popup shortcut (user K3).
- Not notarized: other Macs need a local build or a manual Gatekeeper override.
- Git: only the S01–S07 checkpoint is committed; S08 onward is uncommitted; the earlier push was refused for the signed-in GitHub account.

### Rollback

Quit the app, delete `/Applications/LocalTranslator.app`, and run the previous build from `.build/DerivedData/Build/Products/Release/` (or rebuild from source). Models, Ollama, Accessibility permission and settings are not touched by rollback.
