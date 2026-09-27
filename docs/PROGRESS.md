# Operator progress

PLAN.md is the product spec. Step results and permission to advance are separate.

| ID | Status | Evidence | Pending manual checks | User approval |
|---|---|---|---|---|
| S01 | PASS | Spec read; Xcode 27.0; user confirmed Xcode visible | None | User replied “Có thấy rồi”, then “Ok” to the S02 request |
| S02 | PASS | Configuration proposed: SwiftUI macOS App, macOS 14.0, local.chienhuynh.LocalTranslator, existing repo root | None | User replied “Tiếp tục đi” to the configuration and S03 request |
| S03 | PASS | Xcode template created; UI Build Succeeded; running Hello, world! window observed; artifact identity verified | None for shell acceptance | User replied “ok tiếp tục” to the S04 request |
| S04 | PASS | Existing repo confirmed; shared scheme added; Debug build and project listing exit 0; ignored paths and untracked file list reviewed; spec/source hashes unchanged | None for S04 | User replied “ok tiếp” to the S05 request |
| S05 | PASS | ARCHITECTURE.md and SPEC-MAP.md cover design, requirement mapping and decision gates; static flow review completed | None for design review | User replied “ok tiếp tục di” to the design and S06 request |
| S06 | PASS | Debug build exit 0; Swift Testing 6 tests passed (rechecked in resumed session); no network/AX implementation; `UIElement` launch with 0 windows; user screenshots show status menu and Settings; user reported Settings reopen and Quit OK | None for S06 | User reported “mở lại được, quit ok”, then “Ok làm s07” to the S07 request |
| S07 | PASS | AX trust service + Settings UI; sandbox identified as blocker and disabled with user approval; review fixes applied; B/T/R exit 0, 12 tests passed. User screenshots: not-granted UI, deep link to macOS 27 “Device Control and Data Access”, single request, and after the user enabled LocalTranslator the Settings shows “Đã cấp quyền” with hints hidden | None for S07. Not explicitly reported: that the real-app system dialog appeared (registration evident from list entry) and no-prompt-on-launch for the final build | User sent final screenshots; completion approval and S08 authorization not yet given |

S08 and later: NOT RUN, not authorized. Stop after S07 and wait for fresh confirmation.

S04 verification on 2026-09-27: see BUILD.md and ignored `.build/logs/S04-debug-build.log`. Build produced only destination-selection and skipped AppIntents metadata warnings. No tests exist yet; tests and Release build NOT RUN. S03 runtime evidence is historical, not a new S04 runtime test.

## S04 scope and rollback

New files: `.gitignore`, shared `LocalTranslator.xcscheme`, `docs/BUILD.md`, `docs/PROGRESS.md`. Added operator rules to the previously empty AGENTS.md. No source or product-spec changes; no staging, commit, push, or repository initialization.

To roll back after approval, remove only these S04 additions and restore AGENTS.md to its prior empty content, preserving any subsequent user edits. Keep the existing `.git`, S03 project/source, and user data intact.

## S05 scope and validation

Added docs/ARCHITECTURE.md and docs/SPEC-MAP.md; updated this progress record with actual S04 approval and S05 results. Static review covers focus-before-snapshot, immutable request context, stale callbacks, cancellation/cleanup, error/partial output, bounds fallback, all PLAN sections and conditional runbook steps. Design recommendations are pending user approval; no future implementation is authorized.

Build/tests: NOT RUN per S05 because no project/source changes. S04 build remains historical evidence only. Git diff checks plus direct review of untracked documents and before/after hashes verify scope. No commit/staging/push.

Rollback: remove only the two S05 documents and revert the S05 edits to this file, preserving S04 records and any later user edits.

## S06 shell and test seam

- Replaced template WindowGroup with MenuBarExtra + Settings; LSUIElement=YES in Debug/Release. ContentView is now the Settings shell. Sandbox/signing/bundle identity unchanged.
- AppDelegate owns AppCoordinator and calls shutdown on termination. RuntimeReadinessProviding is injected; UnconfiguredReadinessService is inert and reports not checked. The test fake reports unavailable without I/O.
- TranslationStateMachine implements only synchronous lifecycle transitions and request identity; it is not an AX/shortcut/network/popup pipeline. Interfaces for those adapters will be introduced with their implementing steps, avoiding unused scaffolding.
- Menu/settings show unchecked readiness/model/permission honestly. Open Ollama is disabled until S18; no fake Connected, active translation shortcut, AX prompt, persistence or login item registration.
- Added LocalTranslatorTests with a hosted Swift Testing target in the shared scheme. Six tests verify valid completion/terminal-state guards, stale requests, cancellation/dismissal, partial failure/retry, empty output, injected status/shutdown.
- Commands B and T from BUILD.md both exit 0. Logs: `.build/logs/S06-build.log`, `.build/logs/S06-test.log`. Test log explicitly reports 6 tests in 1 suite passed, not merely an empty XCTest suite.
- No Swift compiler warnings observed. Existing destination-selection and skipped AppIntents metadata warnings remain; test host emits the previously observed com.apple.linkd.autoShortcut service errors without failing tests.
- UI tool launched the CLI product but selecting its no-window/menu-bar surface timed out twice. App inventory reported LocalTranslator running, but Settings/Quit/no-Dock acceptance has NOT been observed. Stopped the old S03 debug process in Xcode to avoid confusing it with the new shell.

Manual check to finish S06: launch the S06 binary listed in BUILD.md, click the character/speech-bubble menu bar icon, confirm unchecked Ollama/model labels, open Settings, close/reopen Settings, verify no Hello-world window or Dock icon, then choose Quit Local Translator and confirm the status icon disappears. Open Ollama being disabled is intentional at this stage.

Rollback: restore the two existing Swift files, project.pbxproj, shared scheme and documentation edits from the S06 before-state; remove only the newly added AppCoordinator.swift, TranslationStateMachine.swift and LocalTranslatorTests/ShellTests.swift after approval. A local before-state copy is at `/private/tmp/local-translator-s06-before` (temporary, not a durable Git checkpoint). Never reset the whole repo; preserve S01–S05 work.

### S06 recheck — resumed session, 2026-09-27

- Previous session ended mid-S06. Re-read PLAN.md, AGENTS.md, runbook S06 and this file; reviewed all S06 Swift sources/tests and project settings (LSUIElement=YES, macOS 14.0, bundle ID unchanged, sandbox unchanged). No source changes in the recheck.
- I: `git status --short` unchanged (all untracked); `git diff --check` exit 0.
- B: exit 0, `BUILD SUCCEEDED`, no Swift compiler warnings. Log: `.build/logs/S06-recheck-build.log`.
- T: exit 0, `TEST SUCCEEDED`; Swift Testing "6 tests in 1 suite passed". Known com.apple.linkd.autoShortcut console errors recur. Log: `.build/logs/S06-recheck-test.log`.
- Runtime (automated, no UI control): stopped the stale instance started by the earlier session (PID 65300, pre-rebuild binary) and relaunched the fresh Debug build (PID 74472). `lsappinfo` reports `type="UIElement"`, bundle `local.chienhuynh.LocalTranslator` → no Dock icon. CGWindowList shows the process owns 0 windows at launch → no template window.
- NOT OBSERVED: status icon visibility, menu contents, Settings open/close/reopen, Quit. System Events timed out (-1712); terminal lacks UI-scripting permission. These remain manual checks; S06 stays BLOCKED until the user reports them.
- Later: user ran the app from Xcode (PID 76959, Xcode DerivedData path) and reported no visible window, which is expected for a menu-bar app. Stopped the CLI-launched instance (PID 74472) so only the Xcode instance remains. Status icon visibility still awaits user confirmation.
- User screenshot (Xcode instance): status icon visible in menu bar; menu shows "Local Translator", "Ollama: Chưa kiểm tra", "Model: Chưa chọn", "Settings… ⌘,", disabled "Open Ollama", "Quit Local Translator ⌘Q". Check 1 OBSERVED. Still pending: Settings open/close/reopen, Quit removes icon.
- User screenshot: Settings window opens ("LocalTranslator Settings"), shows Ollama "Chưa kiểm tra", Model "Chưa chọn", Accessibility "Chưa kiểm tra" and both notes. Settings open OBSERVED. Still pending: close/reopen, Quit. Cosmetic note: window title uses bundle name "LocalTranslator" (no space); left unchanged, candidate for S25 polish.
- User reported “mở lại được, quit ok”: Settings close/reopen and Quit OBSERVED by user. No LocalTranslator process remains after Quit (pgrep). S06 marked PASS. S07 NOT RUN, awaiting explicit authorization.

## S07 Accessibility permission state

- Added `LocalTranslator/AccessibilityPermissionService.swift`: `AccessibilityTrustChecking` (live: `AXIsProcessTrusted`, and `AXIsProcessTrustedWithOptions` with the prompt option only for an explicit request), `SystemSettingsOpening` (live: opens `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`), state enum `notChecked / granted / notGranted`, and an `@Observable` service.
- macOS exposes no separate "denied" state; denied and never-granted both map to `notGranted`. Service tracks whether a prompt was already requested this launch and then hides Request Access, leaving Open System Settings and Refresh. No persistence.
- Refresh (no prompt) on launch, on app activation and when Settings appears, plus a manual Refresh button. No polling timer.
- AppCoordinator now receives the permission service by injection; AppDelegate wires the live implementations. Settings shows an Accessibility section with the PLAN §14 message “Local Translator needs Accessibility permission to read selected text.” and [Open System Settings]. Menu unchanged.
- Not implemented (later steps): selected-text reading, shortcut, Screen Recording/Input Monitoring. Initial S07 pass left sandbox, entitlements, signing and bundle ID unchanged and did not edit pbxproj (synchronized groups pick up new files); the later sandbox change below does edit pbxproj.
- Tests: added `LocalTranslatorTests/AccessibilityPermissionTests.swift` (6 tests with fake trust/opener: unchecked start without query, mapping + revoke without prompt, single prompt per launch, no prompt when trusted, grant after prompt, settings opener). ShellTests updated for the new initializer.
- B exit 0 (`.build/logs/S07-build.log`); T exit 0, “12 tests in 2 suites passed” (`.build/logs/S07-test.log`). Known com.apple.linkd.autoShortcut console errors recur.
- NOT OBSERVED: real TCC state of the built app, Settings rendering, System Settings deep link, system prompt behaviour. Requires user manual check. Real grant/revoke verification belongs to S08.

Rollback: remove `AccessibilityPermissionService.swift`, `AccessibilityPermissionTests.swift` and `TestSupport.swift`; restore `project.pbxproj`, `AppCoordinator.swift`, `LocalTranslatorApp.swift`, `ContentView.swift`, `ShellTests.swift` and the S07 edits to this file/ARCHITECTURE.md from `/private/tmp/local-translator-s07-before` (temporary copy, not a Git checkpoint). Do not reset TCC.
- User screenshots (Xcode run): Settings shows “Chưa cấp quyền”, PLAN §14 message, after-request hint and Open System Settings/Refresh (Request Access already hidden → request was made this launch). Open System Settings landed on macOS 27 “Device Control and Data Access” page listing existing AX-trusted apps. OBSERVED: state label, explanation, deep link, single-request hiding.
- Observed gap: LocalTranslator is NOT listed on that page after the request. Whether the system dialog appeared is not yet reported. Possible causes (unverified): prompt dismissed without registering, or App Sandbox/macOS 27 behaviour. Real grant path is S08 scope; noted as a risk for S08/S10 sandbox gate.
- In-step fix: hint text now names both “Privacy & Security › Accessibility” and the newer “Device Control and Data Access” page and the listed app name “LocalTranslator”; merged the after-request hint into one line; Settings frame 480×560 so the top section is not scrolled away. Rebuilt: B exit 0, T exit 0, 12 tests passed.
- User report: pressing Request Access shows no system dialog; only the in-app hint changes. LocalTranslator does not appear in the Accessibility list. Settings layout after the fix OBSERVED OK (screenshot).
- Diagnostics: running Xcode build is ad-hoc signed, bundle `local.chienhuynh.LocalTranslator`, entitlements `app-sandbox=true`, `files.user-selected.read-only`, `get-task-allow`. `log show` for tccd/app returned no matching entries from this shell (unified log likely filtered/redacted); cause NOT proven.
- Leading hypothesis (unverified): App Sandbox prevents the AX trust prompt and registration, and would also block reading other apps via AX in S10. Changing sandbox is an ARCHITECTURE decision gate → awaiting user decision; no project change made.
- User chose diagnostic option A. Built `.build/diag/Build/Products/Debug/LocalTranslatorDiag.app` via command-line overrides only (`ENABLE_APP_SANDBOX=NO`, bundle `local.chienhuynh.LocalTranslator.diag`, product `LocalTranslatorDiag`); exit 0; entitlements no longer contain app-sandbox. Project files unchanged. Stopped the Xcode-run instance and launched the diag app for the user test.
- User screenshot of diag app: system dialog “\"LocalTranslatorDiag\" would like to control this Mac and access your data.” with Open System Settings / Deny appeared on Request Access. Hypothesis CONFIRMED: App Sandbox blocked the Accessibility prompt/registration.
- User decision: “Hiện rồi triển khai no sandbox đi”. Changed `ENABLE_APP_SANDBOX` YES→NO for the app target, Debug and Release (project.pbxproj, 2 lines). Test target unchanged. `ENABLE_USER_SELECTED_FILES = readonly` left as is (inert without sandbox).
- Rebuilt: B exit 0 (`.build/logs/S07-nosandbox-build.log`), no Swift warnings; T exit 0, 12 tests in 2 suites passed (`S07-nosandbox-test.log`); R exit 0 (`S07-nosandbox-release.log`). Debug and Release entitlements: no app-sandbox; `files.user-selected.read-only`, `get-task-allow` remain. Release carrying get-task-allow is pre-existing ad-hoc signing behaviour; review at S28/S30.
- Consequence: not Mac App Store distributable; distribution route to be decided at S28 (e.g. Developer ID + notarization at S30).
- Cleanup: stopped the diag app and deleted `.build/diag`. Any “LocalTranslatorDiag” entry in the Accessibility list must be removed by the user (TCC not reset by agent).
- Rollback of the sandbox change: set `ENABLE_APP_SANDBOX = YES` on both app-target configurations.

### S07 review fixes (user approved “OK làm đi” after /code-review)

- #1 Settings adds a stale-grant hint: ad-hoc signing changes the code signature on rebuild, so an existing TCC entry may show ON while `AXIsProcessTrusted` is false; hint tells the user to remove/re-add or toggle LocalTranslator. Root fix (stable signing identity) deferred to S08 discussion.
- #2 Settings view refreshes on `NSWindow.didBecomeKeyNotification` so reopening an existing Settings window or returning from System Settings updates the state.
- #8 Removed `applicationDidBecomeActive` refresh; refresh triggers are now launch (AppDelegate) plus the Settings view (onAppear, window key, Refresh button). First open can still call the cheap trust check twice (appear + key); kept deliberately for correctness.
- #7 `NSApplication.shared.activate(ignoringOtherApps:)` → `NSApp.activate()` (macOS 14 API).
- #3 FakeTrust no longer grants on prompt (matches real API); replaced the unrealistic test with “grant in System Settings after request is picked up by refresh”.
- #10 Moved FakeTrust/FakeSettingsOpener/`fake()` to `LocalTranslatorTests/TestSupport.swift`.
- #6 Removed `ENABLE_USER_SELECTED_FILES = readonly` from the app target (Debug, Release).
- #4/#5 Fixed ARCHITECTURE.md sandbox statements and the contradictory PROGRESS note. #9 (duplicate “Chưa kiểm tra” label) intentionally not changed.
- Settings frame 480×620 for the extra hint row.
- Checks: B exit 0 (`S07-review-build.log`, no Swift warnings); T exit 0, 12 tests in 2 suites passed (`S07-review-test.log`); R exit 0 (`S07-review-release.log`). Entitlements after plain B and R: only `com.apple.security.get-task-allow`. The test action temporarily re-signs the Debug host with `temporary-exception.*` entitlements; a subsequent plain build removes them (verified).
- Still pending (manual, real app): Request Access shows the system dialog for “LocalTranslator” once; app appears in the Accessibility list; no prompt on launch; new hint rows render.

- Final user screenshots: LocalTranslator listed and enabled in Device Control and Data Access; Settings shows “Trạng thái: Đã cấp quyền”, guidance and buttons hidden. Grant → state transition OBSERVED. The grant was done by the user (belongs to S08 formally); revoke, relaunch and grant stability across rebuilds (ad-hoc signing) remain S08 checks. S07 marked PASS.

## Checkpoint after S07

User authorized (“Init git này vào, tạo branch main, push code lên”) adding remote `git@github.com:chienhuynh-dev/local-ai-translator.git`, committing S01–S07 on `main` and pushing. Existing repo reused (no `git init`). This is not approval to start S08.
