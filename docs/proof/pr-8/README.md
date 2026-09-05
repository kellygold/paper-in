# PR 8 validation evidence

Status: CURRENT for candidate `c56db47a97e77cca9729edba4fd08e604905e95c` (executable code `44f0f72e19e00866caac579123827f865c673aee`). The final candidate differs only in validation documentation.

- `regressions.json`: 91 offline checks and cleanup assertions.
- `live-native.json`: generated PDF → packaged native controller/worker → OCR → Codex → filing → Undo, with original hash preservation and cleanup.
- `ui-result.json`, `settings-model-preserved.png`: actual mounted settings view and independent native UI regression replay. Fixed-size harness screenshot proves the model field; it is not a full responsive layout audit.

No personal scans or credentials are included. Hardware capture, live API-key services and signed binary distribution were not exercised in this fix pass. The live synthetic OCR result has an imperfect issuer spelling; integration success does not establish universal OCR/naming accuracy.

Independent delta review timed out after270.4seconds without a verdict. The prior completed review consumed627.5seconds. This is not an approval; the remaining release decision is documented in the PR proof comment.
