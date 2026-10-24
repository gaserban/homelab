#!/usr/bin/env bash
# PreToolUse hook for `gh issue create|edit`. Refuses a body that lacks the four headings.
# Exit 2 = block with reason on stderr. Exit 0 = fine.
set -u
input="$(cat)"
cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1 | sed 's/\\"/"/g; s/\n/\n/g')"
case "$cmd" in *"gh issue create"*|*"gh issue edit"*) ;; *) exit 0 ;; esac

body=""
if   printf '%s' "$cmd" | grep -qE -- '--body-file[= ]|-F[= ]'; then
  f="$(printf '%s' "$cmd" | sed -nE 's/.*(--body-file|-F)[= ]+("([^"]*)"|'"'"'([^'"'"']*)'"'"'|([^ ]+)).*/\3\4\5/p' | head -1)"
  [ -n "$f" ] && [ -r "$f" ] && body="$(cat "$f")"
elif printf '%s' "$cmd" | grep -qE -- '--body[= ]|-b[= ]'; then
  body="$cmd"
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
