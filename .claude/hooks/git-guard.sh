#!/usr/bin/env bash
# PreToolUse hook (Bash matcher). Blocks commands that would take the merge away from the
# operator or destroy history. Ordinary branch pushes, PR creation and comments stay allowed.
# Exit 2 = block; the message on stderr reaches Claude. Exit 0 = no opinion.
#
# Only the command string is inspected (tool_input.command). The earlier sed extraction swallowed
# the rest of the JSON, so a "+" or the word "merge" in the call's description blocked a plain
# branch push. jq is required; without it the hook fails closed.
set -u
command -v jq >/dev/null 2>&1 || {
  printf 'git-guard.sh: jq is required to parse the tool input (docs/operator-setup.md, section 3).\n' >&2; exit 2; }
cmd="$(jq -r '.tool_input.command // empty' 2>/dev/null)"
[ -z "$cmd" ] && exit 0

deny() { printf 'Blocked by .claude/hooks/git-guard.sh: %s\nThe merge into main is the operator'"'"'s alone; open or update the PR and stop.\n' "$1" >&2; exit 2; }

s='[[:space:]]'
# "git push", allowing git's own options in between (-C dir, -c k=v, --no-pager), then the rest
# of that one shell command up to the next ; & or |, so a "+" elsewhere in a compound command
# does not count as a force push.
push="git(${s}+-[^[:space:]]*(${s}+[^-[:space:]][^[:space:]]*)?)*${s}+push[^;&|]*"

if   [[ "$cmd" =~ gh${s}+pr${s}+merge ]];                                then deny "merging a pull request"
elif [[ "$cmd" =~ gh${s}+api.*/merge ]] || [[ "$cmd" =~ pulls/[^/]+/merge ]]; then deny "merging through the API"
elif [[ "$cmd" =~ ${push}${s}(--force[^[:space:]]*|-f)(${s}|$) ]];       then deny "force push"
elif [[ "$cmd" =~ ${push}${s}\+ ]];                                      then deny "force push (+refspec)"
elif [[ "$cmd" =~ ${push}(${s}|:|/)main(${s}|$) ]];                      then deny "push to main"
elif [[ "$cmd" =~ git${s}+reset${s}+--hard ]];                           then deny "hard reset"
elif [[ "$cmd" =~ git${s}+branch${s}+(-D|--delete${s}+--force|--force${s}+--delete) ]]; then deny "forced branch delete"
elif [[ "$cmd" =~ git${s}+clean${s}+-[a-zA-Z]*f ]];                      then deny "git clean -f"
elif [[ "$cmd" =~ git${s}+(checkout|restore)${s}+\.(${s}|$) ]];           then deny "discarding all working changes"
fi
exit 0
