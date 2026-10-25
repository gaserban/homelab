#!/usr/bin/env bash
# Regression tests for the hooks. Run from anywhere: bash .claude/hooks/test.sh
# Guard cases feed a PreToolUse JSON payload to a hook and check the exit code (2 = blocked,
# 0 = allowed); token-refresh cases check whether the hook called a stub helper; skills-restore
# cases restore from a local git repository standing in for GitHub.
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
t $I 0 'create --help'                "$C --help"
t $I 0 'edit -h'                      "$E 4 -h"
t $I 0 'heredoc lines start with edit' "cat > $tmp/r.md <<'EOF'"$'\n'"$E 4 --add-blocked-by 3"$'\n'"$C --title t --body-file /nope"$'\n'"EOF"
t $I 2 'create, heredoc body partial' "$C --title t --body \"\$(cat <<'EOF'"$'\n'"## Goal only"$'\n'"EOF"$'\n'")\""
t $I 0 'create, heredoc body ok'      "$C --title t --body \"\$(cat <<'EOF'"$'\n'"## Goal"$'\n'"## Done when"$'\n'"## Out of scope"$'\n'"## Depends on"$'\n'"EOF"$'\n'")\""

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

echo "# flow-review-bound: at most max_rounds hl-plan-reviewer launches per lens in the running run"
proj="$tmp/hooktest-proj"; F=flow-review-bound.sh
a() { # a <want rc> <label> <subagent_type> <prompt>
  local want=$1 label=$2 payload rc
  payload=$(jq -cn --arg t "$3" --arg p "$4" '{hook_event_name:"PreToolUse",tool_name:"Agent",tool_input:{subagent_type:$t,prompt:$p}}')
  printf '%s' "$payload" | CLAUDE_PROJECT_DIR="$proj" bash ".claude/hooks/$F" >/dev/null 2>"$tmp/hooktest.err"; rc=$?
  if [ "$rc" = "$want" ]; then printf 'ok    %-5s %-7s %s\n' "$F" "rc=$rc" "$label"
  else fail=1; printf 'FAIL  %-5s want=%s got=%s %s\n      %s\n' "$F" "$want" "$rc" "$label" "$(head -1 "$tmp/hooktest.err")"; fi
}
run() { printf '{"issue":%s,"stage":"plan","status":"%s","max_rounds":%s}\n' "$1" "$2" "$3" > "$proj/.flow/$1.json"; }
R=hl-plan-reviewer
rm -rf "$proj"; mkdir -p "$proj"
a 0 'no .flow dir: reviewer passes'     $R $'Lens: Falsifier\nbrief'
mkdir -p "$proj/.flow"; run 7 done 3
a 0 'no running run: reviewer passes'   $R $'Lens: Falsifier\nbrief'
run 7 running 2
a 0 'other agent type passes'           Explore 'find things'
a 2 'reviewer without a lens line'      $R 'review this brief'
a 2 'reviewer with an unknown lens'     $R $'Lens: Optimist\nbrief'
a 0 'Falsifier round 1'                 $R $'Lens: Falsifier\nbrief'
a 0 'Saboteur round 1'                  $R $'Lens: Saboteur\nbrief'
a 0 'Falsifier round 2'                 $R $'Lens: Falsifier\nbrief'
a 2 'Falsifier round 3 past max 2'      $R $'Lens: Falsifier\nbrief'
a 0 'Newcomer round 1 still allowed'    $R $'Lens: Newcomer\nbrief'
[ "$(jq -c .review "$proj/.flow/7.json")" = '{"Falsifier":2,"Saboteur":1,"Newcomer":1}' ] \
  && echo "ok    $F counts  {Falsifier:2,Saboteur:1,Newcomer:1}" \
  || { fail=1; echo "FAIL  $F counts $(jq -c .review "$proj/.flow/7.json")"; }
run 8 running 3
a 2 'two running runs: ambiguous'       $R $'Lens: Saboteur\nbrief'
rm -f "$proj/.flow/8.json"
jq '.max_rounds = 3' "$proj/.flow/7.json" > "$tmp/hooktest-run.json" && mv "$tmp/hooktest-run.json" "$proj/.flow/7.json"
a 0 'max_rounds raised to 3: round 3'   $R $'Lens: Falsifier\nbrief'
a 2 'round 4 past max 3'                $R $'Lens: Falsifier\nbrief'
run 7 running 3; p=$(jq -cn '{tool_name:"Agent",tool_input:{subagent_type:"hl-plan-reviewer",prompt:"Lens: Saboteur\nbrief"}}')
for i in 1 2 3 4 5 6; do (printf '%s' "$p" | CLAUDE_PROJECT_DIR="$proj" bash ".claude/hooks/$F" 2>/dev/null; echo $? > "$tmp/hooktest-par.$i") & done; wait
allowed=$(cat "$tmp"/hooktest-par.* | grep -c '^0$'); rm -f "$tmp"/hooktest-par.*
[ "$allowed" = 3 ] && [ "$(jq .review.Saboteur "$proj/.flow/7.json")" = 3 ] \
  && echo "ok    $F parallel 6 launches, 3 allowed" \
  || { fail=1; echo "FAIL  $F parallel: $allowed allowed, count $(jq .review.Saboteur "$proj/.flow/7.json")"; }

echo "# skills-restore: restores the skills in skills-lock.json, keeping only hash matches"
sk="$tmp/hooktest-skills"; up="$sk/up/acme/kit.git"; proj="$sk/proj"; rm -rf "$sk"
mkdir -p "$up/skills/one" "$up/skills/multi/agents" "$proj"
printf 'one\n' > "$up/skills/one/SKILL.md"; printf '{}\n' > "$up/skills/one/metadata.json"
printf 's\n' > "$up/skills/multi/SKILL.md"; printf 'm\n' > "$up/skills/multi/SKILL-MECHANICS.md"
printf 'x\n' > "$up/skills/multi/agents/x.yaml"
gc() { git -C "$up" -c user.name=t -c user.email=t@t "$@" >/dev/null 2>&1; }
gc init -q; gc add -A; gc commit -qm v1
h() { printf "$1" | sha256sum | cut -d' ' -f1; }
lockjson() { # lockjson [jq filter]. Hashes written out by hand: snapshot scheme for one and multi
  # (multi in localeCompare order), the CLI's folder scheme for "One Folder".
  jq -n --arg one "$(h 'SKILL.md\0one\n\0')" --arg folder "$(h 'SKILL.mdone\n')" \
    --arg multi "$(h 'agents/x.yaml\0x\n\0SKILL-MECHANICS.md\0m\n\0SKILL.md\0s\n\0')" '{version: 1, skills: {
      one: {source: "acme/kit", sourceType: "github", skillPath: "skills/one/SKILL.md", computedHash: $one},
      multi: {source: "acme/kit", sourceType: "github", skillPath: "skills/multi/SKILL.md", computedHash: $multi},
      "One Folder": {source: "acme/kit", sourceType: "github", skillPath: "skills/one/SKILL.md", computedHash: $folder}}}' \
    | jq "${1:-.}" > "$proj/skills-lock.json"
}
s() { # s <expected rc> <label> [git base]
  local want=$1 label=$2 gb=${3:-file://$sk/up}
  CLAUDE_PROJECT_DIR="$proj" HOMELAB_SKILLS_GIT_BASE="$gb" bash .claude/hooks/skills-restore.sh </dev/null >/dev/null 2>"$tmp/hooktest.err"; local rc=$?
  if [ "$rc" = "$want" ]; then printf 'ok    %-7s %-5s %s\n' skills "rc=$rc" "$label"
  else fail=1; printf 'FAIL  %-7s want=%s got=%s %s\n      %s\n' skills "$want" "$rc" "$label" "$(head -1 "$tmp/hooktest.err")"; fi
}
k() { # k <label> <test...>: checks the state a run left behind
  local label=$1; shift
  if "$@"; then printf 'ok    %-7s %-5s %s\n' skills check "$label"; else fail=1; printf 'FAIL  %-7s %s\n' skills "$label"; fi
}
SK="$proj/.claude/skills"
lockjson
s 0 'restores missing skills'
k 'single-file skill in place'       [ -f "$SK/one/SKILL.md" ]
k 'metadata.json left out'           [ ! -e "$SK/one/metadata.json" ]
k 'multi-file, localeCompare order'  [ -f "$SK/multi/SKILL-MECHANICS.md" ]
k 'folder scheme, CLI folder name'   [ -f "$SK/one-folder/SKILL.md" ]
s 0 'stamp hit: no download'         file:///nonexistent
rm "$SK/.restored"
s 0 'lock changed, folders intact: no download' file:///nonexistent
printf 'edited\n' >> "$SK/one/SKILL.md"; rm "$SK/.restored"
s 0 'edited folder is restored'
k 'edit undone'                      cmp -s "$SK/one/SKILL.md" "$up/skills/one/SKILL.md"
printf 'one v2\n' > "$up/skills/one/SKILL.md"; gc commit -qam v2; rm -rf "$SK/one"
s 1 'upstream moved past the lock'
k 'mismatch not installed'           [ ! -e "$SK/one" ]
k 'no stamp while a skill is missing' [ ! -e "$SK/.restored" ]
printf 'one\n' > "$up/skills/one/SKILL.md"; gc commit -qam v3
lockjson '.skills.evil = {source: "acme/kit", sourceType: "github", skillPath: "../../x/SKILL.md", computedHash: "0"}'
s 1 'skillPath with .. skipped'
lockjson '.skills.evil = {source: "acme/kit;id", sourceType: "github", skillPath: "skills/one/SKILL.md", computedHash: "0"}'
s 1 'unsafe source skipped'
k 'the rest still restored'          [ -f "$SK/one/SKILL.md" ]
rm "$proj/skills-lock.json"
s 0 'no skills-lock.json'

echo "# malformed input"
t $G 0 'no command key'              ''
printf '' | bash .claude/hooks/$G; [ $? = 0 ] && echo "ok    $G rc=0   empty stdin" || { fail=1; echo "FAIL  $G empty stdin"; }
printf 'garbage' | bash .claude/hooks/$G; [ $? = 0 ] && echo "ok    $G rc=0   not json" || { fail=1; echo "FAIL  $G not json"; }

[ $fail = 0 ] && echo "all hook tests passed" || { echo "hook tests FAILED"; exit 1; }
