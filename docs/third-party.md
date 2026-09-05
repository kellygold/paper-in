# Third-party components

Paper In's MIT license covers this repository's original code. It does not relicense third-party SDKs, runtimes or operating-system frameworks.

- `@openai/codex-sdk` and Codex: Apache-2.0; preserve their distributed license/notice files.
- `@anthropic-ai/claude-agent-sdk` and its native Claude runtime: proprietary, subject to Anthropic's applicable legal agreements. The package contains its own `LICENSE.md`. Public binary redistribution and subscription access must be checked against those terms; the repository can be built with dependencies installed from their official packages.
- Other npm dependencies retain the licenses included in their packages and recorded in `Worker/package-lock.json`.
- macOS AppKit, SwiftUI, PDFKit, Vision, Security and system networking frameworks are Apple platform dependencies.

The app bundle currently copies installed worker dependencies, including their license files. No npm dependency or native AI runtime is committed to the source repository. Local builds are approximately 515 MB due to the two native AI runtimes; Node itself is not bundled.
