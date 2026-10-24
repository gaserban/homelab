#!/usr/bin/env bash
# PreToolUse hook for `gh issue create|edit`. Refuses a body that lacks the four headings.
# Exit 2 = block with reason on stderr. Exit 0 = fine.
#
# Only tool_input.command is inspected (jq; fails closed without it). `gh issue edit` that does
# not touch the body (title, labels, assignees) passes: the body it leaves alone was checked when
# it was written.
set -u
command -v jq >/dev/null 2>&1 || {
  printf 'issue-template.sh: jq is required to parse the tool input (docs/operator-setup.md, section 3).\n' >&2; exit 2; }
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
# Match "gh issue create|edit" only where a command starts (line start, after ; & | ( or $( ),
# not inside a commit message or a heredoc that merely mentions it.
s='[[:space:]]'
nl=$'\n'
start="(^|[;&|(]|\\\$\\(|${nl})${s}*"
if   [[ "$cmd" =~ ${start}gh${s}+issue${s}+create ]]; then mode=create
elif [[ "$cmd" =~ ${start}gh${s}+issue${s}+edit ]];   then mode=edit
else exit 0
fi

body=""
if   printf '%s' "$cmd" | grep -qE -- '(^|[[:space:]])(--body-file|-F)[= ]'; then
  f="$(printf '%s' "$cmd" | sed -nE 's/.*(--body-file|-F)[= ]+("([^"]*)"|'"'"'([^'"'"']*)'"'"'|([^[:space:]]+)).*/\3\4\5/p' | head -1)"
  if [ -n "$f" ] && [ -r "$f" ]; then
    body="$(cat "$f")"
  else
    printf 'Blocked: body file "%s" is not readable at check time. Write it in a separate step first and pass a literal absolute path (no variables).\n' "$f" >&2; exit 2
  fi
elif printf '%s' "$cmd" | grep -qE -- '(^|[[:space:]])(--body|-b)[= ]'; then
  body="$cmd"
elif [ "$mode" = edit ]; then
  exit 0
else
  printf 'Blocked: create the issue with --body or --body-file so the template can be checked.\n' >&2; exit 2
fi

missing=""
for h in "## Goal" "## Done when" "## Out of scope" "## Depends on"; do
  printf '%s' "$body" | grep -qF -- "$h" || missing="$missing '$h'"
done
if [ -n "$missing" ]; then
  printf 'Blocked: issue body is missing%s. Use .github/ISSUE_TEMPLATE/task.md.\n' "$missing" >&2; exit 2
fi
exit 0
