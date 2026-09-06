# Development

## Requirements

- macOS 14+; Apple Silicon is the tested architecture.
- Xcode or Apple's Command Line Tools, including Swift, clang, and the macOS SDK.
- Node.js 22+ and npm.
- A Brother DS-940DW is needed only for physical scanner testing.

The build uses the selected SDK and host architecture. A narrowly scoped fallback handles the known Swift 6.1.2 / mismatched Command Line Tools installation. It creates a local compiler overlay under `.build`; it does not change system settings. `PAPER_IN_SDK` and `PAPER_IN_ARCH` override SDK and architecture selection.

## Everyday commands

Run from the repository root:

```sh
./build.sh                    # Compile and package .build/Paper In.app
./test.sh                     # Build and run all offline automated checks
open '.build/Paper In.app'    # Launch the built app
```

`build.sh` installs locked npm dependencies into `ai/node_modules` on the first build and when the lockfile changes. It does not install global CLIs. Both SDK runtimes and their license files are copied into the app bundle. Source builds use an installed Node for AI filing; the DMG packaging script also bundles Node. See [distribution](distribution.md) for DMGs and the static website.

The built app is ad-hoc signed for local development. Building does not quit or update an already installed app. Finish any scanning session before deliberately replacing or relaunching your installed copy.

## Tests

```sh
./scripts/test-native.sh     # Native suites only, after an initial build
(cd ai && npm test)          # AI queue/provider unit tests only
```

All default tests use generated fixtures, isolated temporary folders, and fake scanner/provider responses. They never send your documents to a provider or touch your real scanning session. `tests/app/Connection/LegacyScanner.swift` is a regression fixture for the earlier ImageCapture implementation; it is not compiled into the app.

The [validation page](validation.md) lists the scenarios and hardware boundaries. Opt-in live tests send a fictional invoice through your selected provider and may consume quota:

```sh
./scripts/live-test.sh codex
./scripts/live-test.sh claudeSDK
```

API variants require the matching environment key and `PAPER_IN_TEST_MODEL`; see the validation page. Never commit credentials. The native controller/Keychain harness in `tests/app/ControllerIntegration` is also opt-in; see `scripts/live-native-test.sh`.

## Inspect the screens without a scanner

```sh
open -n '.build/Paper In.app' --args --demo
open -n '.build/Paper In.app' --args --demo --demo-settings
open -n '.build/Paper In.app' --args --demo --demo-review
```

Demo mode uses generated pages and temporary storage and refuses AI requests. Add `--screenshot /absolute/path.png` to export a screenshot. The README preview is generated sample content, not a personal document.

## Formatting and dependencies

Swift follows `swift-format` defaults. JavaScript follows `.prettierrc.json`. Keep formatting changes separate from behavioral fixes where possible.

When changing a dependency, update both `ai/package.json` and `ai/package-lock.json`, run the full suite, and check the relevant SDK integration with a synthetic document. Do not commit `node_modules`, app bundles, `.build`, credentials, or personal scans.

## CI

GitHub Actions runs `./test.sh` on a macOS Apple Silicon runner using Node 22. It requires no repository secrets, scanner, or AI account. The workflow grants read-only repository access and does not publish an installer. A successful CI run establishes build and offline test results, not hardware compatibility or provider eligibility.
