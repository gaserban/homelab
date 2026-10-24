#!/usr/bin/env bash
# Regression tests for the hooks. Run from anywhere: bash .claude/hooks/test.sh
# Guard cases feed a PreToolUse JSON payload to a hook and check the exit code (2 = blocked,
# 0 = allowed); token-refresh cases check whether the hook called a stub helper.
# Exits 1 if any case mismatches.
set -u
cd "$(dirname "$0")/../.." || exit 1
tmp="${TMPDIR:-/tmp}"; fail=0
t() { # t <hook> <expected rc> <label> <command> [description]
  local hook=$1 want=$2 label=$3 c=$4 d=${5:-}
  local payload; payload=$(jq -cn --arg c "$c" --arg d "$d" '{tool_name:"Bash",tool_input:({command:$c} + (if $d=="" then {} else {description:$d} end))}')
  printf '%s' "$payload" | bash ".claude/hooks/$hook" >/dev/null 2>"$tmp/hooktest.err"; local rc=$?
  if [ "$rc" = "$want" ]; then printf 'ok    %-5s %-7s %s\n' "$hook" "rc=$rc" "$label"
  else fail=1; printf 'FAIL  %-5s want=%s got=%s %s\n      %s\n' "$hook" "$want" "$rc" "$label" "$(head -1 "$tmp/hooktest.err")"; fi
}
G=git-guard.sh; I=issue-template.sh

echo "# git-guard: blocked"
t $G 2 'gh pr merge'                 'gh pr merge 5 --squash'
t $G 2 'gh pr merge, escaped quotes' 'gh pr merge 5 --subject "x"'
t $G 2 'merge through gh api'        'gh api -X PUT repos/o/r/pulls/9/merge'
t $G 2 'merge through curl'          'curl -X PUT https://api.github.com/repos/o/r/pulls/4/merge'
t $G 2 'push main'                   'git push origin main'
t $G 2 'push HEAD:main'              'git push origin HEAD:main'
t $G 2 'push feat:main'              'git push origin feat:main'
t $G 2 'push refs/heads/main'        'git push origin HEAD:refs/heads/main'
t $G 2 'push main after &&'          'git commit -m x && git push origin main'
t $G 2 'push --force'                'git push --force origin feat'
t $G 2 'push --force-with-lease'     'git push --force-with-lease origin feat'
t $G 2 'push --force-with-lease=x'   'git push --force-with-lease=main origin feat'
t $G 2 'push -f'                     'git push -f origin feat'
t $G 2 'push -f at end'              'git push origin feat -f'
t $G 2 'push +refspec'               'git push origin +feat'
t $G 2 'git -C dir push main'        'git -C /tmp/x push origin main'
t $G 2 'git -c k=v push main'        'git -c a=b push origin HEAD:main'
t $G 2 'git --no-pager push -f'      'git --no-pager push -f origin feat'
t $G 2 'reset --hard'                'git reset --hard HEAD~1'
t $G 2 'branch -D'                   'git branch -D feat'
t $G 2 'branch --delete --force'     'git branch --delete --force feat'
t $G 2 'clean -f'                    'git clean -f'
t $G 2 'clean -fdx'                  'git clean -fdx'
t $G 2 'clean -xf'                   'git clean -xf'
t $G 2 'checkout .'                  'git checkout .'
t $G 2 'restore .'                   'git restore .'

echo "# git-guard: allowed"
t $G 0 'push branch'                 'git push -u origin feat'
t $G 0 'push branch, desc has +'     'git push -u origin feat' 'Push branch (amd64 + arm64)'
t $G 0 'push branch, desc says merge' 'git push -u origin feat' 'Push so the operator can run gh pr merge'
t $G 0 'push branch main-fix'        'git push -u origin main-fix'
t $G 0 'push branch maintenance'     'git push -u origin maintenance'
t $G 0 'push main:feat'              'git push origin main:feat'
t $G 0 'push feat && echo a+b'       'git push origin feat && echo a+b'
t $G 0 'push, commit msg has main'   'git commit -m "sync with main" && git push -u origin feat'
t $G 0 'commit msg says push main'   'git commit -m "push to main later"'
t $G 0 'git -C dir push feat'        'git -C /tmp/x push origin feat'
t $G 0 'push --dry-run'              'git push origin feat --dry-run'
t $G 0 'gh pr view'                  'gh pr view 1 --json merged'
t $G 0 'git status'                  'git status'
t $G 0 'checkout main'               'git checkout main'
t $G 0 'restore one path'            'git restore .claude/x'
t $G 0 'branch -d'                   'git branch -d feat'
t $G 0 'clean -n'                    'git clean -n'
t $G 0 'multiline'                   $'ls\ngit push -u origin feat'

echo "# issue-template"
ok="$tmp/hooktest-body-ok.md"; printf '## Goal\nx\n## Done when\n- [ ] y\n## Out of scope\nz\n## Depends on\nnothing\n' > "$ok"
C='gh issue create'; E='gh issue edit'
t $I 0 'create --body-file ok'       "$C --title t --body-file $ok"
t $I 0 'create -F ok'                "$C --title t -F $ok"
t $I 2 'create --body-file missing'  "$C --title t --body-file /nonexistent"
t $I 2 'create --body-file heredoc'  $'cat > '"$tmp"$'/b.md <<EOF\n## Goal\nEOF\n'"$C --title t --body-file $tmp/b.md"
t $I 0 'create --body ok'            "$C --title t --body \"## Goal"$'\n'"## Done when"$'\n'"## Out of scope"$'\n'"## Depends on\""
t $I 2 'create --body partial'       "$C --title t --body \"## Goal only\""
t $I 2 'create without body'         "$C --title t"
t $I 2 'edit --body partial'         "$E 3 --body \"## Goal only\""
t $I 0 'edit --title only'           "$E 3 --title new"
t $I 0 'edit --add-label'            "$E 3 --add-label bug"
t $I 0 'issue view'                  'gh issue view 3'
t $I 0 'issue comment'               'gh issue comment 3 --body hi'
t $I 2 'create after cd &&'          "cd /tmp && $C --title t"
t $I 2 'create in \$( )'             "url=\$($C --title t)"
t $I 2 'create on second line'       $'cd /tmp\n'"$C --title t"
t $I 0 'commit msg mentions edit'    "git commit -F - <<'EOF'"$'\n'"fix: $E demanded a body"$'\n'"EOF"
t $I 0 'echo mentions create'        "echo 'use $C with a body file'"

echo "# token-refresh: calls gh-app-token only when the cache is stale and the command needs it"
rt="$tmp/hooktest-runtime"; stub="$tmp/hooktest-stub"; calls="$tmp/hooktest-calls"
mkdir -p "$rt"; printf '#!/bin/sh\necho x >> "%s"\n' "$calls" > "$stub"; chmod +x "$stub"
r() { # r <want: call|none> <cache: fresh|stale|missing> <label> <payload>
  local want=$1 cache=$2 label=$3 payload=$4 got=none
  rm -f "$calls" "$rt/homelab-app-token"
  case $cache in
    fresh) printf tok > "$rt/homelab-app-token" ;;
    stale) printf tok > "$rt/homelab-app-token"; touch -d '-51 minutes' "$rt/homelab-app-token" ;;
  esac
  printf '%s' "$payload" | XDG_RUNTIME_DIR="$rt" HOMELAB_APP_TOKEN_HELPER="$stub" bash .claude/hooks/token-refresh.sh >/dev/null 2>&1
  [ -s "$calls" ] && got=call
  if [ "$got" = "$want" ]; then printf 'ok    %-7s %-5s %s\n' token "$want" "$label"
  else fail=1; printf 'FAIL  %-7s want=%s got=%s %s\n' token "$want" "$got" "$label"; fi
}
b() { jq -cn --arg c "$1" '{hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}'; }
S='{"hook_event_name":"SessionStart","source":"startup"}'
r none  fresh   'session start, fresh'       "$S"
r call  stale   'session start, stale'       "$S"
r call  missing 'session start, no cache'    "$S"
r none  fresh   'gh, fresh'                  "$(b 'gh pr list')"
r call  stale   'gh, stale'                  "$(b 'gh pr list')"
r call  stale   'git push, stale'            "$(b 'git push -u origin feat')"
r call  stale   'push after &&, stale'       "$(b 'git commit -m x && git push')"
r call  stale   '/usr/bin/gh, stale'         "$(b '/usr/bin/gh issue view 3')"
r none  stale   'ls, stale'                  "$(b 'ls -la')"
r none  stale   'git status, stale'          "$(b 'git status')"
r none  stale   'ghcr.io mention, stale'     "$(b 'curl https://ghcr.io/v2/')"

echo "# malformed input"
t $G 0 'no command key'              ''
printf '' | bash .claude/hooks/$G; [ $? = 0 ] && echo "ok    $G rc=0   empty stdin" || { fail=1; echo "FAIL  $G empty stdin"; }
printf 'garbage' | bash .claude/hooks/$G; [ $? = 0 ] && echo "ok    $G rc=0   not json" || { fail=1; echo "FAIL  $G not json"; }

[ $fail = 0 ] && echo "all hook tests passed" || { echo "hook tests FAILED"; exit 1; }
