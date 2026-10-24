#!/usr/bin/env bash
# PreToolUse hook (Bash matcher). Blocks commands that would take the merge away from the
# operator or destroy history. Ordinary branch pushes, PR creation and comments stay allowed.
# Exit 2 = block; the message on stderr reaches Claude. Exit 0 = no opinion.
set -u
input="$(cat)"
cmd="$(printf '%s' "$input" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' | head -1 | sed 's/\\"/"/g')"
[ -z "$cmd" ] && exit 0

deny() { printf 'Blocked by .claude/hooks/git-guard.sh: %s\nThe merge into main is the operator'"'"'s alone; open or update the PR and stop.\n' "$1" >&2; exit 2; }

case "$cmd" in
  *"gh pr merge"*)                                   deny "merging a pull request" ;;
  *"gh api"*"/merge"*|*"pulls/"*"/merge"*)           deny "merging through the API" ;;
  *"git push"*"--force"*|*"git push"*" -f"*|*"git push"*"+"*) deny "force push" ;;
  *"git push"*" main"*|*"git push"*":main"*|*"git push"*"HEAD:main"*) deny "push to main" ;;
  *"git reset --hard"*)                              deny "hard reset" ;;
  *"git branch -D"*|*"git branch --delete --force"*) deny "forced branch delete" ;;
  *"git clean -f"*|*"git clean -xf"*|*"git clean -fd"*) deny "git clean -f" ;;
  *"git checkout ."*|*"git restore ."*)              deny "discarding all working changes" ;;
esac
exit 0
