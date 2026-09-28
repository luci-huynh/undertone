# Build baseline — S04

Current product name: **Undertone** (`Undertone.app`, executable `Undertone`). Since 0.3.0 the bundle ID is `local.chienhuynh.Undertone` and the Swift module `Undertone`; project, target, scheme and source folders remain `LocalTranslator`; signing is unchanged. Commands below still use the same scheme. Old verification entries retain their historical names.

Run commands from `/Users/chien.huynh/MyProjects/local-translator` (the existing Git root).

## Project identity

- Project: `LocalTranslator.xcodeproj` (no separate workspace required).
- Target and shared scheme: `LocalTranslator`.
- Shared scheme: `LocalTranslator.xcodeproj/xcshareddata/xcschemes/LocalTranslator.xcscheme`.
- Bundle ID: `local.chienhuynh.LocalTranslator`.
- Version: `0.1.0` (build 1); deployment target: macOS 14.0.
- S01 observed Xcode 27.0 (27A266a); S02 observed host macOS 27.0 (26A428).
- S03 artifact used ad-hoc signing, with no Developer Team. Do not disable code signing to conceal build errors.

## Commands

Inspect project:

```sh
xcodebuild -list -project LocalTranslator.xcodeproj
```

Debug build (B):

```sh
xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData build
```

CLI product: `.build/DerivedData/Build/Products/Debug/Undertone.app`.
Xcode's per-user relative DerivedData setting from S03 can append `LocalTranslator/`, yielding `.build/DerivedData/LocalTranslator/Build/Products/Debug/Undertone.app`. That UI setting is ignored by Git; the CLI command above is the reproducible baseline.

If the execution sandbox blocks Xcode cache/log access, request permission to rerun outside the sandbox; do not change global Xcode paths or signing to work around it.

## Verification

- S04 Debug build (2026-09-27): PASS, exit 0, `BUILD SUCCEEDED`. Log: `.build/logs/S04-debug-build.log` (ignored by Git).
- Build warnings: multiple matching macOS destinations (Xcode selected the host arm64 destination); AppIntents metadata extraction skipped because this template has no AppIntents dependency. Neither prevented the build; no source compiler warnings were reported.
- Post-change `xcodebuild -list`: exit 0, target and scheme `LocalTranslator` discovered. Shared scheme XML references the existing target ID.
- Artifact inspection: minimum macOS 14.0, ad-hoc signing, bundle ID unchanged, no Team.
- Repo/ignore review: `.build/`, `.DS_Store`, and both Xcode `xcuserdata/` trees are ignored; shared scheme and source remain visible. No files are staged or tracked yet. `git diff --check` and `git diff --stat` are empty because all files are untracked; newly added text files are also reviewed directly.
- SHA-256 before/after checks confirm PLAN.md, CODEX_RUNBOOK.md, and both Swift source files were unchanged in S04.
- At S04: tests NOT RUN because no test target existed. S06 adds LocalTranslatorTests to the shared scheme; see results below.
- Release build: NOT RUN in S04.
- Runtime: S03 observed the template window displaying `Hello, world!`; not repeated in S04.
- S03 console reported `com.apple.linkd.autoShortcut` connection errors while the app remained running. Cause unverified.
- macOS 14 runtime and Accessibility/TCC behavior have not been verified.

## Git baseline

The repository already existed on branch `main`, with no commits and no tracked files at entry to S04. Do not run `git init` or create an automatic checkpoint.
`.gitignore` excludes `.build/`, `DerivedData/`, Xcode user state, and `.DS_Store`; shared schemes remain eligible for version control.
PLAN.md and CODEX_RUNBOOK.md were already at root and are preserved without copying or rewriting. The existing empty filename `README.md ` (trailing space) is left unchanged.

## S06 verification

Test command (T), from repo root:

```sh
xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test
```

2026-09-27: Debug build B exit 0, `BUILD SUCCEEDED`; T exit 0, `TEST SUCCEEDED`. Swift Testing ran **6 tests in 1 suite**, all passed. The XCTest wrapper also reports zero XCTest tests; this does not negate the separate six Swift Testing tests. Hosted test target: `LocalTranslatorTests`, macOS 14.0, existing app target dependency, unchanged app signing. No transport or AX implementation is linked from application source; tests use synthetic strings and a fake readiness service.

Logs: `.build/logs/S06-build.log`, `.build/logs/S06-test.log`. Runtime warnings about com.apple.linkd.autoShortcut also occurred at S03; no Swift compiler warnings found. UI acceptance is pending because the UI automation tool timed out on the windowless menu-bar app.

Manual binary: `.build/DerivedData/Build/Products/Debug/LocalTranslator.app`. Launch it, inspect the speech-bubble status menu, open/close/reopen Settings, then Quit using that menu. Confirm no template window or Dock icon. Do not treat build/tests as proof of these checks.

## S07 configuration change

App target `ENABLE_APP_SANDBOX = NO` (Debug and Release), approved by the user after a diagnostic build proved the sandbox blocked the Accessibility prompt. Entitlements now: `com.apple.security.files.user-selected.read-only`, `com.apple.security.get-task-allow` (no app-sandbox). Release build (R) exit 0 on 2026-09-27; log `.build/logs/S07-nosandbox-release.log`.

## S08b signing

App and test targets use `DEVELOPMENT_TEAM = 6T9Y4G54XN` (Xcode Personal Team) with automatic signing; builds are signed “Apple Development” instead of ad-hoc. If the certificate is missing on a machine, run command B once with `-allowProvisioningUpdates` (requires the Apple ID in Xcode › Settings › Accounts). Do not disable signing. 2026-09-27: B, T, R exit 0 (`.build/logs/S08b-*.log`).
