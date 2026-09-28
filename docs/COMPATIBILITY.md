# Compatibility and fallback — S11

## Spec reading

PLAN §12 says a fallback strategy must exist because apps expose Accessibility differently. It lists `NSPasteboard` among the APIs, but PLAN only uses the pasteboard for the popup's **Copy** button (§3 F03, §9). PLAN does not require reading the selection through the clipboard (synthetic ⌘C). SPEC-MAP: S11 = text fallback policy, S12 = bounds → mouse fallback; clipboard fallback only after explicit approval (runbook rule 6).

Decision in S11 (2026-09-27, user chose option A): **clipboard fallback N/A** (not required, not implemented). Text fallback = clear unsupported UX. Selection is read only through AX (`kAXSelectedTextAttribute`), as implemented in S10.

## Text fallback policy

| Capture result (S10 `SelectionFailure`) | Planned popup behaviour (S14/S23) | Text read? |
|---|---|---|
| `noSelection` | PLAN §14: “No text selected.” small popup, auto-dismiss | — |
| `permissionMissing` | PLAN §14: “Local Translator needs Accessibility permission to read selected text.” + [Open System Settings] | No |
| `unsupported`, `noFocusedElement` | “Can't read selected text in this app.” small popup, auto-dismiss | No |
| `secureInput` | “Secure input is on. Selected text isn't read.” small popup, auto-dismiss | Never |
| `timedOut` | “The app didn't respond. Try again.” small popup, auto-dismiss | No |
| `axError(code)` | Same as `unsupported`; code only in metadata log | No |
| `focusChanged` | Dropped silently (user already moved on) | Discarded |
| `selectionChanged` (S12a) | “The selection changed. Try again.” small popup, auto-dismiss | Discarded |
| `cancelled` (S12a) | Dropped silently (a newer ⌥T replaced it) | Discarded |
| `sourceIsSelf`, `noFrontmostApp` | Ignored (no popup) | — |

Translation failures (S20–S23, normalised in `TranslationError`), shown in the popup with any partial output labelled “Incomplete”:

| Cause | Message | Action |
|---|---|---|
| Ollama not answering / quit mid-stream | PLAN §14 “Ollama is not running.” | Retry |
| Model not installed | PLAN §14 “Translation model is not installed.” | — (no download) |
| No first token within 60 s | “The model took too long to start.” | Retry |
| No new output for 15 s | “Ollama stopped responding.” | Retry |
| Response not in Ollama's format | “Ollama sent an unexpected response.” | Retry |
| Stream ended early / cancelled by the system | “The translation was interrupted.” | Retry |
| Ollama error (e.g. memory) | “Ollama: <first line of its message>” | Retry |
| Empty output | “No translation returned.” | Retry |
| Selection over the context budget (not sent) | “Selected text is too long to translate at once.” | — |
| Context window filled while streaming | “Translation stopped early: the text is too long.” | — |
| Non-local endpoint or cloud model (not sent) | “Only a local Ollama and local models are allowed. Check Settings.” | — |
| Selection has no words (URL, e-mail, numbers; S21) | “Nothing to translate.” notice, auto-dismiss | — |
| Anything else | “Translation failed.” | Retry |

Close, a new ⌥T, ⇄ and Retry cancel the running request silently; they are never shown as errors.

Wording for the non-PLAN rows is an assumption (low-impact detail, runbook rule 6). It is confirmed or adjusted when the popup is built (S14) and the error states (S23). No retry loop, no clipboard, no automatic enabling of app-specific accessibility modes.

## Known limits (not verified per app yet)

| Source | Expected via AX | Status |
|---|---|---|
| TextEdit (EN/VI, multi-line, emoji) | Supported | PASS (S10, user) |
| Browser page text (S10 browser, not Chrome) | Supported in the browser tested | PASS (S10, user; which browser not recorded) |
| Google Chrome (default settings) | Focused element not exposed: `kAXFocusedUIElementAttribute` → `noFocusedElement` | OBSERVED (S12, user, 7–24 ms, no text, no anchor). Likely cause: Chrome builds its native accessibility tree only when it detects an assistive client (unverified) |
| Google Chrome with `chrome://accessibility` native + web accessibility ticked | Text read; anchor fell back to cursor (orange) | PASS text (S12, user): confirms the missing-tree diagnosis. Bounds not obtained; cause not investigated |
| Google Chrome 153.0.8010.53, default settings, with S12b auto-activation | `AXUIElementSetAttributeValue(app, AXManualAccessibility, true)` → -25205 attributeUnsupported; every later ⌥T still `noFocusedElement` | FAIL (S12b, user): Chrome does not build its tree from this attribute |
| Password fields / secure input | Never read | PASS (S10, user) |
| VS Code 1.139.1 (Electron) | `AXManualAccessibility` activation (S12b) | PASS text (S12b, user, after relaunching Local Translator) |
| Safari | Reported not working in S12 checks (details not given) | FAIL (S12, user); low priority per user |
| Google Chrome with S12c `AXEnhancedUserInterface` fallback | Text read after the tree is built; anchor = cursor (no usable range bounds) | PASS text (S12c, user); ~30 s from first ⌥T until capture works — warm-up once per Chrome launch |
| Slack, Notion (Electron) | `AXManualAccessibility` (S12b) | PASS text (user, after S12): first ⌥T triggers activation, works after ~10 s |
| Brave (Chromium) | `AXEnhancedUserInterface` fallback (S12c) | PASS text (user, after S12): same ~10 s warm-up |
| Outlook | Native | NOT VERIFIED — S27 |
| Other Chromium/Electron apps (Slack, Discord…) | Same mechanism | NOT VERIFIED — S27 |
| PDF in Preview | Usually supported | NOT VERIFIED — S27 |
| Terminal, iTerm | Varies | NOT VERIFIED — S27 |
| Java/Qt/custom-drawn apps, games, remote desktop | Often unsupported | NOT VERIFIED — S27 |

The app does not promise support for every app. Unsupported sources get the message above, not a silent failure.

## Options not taken (need explicit approval)

1. **Opt-in clipboard fallback** (synthetic ⌘C). If approved, a separate sub-phase must: be off by default, run only from ⌥T, skip when secure input is on, snapshot every pasteboard item/type and `changeCount`, restore only if `changeCount` is still the one written by the fallback, never overwrite a newer user/app copy, handle timeout and apps that refuse copy, and log no content. Risks: other clipboard managers record the text; restoring all types is not guaranteed (lazy/promised data); some apps ignore synthetic events. Manual checks: clipboard holding text and image, user copying during fallback, timeout, app refusing copy.
2. ~~Enable Chromium/Electron accessibility~~ — **adopted in S12b** (user chose option B): only `AXManualAccessibility`, only after a no-focused-element answer, once per process per launch, then up to 4 × 50 ms re-reads. The app keeps its tree (extra CPU/RAM in that app) until it quits. `AXEnhancedUserInterface` is not used: it is known to disturb window animation and window managers. **S12c** (user chose option C after Chrome 153 refused `AXManualAccessibility` with -25205): for known Chromium browser bundle IDs only, `AXEnhancedUserInterface = true` is tried next; never sent to other apps. Stays on in that browser until it quits.

## Rollback

Docs only. Delete `docs/COMPATIBILITY.md` and restore `docs/PROGRESS.md` from `/private/tmp/local-translator-s11-before/docs/`.

## Selection button (S24)

The button appears only where ⌥T can read the selection, because it uses the same capture: not in secure fields, not in apps listed above as FAIL (Safari), and in Chromium/Electron apps only after their accessibility warm-up. Mouse selections only; keyboard selections use ⌥T.

## S27 (Release build, macOS 27.0)

Per-app summary PASS for TextEdit, Notes, Mail, Preview (text PDF), Chrome, Brave, Slack, Notion, VS Code, Outlook 16.113.2, Word 16.113.2 (user summary, not itemised); Safari not re-tested (S12 FAIL); Pages and Acrobat not installed → NOT RUN. Details and timings: `QA-REPORT.md`.

