#!/usr/bin/env bash
# SessionStart hook that deletes local branches whose pull request was merged, so finished work
# does not pile up. PRs are squash-merged, so git cannot see a branch as merged; a branch counts as
# merged when its tip is the head of a merged PR, or an ancestor of one: then nothing on it is lost.
# A merged branch checked out in a clean worktree goes with that worktree; checked out here, the
# checkout moves to main first, if clean. Local main is fast-forwarded to origin/main.
# Branches that are not merged as-is are only listed. Never blocks: exit 0, or 1 (non-blocking,
# shown to the operator) when something could not be checked or cleaned.
#
# SessionStart hooks run in parallel, so this one refreshes the App token itself before calling gh.
# HOMELAB_GH overrides gh and skips the refresh (used by test.sh).
set -u
root="${CLAUDE_PROJECT_DIR:-.}"
gh="${HOMELAB_GH:-gh}"
[ -z "${HOMELAB_GH:-}" ] && bash "$root/.claude/hooks/token-refresh.sh" </dev/null >/dev/null 2>&1
runtime="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"; [ -d "$runtime" ] || runtime=/tmp
[ -z "${GH_TOKEN:-}" ] && [ -s "$runtime/homelab-app-token" ] && GH_TOKEN="$(cat "$runtime/homelab-app-token")" && export GH_TOKEN
cd "$root" 2>/dev/null && git rev-parse --git-dir >/dev/null 2>&1 || exit 0

fail=0; deleted=()
warn() { printf 'branch-cleanup.sh: %s\n' "$1" >&2; fail=1; }
clean() { [ -z "$(git -C "$1" status --porcelain 2>/dev/null)" ]; }

git fetch -q --prune origin 2>/dev/null || { warn "git fetch failed; branches not cleaned"; exit 1; }
merged="$("$gh" pr list --state merged --limit 200 --json headRefName,headRefOid \
  --jq '.[] | "\(.headRefName) \(.headRefOid)"' 2>/dev/null)" || { warn "gh pr list failed; branches not cleaned"; exit 1; }

# Worktree path per checked-out branch.
declare -A wt; here="$(git rev-parse --show-toplevel)"
while read -r k v; do
  case $k in worktree) p=$v ;; branch) wt[${v#refs/heads/}]=$p ;; esac
done < <(git worktree list --porcelain)

is_merged() { # is_merged <branch>: its tip equals, or is an ancestor of, a merged PR's head
  local tip; tip="$(git rev-parse "refs/heads/$1")"
  while read -r name head; do
    [ "$name" = "$1" ] || continue
    [ "$tip" = "$head" ] && return 0
    git cat-file -e "$head^{commit}" 2>/dev/null && git merge-base --is-ancestor "$tip" "$head" && return 0
  done <<< "$merged"
  return 1
}

# Fast-forward main where it is not checked out; the fetch refuses anything but a fast-forward.
[ -z "${wt[main]:-}" ] && git fetch -q origin main:main 2>/dev/null

stale=()
for b in $(git for-each-ref --format='%(refname:short)' refs/heads/); do
  [ "$b" = main ] && continue
  if ! is_merged "$b"; then
    [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$b")" = "[gone]" ] && stale+=("$b")
    continue
  fi
  p="${wt[$b]:-}"
  if [ -n "$p" ] && [ "$p" = "$here" ]; then
    clean "$p" || { warn "$b is merged but this checkout has uncommitted changes; kept"; continue; }
    git switch -q main 2>/dev/null && git merge -q --ff-only origin/main 2>/dev/null \
      || { warn "$b is merged but switching to main failed; kept"; continue; }
  elif [ -n "$p" ]; then
    { [ -d "$p" ] && clean "$p" && git worktree remove "$p" 2>/dev/null; } || [ ! -d "$p" ] \
      || { warn "$b is merged but its worktree $p has changes; kept"; continue; }
    git worktree prune
  fi
  git branch -q -D "$b" && deleted+=("$b")
done

[ ${#deleted[@]} -gt 0 ] && echo "branch-cleanup.sh: deleted merged branches: ${deleted[*]}"
[ ${#stale[@]} -gt 0 ] && echo "branch-cleanup.sh: remote gone but not merged as-is, kept: ${stale[*]}"
exit "$fail"
