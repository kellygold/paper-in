# Contributing

Paper In is early and intentionally small. Useful contributions include clearer errors, recovery fixes, accessible controls, tests, and verified scanner/provider adapters.

## Your first change

1. Read the [project map](project-map.md) and build with [development.md](development.md).
2. For a bug, describe the action, expected result, actual result, app/macOS version, and scanner model. Share redacted diagnostics if useful; do not post your scans or credentials.
3. For a new feature or a large architectural change, open an issue describing the problem and proposed user experience before starting a broad refactor.
4. Make one focused change and run `./test.sh`.
5. In the PR, describe the resulting behavior, the relevant tests, and anything you could not verify. Hardware support needs actual hardware evidence.

## Design rules

- A completed scan must reach durable storage before the UI counts it as saved.
- Keep scanning local and independent of AI availability.
- Provider adapters return structured suggestions. The shared filing engine owns validation and filesystem changes.
- Preserve original bytes, never overwrite an unrelated file, and retain recovery paths when work is interrupted.
- Keep user controls about their task. Put implementation details in diagnostics and contributor docs.
- Reuse the existing scanner/provider contracts. Avoid adding a new abstraction before it has a concrete use.
- Do not automatically merge related documents or silently rescan after uncertain delivery.

Read [architecture](architecture.md) before adding a scanner or provider. New model IDs supported by an existing adapter do not require a new provider implementation.

## Tests and privacy

Use generated fixtures. Default tests must run without hardware, credentials, network calls to AI services, or personal files. Live provider tests are opt-in and use fictional content.

Do not include API keys, OAuth material, personal PDFs, diagnostic logs containing private data, or machine-specific paths in commits or issue attachments. API keys belong in Keychain at runtime; test keys must be obviously synthetic.

## License

Contributions to Paper In's original code are under the repository's MIT license. Third-party dependencies retain their own terms; do not copy proprietary dependency source or binaries into the repository. See [third-party notices](third-party.md).
