#!/usr/bin/env bash
# PreToolUse hook on Agent, registered by the hl-engineer skill's frontmatter (ADR 0016).
# Bounds the plan-review loop: each hl-plan-reviewer launch names its lens on the prompt's first
# line ("Lens: Falsifier|Saboteur|Newcomer"), and the running run's .flow/<issue>.json counts
# launches per lens under .review. The launch past .max_rounds (default 3) is denied.
# Exit 2 = block with reason on stderr. Exit 0 = fine.
#
# The skill's hooks stay registered for the rest of the session, so everything that is not an
# hl-plan-reviewer launch inside a running run passes untouched.
set -u
input="$(cat)"
case "$input" in *hl-plan-reviewer*) ;; *) exit 0 ;; esac
command -v jq >/dev/null 2>&1 || {
  printf 'flow-review-bound.sh: jq is required to count review rounds (docs/operator-setup.md, section 3).\n' >&2; exit 2; }
[ "$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null)" = hl-plan-reviewer ] || exit 0

lens="$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""' | head -1 |
  sed -nE 's/^Lens:[[:space:]]*(Falsifier|Saboteur|Newcomer)[[:space:]]*$/\1/p')"
[ -n "$lens" ] || {
  printf 'Blocked: the first line of an hl-plan-reviewer prompt must be "Lens: Falsifier", "Lens: Saboteur" or "Lens: Newcomer".\n' >&2; exit 2; }

dir="${CLAUDE_PROJECT_DIR:-.}/.flow"
active=()
for f in "$dir"/*.json; do
  [ -f "$f" ] && jq -e '.status == "running"' "$f" >/dev/null 2>&1 && active+=("$f")
done
[ ${#active[@]} -eq 0 ] && exit 0
[ ${#active[@]} -gt 1 ] && {
  printf 'Blocked: more than one running hl-engineer run in .flow/ (%s). Set the others to stopped or awaiting-operator.\n' "${active[*]}" >&2; exit 2; }
f="${active[0]}"

# Parallel launches of the three lenses update the same file: serialise them.
exec 9>"$f.lock"
flock -w 10 9 || { printf 'Blocked: could not lock %s to count the review round.\n' "$f" >&2; exit 2; }
n="$(jq -r --arg l "$lens" '.review[$l] // 0' "$f")"
max="$(jq -r '.max_rounds // 3' "$f")"
if [ "$n" -ge "$max" ]; then
  printf 'Blocked: review bound reached (%s has run %s of %s rounds). Stop the loop and ask the operator: approve as is, more rounds, revise it themselves, or stop.\n' "$lens" "$n" "$max" >&2
  exit 2
fi
jq --arg l "$lens" '.review[$l] = ((.review[$l] // 0) + 1)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
exit 0
