# Third-party components

Paper In's MIT license covers this repository's original code. It does not relicense third-party SDKs, runtimes or operating-system frameworks.

- `@openai/codex-sdk` and Codex: Apache-2.0; preserve their distributed license/notice files. `docs/notices/OpenAI-Codex-*` includes the upstream LICENSE and NOTICE from Codex tag `rust-v0.153.4`, matching the pinned runtime, for copying into the DMG.
- `@anthropic-ai/claude-agent-sdk` and its native Claude runtime: proprietary, subject to [Anthropic's legal agreements](https://code.claude.com/docs/en/legal-and-compliance). The package contains its own `LICENSE.md`. The distributed runtime is unmodified, including its authentication methods. Users authenticate directly with their own provider credentials; Paper In does not resell provider access. Account eligibility and provider terms still apply.
- Node.js 22.23.2: included in the Apple Silicon DMG from the official release archive, verified against a pinned SHA-256. Its complete `LICENSE`, including third-party notices, is included beside the runtime.
- Other npm dependencies retain the licenses included in their packages and recorded in `ai/package-lock.json`.
- macOS AppKit, SwiftUI, PDFKit, Vision, Security and system networking frameworks are Apple platform dependencies.

The app bundle copies installed worker dependencies with their distributed license files. Packaging preserves upstream runtime bytes and signatures; it signs Paper In's own code and the outer bundle. Notices are in `Contents/Resources/Notices`, dependency licenses in `Contents/Resources/Worker/node_modules`, and Node's license in `Contents/Resources/Runtime/LICENSE`.

No npm dependency or native AI runtime is committed to the source repository. Source builds use an installed Node; DMGs include Node. The native provider runtimes account for most of the download size. The dependencies do not imply endorsement by Apple, Brother, Anthropic or OpenAI.

Before updating a bundled runtime, recheck its license, redistribution conditions, authentication behavior and signing/notarization compatibility. Anthropic's current preinstallation conditions were checked on 6 September 2026; their terms can change.
