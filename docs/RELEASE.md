# Release configuration — S28

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
2. Get the source: copy the folder, or `git clone` once the work is committed and pushed (today only the S01–S07 checkpoint is committed; everything after it is uncommitted, and the last push attempt was refused for the signed-in GitHub account).
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

