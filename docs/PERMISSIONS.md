# Accessibility permission — S08

Current app: **Undertone**, bundle ID `local.chienhuynh.Undertone` since 0.3.0 (a new identity for TCC: Accessibility and System Audio Recording must be granted again; the old ID's grants were reset). The historical verification below used the old name and ID. Live additionally needs System Audio Recording Only when Start is pressed.

Only Accessibility is required. Screen Recording and Input Monitoring are not requested.

## App identity (2026-09-27)

| Build | Path (repo-relative) | Bundle ID | Signing | Designated requirement |
|---|---|---|---|---|
| Xcode Run (stable path for manual checks) | `.build/DerivedData/LocalTranslator/Build/Products/Debug/LocalTranslator.app` | `local.chienhuynh.LocalTranslator` | ad-hoc, no Team | `cdhash H"2a218f09204d4962846b7a299f953b328b2a52dc"` |
| CLI `xcodebuild` (BUILD.md command B) | `.build/DerivedData/Build/Products/Debug/LocalTranslator.app` | same | ad-hoc, no Team | `cdhash H"281e7cf01b5b9966ebaf1c01bf73739e2cc45eda"` |

With ad-hoc signing the designated requirement is the cdhash, so TCC trusts one exact binary. Any rebuild that changes the binary, or the other build path, is a different identity even though System Settings shows the same name “LocalTranslator” with the switch ON. `security find-identity -v -p codesigning` reports 0 valid identities on this Mac, so a stable signing identity does not exist yet.

The System Settings page is “Privacy & Security › Accessibility” on older macOS and “Device Control and Data Access” on macOS 27. Deep link: `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.

## Sub-phases

- **S08a** — verify grant, revoke, re-enable and relaunch with the current ad-hoc identity, and demonstrate the identity mismatch. No code or signing change.
- **S08b** — approved: stable signing identity via the Xcode Personal Team so grants survive rebuilds.

## S08a procedure (user-performed; agent never toggles security settings)

1. Xcode build running (path above). Settings shows “Đã cấp quyền”.
2. Revoke: switch LocalTranslator OFF in System Settings, click the Settings window → expect “Chưa cấp quyền”.
3. Re-enable: switch ON, click the Settings window → expect “Đã cấp quyền”.
4. Relaunch same binary: Quit from the menu, then Xcode Product › Run Without Building (⌃⌘R) → Settings shows “Đã cấp quyền”.
5. Identity mismatch: Quit, launch the CLI build (`open .build/DerivedData/Build/Products/Debug/LocalTranslator.app` from the repo root) and open Settings → expected “Chưa cấp quyền” although the list shows LocalTranslator ON. Do not press Request Access in this build. Quit it afterwards.

## Results

| Check | Result | Evidence |
|---|---|---|
| 1 Granted state | PASS (S07) | User screenshot: “Đã cấp quyền”, LocalTranslator ON |
| 2 Revoke | PASS | User report |
| 3 Re-enable | PASS | User report |
| 4 Relaunch same binary | PASS | User report (Run Without Building) |
| 5 Identity mismatch | PASS (confirms limitation) | User report: CLI build shows “Chưa cấp quyền” while list shows ON |

## S08b stable signing

- `DEVELOPMENT_TEAM = 6T9Y4G54XN` (Personal Team, free provisioning) on app and test targets, Debug and Release; `CODE_SIGN_STYLE = Automatic` unchanged. The first build with `-allowProvisioningUpdates` let Xcode create an Apple Development certificate; later plain builds (BUILD.md command B) sign without the flag.
- New designated requirement (both build paths, Debug and Release): `identifier "local.chienhuynh.LocalTranslator" and anchor apple generic and certificate leaf[subject.CN] = "Apple Development: … (66UDT2CH5Q)" and certificate 1[…6.2.1] exists`. No cdhash → the grant should survive rebuilds and apply to both build paths.
- Entitlements: only `com.apple.security.get-task-allow`. `codesign --verify --strict`: valid, satisfies its DR.
- The old grant was for the ad-hoc cdhash, so the newly signed app needs one re-grant (remove the old entry with “−”, then Request Access / enable).
- Free-team certificates expire (typically after one year) and are not for distribution; release signing is S28/S30.

| S08b check | Result | Evidence |
|---|---|---|
| Re-grant for new signature | PASS | User report |
| Grant survives different binary (CLI path, same DR) | PASS | User report |
| Settings window comes to front from menu | PASS | User report |

## Rollback

S08b: remove the four `DEVELOPMENT_TEAM` lines (returns to ad-hoc signing; grants again tied to cdhash). The user switches LocalTranslator off or removes it with “−” in System Settings. Never run a global `tccutil reset`; if ever needed, only `tccutil reset Accessibility local.chienhuynh.LocalTranslator` with user approval.

## Live meeting audio (Feature 2, L02)

| Item | Value |
|---|---|
| Permission | “System Audio Recording Only” (TCC `kTCCServiceAudioCapture`), System Settings → Privacy & Security → Screen & System Audio Recording |
| Usage string | `NSAudioCaptureUsageDescription` in `Config/LocalTranslator-Info.plist` (merged into the generated Info.plist; `INFOPLIST_KEY_…` does not support this key) |
| When asked | First Live **Start** only — never at launch or for ⌥T. Observed: tccd `authValue=2` (allowed by the user) on the first Start, 2026-09-28 15:21:17 |
| Microphone | Never requested by the app. Creating the aggregate device makes Core Audio preflight `kTCCServiceMicrophone`; with Hardened Runtime and no `com.apple.security.device.audio-input` entitlement tccd refuses it by policy (“Prompting policy for hardened runtime”), so the app cannot use the microphone at all. Capture of the tapped app is unaffected (verified) |
| Revoke | Turning the permission off makes new taps deliver nothing; the Live window shows “The app is playing but no sound arrives…” once the source has played ≥ 4 s without a single audio block |

Speech recognition (L03): SpeechAnalyzer/SpeechTranscriber ran with `SFSpeechRecognizer.authorizationStatus() == notDetermined`; the app requests no Speech Recognition permission and declares no `NSSpeechRecognitionUsageDescription`.
