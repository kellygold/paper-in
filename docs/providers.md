# Provider integration notes

Status: checked 5 September 2026. This records implementation and unresolved publication questions, not a legal conclusion.

Paper In uses the official Claude Agent SDK and Codex SDK for local runtime integrations, and direct official API endpoints for API-key integrations. It does not read OAuth token files, copy credentials into a new client or spoof another product. Runtime authentication remains with the provider's software. Claude requests identify Paper In explicitly.

Anthropic's June subscription update acknowledges Agent SDK, `claude -p` and third-party usage against subscription allowances. Its SDK/legal documentation also says third-party subscription login/rate limits require prior approval. Open-source status alone is not stated as an exemption. A successful live test proves technical operation, not blanket authorization for public distribution. Clarify the distributed app's subscription eligibility before promoting that access as guaranteed.

Sources:
- https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan
- https://code.claude.com/docs/en/agent-sdk/overview
- https://code.claude.com/docs/en/legal-and-compliance
- https://learn.chatgpt.com/docs/codex-sdk
- https://learn.chatgpt.com/docs/app-server

New queued jobs capture their selected provider/model. Manual retry uses the current settings so authentication/model corrections can take effect. API keys are looked up at execution time, never copied into job metadata. Existing runtime environment API keys are stripped so selecting a subscription adapter does not silently use a paid API key from the parent shell.
