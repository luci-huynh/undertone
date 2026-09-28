# Release configuration — S28

## Undertone rename — 2026-09-28

New builds produce `Undertone.app`. Project/scheme/module, bundle ID, settings keys and signing stay unchanged. Existing LocalTranslator archives and installed copies are not renamed by a source build. For a later installation, quit the old app, keep a rollback copy and install Undertone as the only running copy. Recheck Accessibility, System Audio Recording Only and Launch at Login; the login item may need toggling off/on after the path changes. Earlier release records below describe their original artifacts.

## Current build (inspected 2026-09-28)

| Item | Value |
|---|---|
| Bundle ID / version | `local.chienhuynh.LocalTranslator`, 0.1.0 (1), macOS 14.0+, universal (arm64 + x86_64), `LSUIElement` menu-bar app |
| Signing | Automatic, Personal Team `6T9Y4G54XN`, Apple Development certificate; no provisioning profile embedded |
| App Sandbox | Off (`ENABLE_APP_SANDBOX = NO`, S07 user decision: the sandbox blocked the Accessibility prompt/registration) |
| Hardened Runtime | Off (`codesign` flags `0x0`) |
| Entitlements | `com.apple.security.get-task-allow = true` only (added by development signing). BUILD.md's S07 note also listed `files.user-selected.read-only`; the current build no longer has it |
| Permissions used | Accessibility (TCC), global mouse monitor (no keyboard monitor), Carbon hot keys, login item (optional) |
| Network | Loopback HTTP to Ollama only (see PRIVACY.md) |

## Distribution options

| Route | What it needs | Fit |
|---|---|---|
| **A. Personal use on this Mac** | Current signing; install the Release build (S29) e.g. into `/Applications` so the Accessibility grant and login item point at a stable path | Matches how the app is used now; no Apple account changes |
| B. Share outside the App Store (Developer ID + notarization) | Paid Apple Developer Program account (Developer ID Application certificate), Hardened Runtime on, `get-task-allow` off, notarization with the user's credentials | Needed only to give the app to other people; the Personal Team cannot notarize |
| C. Mac App Store | App Sandbox on + review; S07 showed the sandbox blocking the Accessibility flow, and current Apple rules for sandboxed Accessibility use must be checked in Apple's documentation before any attempt; no approval can be promised | Not recommended |

Recommendation: **A**, with one minimal change: turn on **Hardened Runtime** for Release (code-injection protection; needs no entitlement for Accessibility, Carbon hot keys, mouse monitors or loopback HTTP). It also makes a later move to B smaller. Not applied yet — waiting for the route decision; the Accessibility grant is expected to survive (same identifier and team) but must be rechecked after the change.

## Decision (user, 2026-09-28)

- Route **A** — personal use; the user may also build it on their other Macs (below).
- **Hardened Runtime on for Release** (`ENABLE_HARDENED_RUNTIME = YES`, app target Release only; Debug/tests unchanged). Verified: `codesign` flags `0x10000(runtime)`, `--verify --strict` valid, designated requirement unchanged (identifier + Apple Development leaf), so the Accessibility grant should carry over — user recheck pending. `get-task-allow` stays (development signing; harmless for A, removed by Developer ID signing if route B is ever chosen).
- Stale sandbox container deleted: all data inside removed; macOS keeps `.com.apple.containermanagerd.metadata.plist` and the folder itself (“Operation not permitted”); no app data in it.

## Using it on another Mac (route A)

Build from source on that Mac (recommended):

1. Install Xcode 27 or later and Ollama; run `ollama pull translategemma:12b` (8.1 GB) — the app never downloads models.
2. Get the source: copy the folder, or `git clone` the pushed repository. Feature 1 (commit `3b3290d`) is pushed to `luci/main`; Feature 2 (L01–L08) is not committed yet, so for 0.2.0 copy the folder until it is committed and pushed.
3. Open `LocalTranslator.xcodeproj` → target LocalTranslator → Signing & Capabilities → Team: the same Apple ID works as is (Xcode creates a development certificate for that Mac). With a different Apple ID, pick its Personal Team and, if Xcode reports the bundle ID is taken, change `PRODUCT_BUNDLE_IDENTIFIER` to a unique one.
4. Build Release (commands in `BUILD.md`) or Product → Archive, copy `LocalTranslator.app` to `/Applications`, open it, grant Accessibility when asked, optionally turn on Launch at Login.

Copying the built `.app` instead also works on a Mac the user controls, but it is not notarized: macOS Gatekeeper blocks the first launch of a downloaded/AirDropped copy until the user allows it (Finder → right-click → Open, or System Settings → Privacy & Security → Open Anyway), and Accessibility must still be granted there. Sharing with other people is route B.

## Release candidate 0.1.0 (1) — S29

- Version per PLAN §16: `MARKETING_VERSION 0.1.0`, `CURRENT_PROJECT_VERSION 1` (unchanged since S02).
- Artifact: `xcodebuild … -configuration Release -destination "generic/platform=macOS" -archivePath .build/LocalTranslator.xcarchive archive` → `.build/LocalTranslator.xcarchive` (outside Git). App: universal, 2.0 MB, macOS 14.0+, Apple Development signature, Hardened Runtime, **no entitlements** (archive signing drops `get-task-allow`), `codesign --verify --strict` valid.
- Installed: `ditto` into `/Applications/LocalTranslator.app` (stable path for Accessibility and the login item). Not uploaded, notarized, tagged or published.

### Checklist

- [x] Tests: 239 in 42 suites pass; Release build and archive succeed, no Swift warnings.
- [x] README (install, permission, Ollama/model, shortcut, troubleshooting, limits), CHANGELOG.
- [x] Archive signature, version and entitlements inspected.
- [x] Installed copy at `/Applications` launches; ⌥T registered; Ollama connected.
- [ ] User: Accessibility works for the `/Applications` copy; ⌥T EN → VI and VI → EN; Quit and relaunch; Launch at Login toggled off → on so it points at `/Applications` (it pointed at the `.build` Release path).
- [ ] User: remove the empty `README.md ` (trailing space, 0 bytes, from the S01 checkpoint) or keep it.

### Rollback

Quit the app and delete `/Applications/LocalTranslator.app`; the previous Release build remains in `.build/DerivedData/Build/Products/Release/`.

## S30 — N/A (route A)

`codesign --verify --deep --strict`: valid. `spctl --assess --type execute`: rejected (not notarized; expected). No stapled ticket. Signing identities: Apple Development only. Not distribution-ready; personal use only.

## Release 0.2.0 (2) — L08

- Version (user, L08: “0.2.0 đi”): `MARKETING_VERSION 0.2.0`, `CURRENT_PROJECT_VERSION 2` in both app configurations.
- Same route A signing: Apple Development, Personal Team `6T9Y4G54XN`, Hardened Runtime, no entitlements. New since 0.1.0: `Config/LocalTranslator-Info.plist` adds `NSAudioCaptureUsageDescription` (Live's System Audio Recording Only permission, asked at the first Start); there is no microphone usage string.
- Artifact: `.build/LocalTranslator-0.2.0-2.xcarchive` and `.build/release/LocalTranslator-0.2.0-2.zip` (SHA-256 in `.build/release/SHA256SUMS`); the 0.1.0 archive and zip are unchanged.
- Installed to `/Applications/LocalTranslator.app` with the user's approval (L08: “2. Có”); the 0.1.0 copy was moved, not deleted.
- Live on another Mac needs macOS 26 or later; macOS may download its English speech model once at the first Start; grant System Audio Recording Only there. Text translation does not need either.
- Checklist and evidence: `RELEASE-CHECKLIST.md` (0.2.0 section). Not uploaded, notarized, tagged, pushed or published.

## Release 0.2.1 (3) — L08 follow-up

- User: “Build bản mới, cài vào Applications, bỏ bản 0.1.0”. Version 0.2.1 (3); the name stays “Local Translator” (no new name chosen yet).
- Same signing and settings as 0.2.0. Artifact `.build/LocalTranslator-0.2.1-3.xcarchive`, `.build/release/LocalTranslator-0.2.1-3.zip`; installed to `/Applications`.
- 0.1.0 artifacts deleted; 0.2.0 kept for rollback. Details: `RELEASE-CHECKLIST.md`.

## Release 0.3.0 (4) — Undertone

- User: rename everything to Undertone including the bundle ID; “Version mới, và gỡ toàn bộ app tên cũ, install lại app mới”.
- Bundle ID `local.chienhuynh.Undertone` (tests `local.chienhuynh.UndertoneTests`), module `Undertone`, `Config/Undertone-Info.plist`. Same signing. The project, target, scheme and source folders keep the internal name `LocalTranslator`, so the build commands are unchanged except the archive path.
- A new bundle ID is a new app for macOS (permissions, login item). Details and rollback: `RELEASE-CHECKLIST.md`, README.
