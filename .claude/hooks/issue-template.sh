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
# Detect the command on a copy with heredoc bodies removed, so a file or message that merely quotes
# "gh issue edit ..." on its own line is not mistaken for the command. The body check further down
# reads the full text, because a body may legitimately arrive through a heredoc.
awkprog=$(cat <<'AWK'
inh { if ($0 ~ ("^[[:space:]]*" term "[[:space:]]*$")) inh = 0; next }
{
  if (match($0, /<<-?[[:space:]]*["']?[A-Za-z_][A-Za-z0-9_]*["']?/)) {
    term = substr($0, RSTART, RLENGTH)
    sub(/^<<-?[[:space:]]*["']?/, "", term); sub(/["']$/, "", term)
    inh = 1
  }
  print
}
AWK
)
code="$(printf '%s\n' "$cmd" | awk "$awkprog")"
# A command starts at the beginning of a line or after ; & | ( or $( . Split there and look for a
# segment that is itself "gh issue create|edit ...". Asking for help is not creating an issue.
s='[[:space:]]'
mode=""
while IFS= read -r seg; do
  [[ "$seg" =~ ^${s}*gh${s}+issue${s}+(create|edit)(${s}|$) ]] || continue
  m="${BASH_REMATCH[1]}"
  if [[ "$seg" =~ (^|${s})(--help|-h)(${s}|$) ]]; then exit 0; fi
  mode="$m"; break
done < <(printf '%s\n' "$code" | sed -E 's/\$\(|[;&|(]/\n/g')
[ -n "$mode" ] || exit 0

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
