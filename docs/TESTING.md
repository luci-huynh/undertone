# Testing — S26

0.3.0 (4): renamed to Undertone — bundle ID `local.chienhuynh.Undertone`, log subsystem `local.chienhuynh.Undertone`; entries below keep their historical names.

## How to run

All from the repo root (commands as in `docs/BUILD.md` / runbook §2).

| Suite | Command | Needs |
|---|---|---|
| Unit + integration (T) | `xcodebuild -project LocalTranslator.xcodeproj -scheme LocalTranslator -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/DerivedData test` | Nothing outside the Mac: no Ollama, no network, no TCC grant |
| Live Ollama | same + `TEST_RUNNER_LT_LIVE_OLLAMA=1` and `-only-testing:LocalTranslatorTests/OllamaLiveTests -only-testing:LocalTranslatorTests/OllamaLiveStreamTests -only-testing:LocalTranslatorTests/OllamaLiveCancelTests -only-testing:LocalTranslatorTests/TranslationQualityLiveTests` | Local Ollama at `127.0.0.1:11434` with `translategemma:12b` |
| Live translation (L04) | Live Ollama command above + `-only-testing:LocalTranslatorTests/LiveTranslationLiveTests` | Local Ollama + translategemma:12b |
| Live speech recognition (L03) | same + `TEST_RUNNER_LT_LIVE_ASR=1 TEST_RUNNER_LT_ASR_AUDIO=<dir with long-sample.aiff>` and `-only-testing:LocalTranslatorTests/LiveSpeechLiveTests` | macOS 26+, English speech model; synthetic `say` audio |
| Popup render review | same + `TEST_RUNNER_LT_RENDER_DIR=<dir>` and `-only-testing:LocalTranslatorTests/PopupRenderTests` | Writes light/dark PNGs of synthetic popups to `<dir>` for a person to look at |

Gated suites are reported as `skipped` in the normal run (5 suites: `OllamaLiveTests`, `OllamaLiveStreamTests`, `OllamaLiveCancelTests`, `TranslationQualityLiveTests`, `PopupRenderTests`); nothing core is skipped silently.

Result at S26: **239 tests in 42 suites passed**, three consecutive runs identical (`.build/logs/s26-repeat-{1,2,3}.log`).

Result at L08 (0.2.0): **320 tests in 58 suites passed**, three runs (`.build/logs/l08-repeat-{1,2}.log`, `l08-final-test.log`). Gated suites added for Feature 2: `LiveTranslationLiveTests` (`LT_LIVE_OLLAMA`), `LiveSpeechLiveTests` (`LT_LIVE_ASR` + `LT_ASR_AUDIO`), `LiveRenderTests` and `SettingsRenderTests` (`LT_RENDER_DIR`). Live Ollama at L08: all suites pass; the quality fixture missed “QA” once (the model expanded it; sampling), 15/15 on the rerun — the same flake was seen once at L02.

## Rules the suite follows

- Network: every Ollama call in unit tests goes through `MockTransport` (records requests, never opens a socket). `URLSessionTransport` is only constructed in the gated live suites and in `urlSessionTransportRefusesRedirects`, which calls the delegate directly. The pipeline tests assert every recorded request is loopback.
- TCC / Accessibility: `FakeTrust`, fake AX queries and `FakeSelectionCapturer`; no test reads real selections or prompts for permission.
- Storage: model settings use `MemoryModelSettings`; the only `UserDefaults` suite is `local.chienhuynh.LocalTranslator.tests` (one fixed plist, emptied by the test), never the app's own domain.
- Timing: watchdog, notice and trigger tests use real clocks with ≥ 3× margins (e.g. 30 ms gaps vs 150 ms stall limit); product limits are asserted as constants.
- Text: fixtures are synthetic; nothing from real users.
- LLM quality is never asserted by exact strings: the live fixture checks invariants only (direction, output language, kept names/numbers, line structure, no commentary, injection not obeyed).

## Coverage by area (SPEC-MAP)

| Area | PLAN | Main suites |
|---|---|---|
| Permission mapping | F02, §14 | `AccessibilityPermissionTests` (no prompt on refresh, prompt once, grant picked up), `SelectedTextServiceTests` (missing permission never queries AX), `everySelectionFailureHasADecidedPopup` (all 12 capture failures → message/none, Settings action only for permission) |
| Selection capture | F02, §12 | `SelectionClassifierTests`, `SelectedTextServiceTests`, `AXCaptureRegressionTests` (consistency re-read, cancellation), `AccessibilityTreeActivationTests` |
| Geometry | F03 | `ScreenGeometryTests`, `SelectionAnchorResolverTests`, `PopupPositionerTests`, `MovedPopupPositionTests`, `SelectionTriggerPlacementTests` (edges, second screen with negative coordinates) |
| Shortcut / trigger | F06, §1 | `GlobalShortcutTests`, `SelectionTriggerTests` (drag/double/triple click, one read per gesture, hide rules, disabled = no monitor) |
| Routing | F05 | `LanguageRouterTests` (clear EN/VI, unaccented, mixed, other languages, ambiguous, code/numbers, links incl. scheme-less, accents ≠ VI), `DirectionFlowTests` |
| Prompt / budget | F01, S22 | `TranslationPromptTests`, `TranslationModelConfigurationTests` |
| Endpoint policy / redirect | F01, F08 | `LocalEndpointPolicyTests` (loopback only; https, LAN, look-alike hosts, user-info, `127.1`, decimal IP, IPv4-mapped IPv6, scheme-less), `urlSessionTransportRefusesRedirects`, `responseFromAnotherHostIsRejected`, `foreignResponseURLIsRejected`, `redirectStatusIsAnErrorWithoutOutput`, `cloudModel…SendsNothing`, `nonLocalEndpoint…` |
| Parser | F04 | `OllamaStreamParserTests` (every byte boundary with Vietnamese, CRLF, missing final newline, premature EOF, error frame, malformed JSON, invalid UTF-8, thinking/tool payloads ignored) |
| Cancellation | F04 | `closingOrRetriggeringCancelsTheUnderlyingStream`, `consumerCancellationStopsTheStream`, `StreamWatchdogTests` (timeout cancels upstream), `TranslationTimeoutServiceTests`, `userCancellationIsNeverShownAsAnError` |
| Stale results | F04 | `newTriggerCancelsOldRequestAndOldOutputNeverAppears`, `olderInFlightCaptureCannotOverwriteNewerResult`, `switchingMidStreamRestartsAndOldDeltasNeverAppear`, `aReadFinishingAfterTheNextClickIsDropped`, `ShellTests` (request-ID guard) |
| Error recovery | §14 | `TranslationErrorTests` (15 mappings, retry table), `RecoveryFlowTests`, `ollamaDownThenRetryRecovers`, `missingModelEndToEndIsExplainedWithoutRetry` |
| Popup | F03 | `TranslationPanelControllerTests` (Esc hot key lifecycle, Copy only on request, measurement cache, moved popup), `PopupMetricsTests`, `PopupPhaseTests` |
| Whole pipeline | §10 | `PipelineIntegrationTests`: capture → real router → prompt/budget → client → parser → watchdog → coordinator → popup, with only network and AX faked |
| Menu / settings | F07 | `OllamaReadinessTests`, `LaunchAtLoginTests`, `ShellTests` |

## Known-failure fixtures

Cases that once failed in real use are kept as tests; they must fail if the fix is removed.

| Bug (step) | Test |
|---|---|
| Negative-size AX bounds accepted (S12) | `zeroOrGarbageBoundsFallBackToMouse` |
| Streaming renders reset scroll (S20a) | `oneRequestKeepsOneSessionAcrossRenders` |
| Scheme-less Slack link translated (S21a) | `schemelessLinksAreNotText`, `urlOnlySelectionNeverReachesOllama` |
| URLSession idle timeout shown as “Ollama is not running” (S23) | `urlSessionIdleTimeoutIsAStallNotAStoppedOllama` |
| ⇄ label truncated in the narrowest popup (S25a) | `languageNamesForPromptAndPopup` (short title) |

S26 re-run check: in a scratch copy of the repo (outside `.build`, repo untouched) the S21a fix and the endpoint user-info check were removed; `LanguageRouterTests`, `LocalEndpointPolicyTests` and `PipelineIntegrationTests` then failed with 7 issues (4 scheme-less links, `urlOnlySelectionNeverReachesOllama` ×2, user-info URL). The copy was deleted afterwards.

## Still manual

Tests passing do not show that every source app works. These stay manual (S27 and later): real apps and their AX behaviour (matrix in `COMPATIBILITY.md`), TCC grant/revoke, focus behaviour of the panels, VoiceOver, drag in the running app, multiple physical screens, translation quality (live fixture + human judgement), latency/CPU/RAM, offline run of the release binary.
