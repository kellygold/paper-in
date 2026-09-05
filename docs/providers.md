# AI provider setup

Choose a provider in **AI filing…**. You can change it later; scanning and existing PDFs do not depend on the choice.

## Codex login

If you already use the official Codex CLI, sign in with `codex login`. Paper In uses the official SDK/runtime with that existing login. Leave the model field blank for the runtime default, or enter a model your account supports.

If you do not have Codex set up, follow the [official Codex setup](https://developers.openai.com/codex/cli/). The app bundles its SDK runtime, but does not install a global `codex` command or perform login for you.

## Claude login

If you already use Claude Code, sign in with `claude auth login`. Paper In uses the official Agent SDK with that existing login. Leave the model field blank for the runtime default, or enter a supported model ID.

For initial setup, see [Claude Code quickstart](https://code.claude.com/docs/en/quickstart). The app bundles its SDK runtime, but does not install a global `claude` command or perform login for you. Account eligibility and subscription limits still apply; see the notes below.

## API key

1. Choose **OpenAI · API key** or **Anthropic · API key**.
2. Enter a model ID available to your API account.
3. Enter the key and click **Store key in Keychain**, or save settings with the key entered.
4. Enable AI filing and save a document.

A blank key field keeps the existing saved key. Use **Remove saved key** to delete it. API usage has separate billing from ChatGPT/Claude subscriptions.

The adapters use OpenAI Responses and Anthropic Messages with structured JSON output. Choose a model that supports the required API and structured output. An unsupported model produces a retryable filing error; the PDF remains saved.

## Runtime paths and retries

AI filing needs Node.js 22+. Common Homebrew and nvm paths are detected automatically. If needed, set the Node executable under **Runtime paths**. Optional provider executable overrides let you use a specific local installation; blank means the SDK default.

New queued jobs capture their selected provider/model. **Retry analysis** uses current settings, so correcting a model, provider, or runtime path takes effect on retry. API keys are read from Keychain at execution time, never stored in job metadata. Ambient provider API keys are stripped from runtime environments so an existing-login adapter does not silently switch to API-key billing.

## Provider eligibility and data handling

Checked 5 September 2026. These are implementation notes, not a legal conclusion.

Paper In does not read OAuth token files, copy credentials into a new client, or spoof another product. Authentication stays with the official runtime, and Claude requests identify Paper In explicitly. Both existing-login paths passed live tests with a fictional document; that establishes technical operation for those accounts.

Anthropic's June subscription update acknowledges Agent SDK, `claude -p`, and third-party usage against subscription allowances. Its SDK/legal documentation also says third-party subscription login/rate limits require prior approval. Open-source status alone is not stated as an exemption. Clarify the distributed app's subscription eligibility before promoting that access as guaranteed.

References: [Claude subscription update](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan), [Agent SDK](https://code.claude.com/docs/en/agent-sdk/overview), [Claude legal and compliance](https://code.claude.com/docs/en/legal-and-compliance), [Codex SDK](https://learn.chatgpt.com/docs/codex-sdk), [Codex app server](https://learn.chatgpt.com/docs/app-server).

For what is sent to providers and retained locally, see [privacy and recovery](privacy-and-recovery.md). Dependency licenses are covered in [third-party notices](third-party.md).
