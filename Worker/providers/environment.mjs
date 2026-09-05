// Keep authentication with the official installed runtimes. Never read or copy tokens.
export function runtimeEnvironment() {
  const keys = [
    'HOME',
    'PATH',
    'TMPDIR',
    'USER',
    'LOGNAME',
    'LANG',
    'LC_ALL',
    'SHELL',
    'SystemRoot',
    'CODEX_HOME',
    'CLAUDE_CONFIG_DIR',
  ];
  return Object.fromEntries(keys.filter((k) => process.env[k]).map((k) => [k, process.env[k]]));
}
export function safeProviderError(error) {
  const status = error?.status;
  if (status === 401 || status === 403)
    return 'Provider authentication failed. Check your login or API key.';
  if (status === 429) return 'Provider usage limit reached. Retry after your allowance resets.';
  if (error?.name === 'AbortError' || error?.name === 'TimeoutError')
    return 'Provider timed out. The PDF is safe; retry when ready.';
  return 'Provider could not complete the request. Check its login, model and availability, then retry.';
}
