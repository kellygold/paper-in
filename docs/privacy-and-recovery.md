# Privacy and recovery

## What stays on your Mac

Scanner communication, draft storage, page edits, PDF generation, and OCR are local. The app does not use a Paper In server.

Drafts, retained originals, the filing queue, OCR cache, and diagnostics live under `~/Library/Application Support/Paper In`. The export destination is chosen in the app. These are separate from the source repository and are never part of a normal Git push.

API keys live in macOS Keychain and travel to the child worker over stdin, not command-line arguments or job manifests. Existing Claude/Codex authentication stays with the official provider runtime; Paper In does not extract login tokens.

## What AI receives

AI filing is off by default. When enabled, the selected provider receives extracted document text, folder names, and excerpts from up to eight ranked candidate PDFs. Original page images are not uploaded by this implementation. A photograph with no text therefore cannot be understood visually by the filing model.

The worker uses an isolated empty runtime directory per job and disables agent execution tools and external integrations. Provider retention depends on the chosen account and runtime. Codex may retain its own local session history. See [provider notes](providers.md).

The comparison is bounded: the library index reads up to 1,500 PDFs, lists up to 300 folders, hashes for exact duplicates, and selects up to eight candidates for text comparison. It is not a full semantic audit of every document. Truncated input and other uncertainty force review.

## Save, filing, and restart

With AI off, Save writes the PDF directly into the chosen folder. With AI on, Save writes into `_Inbox` and records the filing intent with the completed export. This record lets the next launch discover work even if the app quits immediately after Save.

Enabling AI does not opt previously exported PDFs into uploads. A draft that has not yet been exported uses the setting selected when you save it.

The queue retains its own original PDF before analysis. AI errors leave the original and inbox copy intact. Publication and Undo record their intended changes before modifying files so interrupted operations can resume. Existing files are not overwritten; name collisions receive a short ID suffix.

A filing or Undo failure does not block the other documents. In **Saved documents**, restore access to the original destination and use **Retry filing** to resume the same transaction. **Resume queue** also retries interrupted operations. Incomplete or unreadable records are reported or skipped while healthy records remain usable; original files are retained.

If filing succeeds but inbox cleanup fails, the document stays **Filed** with a warning. Restore access to the inbox and use **Retry inbox cleanup**. The app never follows an inbox symlink to delete a file.

Undo restores the retained original and removes a filed copy only if its bytes still match. If you changed the filed copy, it is preserved. Related documents are never automatically merged or deleted.

Completed draft pages, old drafts, and original PDFs are retained. There is no automatic cleanup yet. OS-level power-loss guarantees still depend on the filesystem; retained originals are the recovery fallback.
