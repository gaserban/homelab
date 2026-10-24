#!/usr/bin/env bash
# SessionStart and PreToolUse (Bash) hook that keeps the App token cache fresh (issue #11).
# Hooks run outside the sandbox, so only here can gh-app-token read the App key and mint a token;
# sandboxed commands then read the cached token. Never blocks: exit 0, or 1 (non-blocking, shown
# to the operator) when minting fails.
#
# PreToolUse refreshes only for commands that need the token: `gh` or `git ... push`.
# HOMELAB_APP_TOKEN_HELPER overrides the helper (used by test.sh).
set -u
helper="${HOMELAB_APP_TOKEN_HELPER:-${CLAUDE_PROJECT_DIR:-.}/tools/gh-app-token}"
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; [ -d "$runtime" ] || runtime=/tmp
cache="$runtime/homelab-app-token"
max_age=3000 # 50 minutes; the helper serves the cache up to 55, tokens live 60

input="$(cat)"
# Without jq the command cannot be inspected, so every Bash call gets the stale-cache check.
if printf '%s' "$input" | grep -q '"hook_event_name" *: *"PreToolUse"' && command -v jq >/dev/null 2>&1; then
  cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)"
  printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]_.-])gh([^[:alnum:]_.-]|$)|(^|[^[:alnum:]_.-])git[[:space:]]([^;&|]*[[:space:]])?push([[:space:];&|)]|$)' \
    || exit 0
fi

if [ -f "$cache" ] && [ $(( $(date +%s) - $(stat -c %Y "$cache") )) -lt "$max_age" ]; then exit 0; fi
"$helper" --refresh >/dev/null || { echo "token-refresh.sh: $helper failed; gh and git push will fail in the sandbox" >&2; exit 1; }
