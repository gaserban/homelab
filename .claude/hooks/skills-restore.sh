#!/usr/bin/env bash
# SessionStart hook that restores the downloaded skills listed in skills-lock.json (ADR 0017).
# Their folders are gitignored. Each missing or changed one is fetched from its author's GitHub
# repository into .claude/skills/<name> and kept only if its hash equals the lock's computedHash,
# so an upstream change never lands unreviewed; taking one is a reinstall with the skills CLI.
# Cache-first: a stamp holding the lock's sha256 skips all work until the lock changes or a folder
# goes missing. Never blocks: exit 0, or 1 (non-blocking, shown to the operator) when a skill is
# not restored.
#
# HOMELAB_SKILLS_GIT_BASE overrides https://github.com (used by test.sh).
set -u
root="${CLAUDE_PROJECT_DIR:-.}"
lock="$root/skills-lock.json"; dest="$root/.claude/skills"; stamp="$dest/.restored"
base="${HOMELAB_SKILLS_GIT_BASE:-https://github.com}"
[ -f "$lock" ] || exit 0
for c in jq git sha256sum; do
  command -v "$c" >/dev/null 2>&1 || { echo "skills-restore.sh: $c is required; downloaded skills not restored" >&2; exit 1; }
done
mkdir -p "$dest"
want="$(sha256sum "$lock" | cut -d' ' -f1)"

# One line per skill: name, source, ref, skill directory inside the source, computedHash. Fields are
# split on the unit separator, not a tab: read collapses consecutive tabs, so an empty ref would
# shift every later field.
u=$'\x1f'
entries="$(jq -r '.skills | to_entries[] | select(.value.sourceType == "github")
  | [.key, .value.source, (.value.ref // ""), ((.value.skillPath // "SKILL.md") | sub("/?[^/]*$"; "")), .value.computedHash]
  | join("\u001f")' "$lock")"

# The skills CLI's sanitizeName: the folder the CLI itself would install the skill into.
folder() {
  local n; n="$(printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9._]+/-/g; s/^[.-]+|[.-]+$//g' | cut -c1-255)"
  printf '%s' "${n:-unnamed-skill}"
}

if [ "$(cat "$stamp" 2>/dev/null)" = "$want" ]; then
  missing=0
  while IFS=$u read -r name _; do [ -z "$name" ] || [ -d "$dest/$(folder "$name")" ] || missing=1; done <<< "$entries"
  [ "$missing" = 0 ] && exit 0
fi
if command -v flock >/dev/null 2>&1; then exec 9>"$dest/.restore.lock"; flock -n 9 || exit 0; fi

# Paths on stdin, sorted like JavaScript localeCompare (ICU root collation): case-insensitive first,
# punctuation before digits before letters, lowercase before uppercase only to break ties.
icu_sort() {
  awk 'BEGIN { ord = " _-,;:!?.'"'"'\"()[]{}@*/\\&#%`^+<=>|~$0123456789abcdefghijklmnopqrstuvwxyz" }
  { p = ""; t = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1); l = tolower(c); k = index(ord, l)
      p = p (k ? sprintf("%c", 32 + k) : "~" c); t = t (c != l ? "b" : "a") }
    print p "\001" t "\t" $0 }' | LC_ALL=C sort | cut -f2-
}
# skill_hash <dir> <folder|snapshot>. folder: the CLI's hash for git-clone installs (path, then
# contents, per file). snapshot: the skills.sh hash for its downloads (path, NUL, contents, NUL).
skill_hash() {
  (cd "$1" && find . \( -name .git -o -name node_modules \) -prune -o -type f -print | sed 's|^\./||' | icu_sort |
    while IFS= read -r f; do
      if [ "$2" = snapshot ]; then printf '%s\0' "$f"; cat -- "$f"; printf '\0'; else printf '%s' "$f"; cat -- "$f"; fi
    done) | sha256sum | cut -d' ' -f1
}
matches() { [ "$(skill_hash "$2" snapshot)" = "$1" ] || [ "$(skill_hash "$2" folder)" = "$1" ]; }

fail=0
warn() { printf 'skills-restore.sh: %s\n' "$1" >&2; fail=1; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
todo=""
while IFS=$u read -r name src ref dir hash; do
  [ -n "$name" ] || continue
  if ! [[ "$src" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || ! [[ "$ref" =~ ^([A-Za-z0-9._][A-Za-z0-9._/-]*)?$ ]] \
     || [[ "/$dir/" == */../* ]]; then
    warn "$name: unsafe source, ref or skillPath in skills-lock.json; skipped"; continue
  fi
  f="$(folder "$name")"
  [ -d "$dest/$f" ] && matches "$hash" "$dest/$f" && continue
  todo+="$name$u$f$u$src$u$ref$u$dir$u$hash"$'\n'
done <<< "$entries"

# One sparse, blobless clone per source and ref, checking out only the skill directories.
clone() { printf '%s/%s' "$tmp" "$(printf '%s@%s' "$1" "$2" | tr '/@' '__')"; }
while IFS=$u read -r src ref; do
  [ -n "$src" ] || continue
  r="$(clone "$src" "$ref")"; pats=()
  while IFS=$u read -r _ _ s rf d _; do
    [ "$s" = "$src" ] && [ "$rf" = "$ref" ] || continue
    if [ -n "$d" ]; then pats+=("/$d/"); else pats+=('/*'); fi
  done <<< "$todo"
  git clone -q --depth 1 --filter=blob:none --no-checkout ${ref:+--branch "$ref"} "$base/$src.git" "$r" 2>"$tmp/err" \
    && git -C "$r" sparse-checkout set --no-cone "${pats[@]}" 2>>"$tmp/err" && git -C "$r" checkout -q 2>>"$tmp/err" \
    || { warn "$src: download failed: $(head -1 "$tmp/err")"; rm -rf "$r"; }
done < <(printf '%s' "$todo" | cut -d"$u" -f3,4 | sort -u)

while IFS=$u read -r name f src ref dir hash; do
  [ -n "$name" ] || continue
  r="$(clone "$src" "$ref")"; [ -d "$r" ] || continue
  [ -f "$r/${dir:-.}/SKILL.md" ] || { warn "$name: $src has no ${dir:+$dir/}SKILL.md; not restored"; continue; }
  stage="$tmp/stage/$f"; mkdir -p "$tmp/stage"; cp -R "$r/${dir:-.}" "$stage"
  # The same files the CLI leaves out when it copies a skill.
  find "$stage" \( -type d \( -name .git -o -name __pycache__ -o -name __pypackages__ \) -o -type f -name metadata.json \) \
    -prune -exec rm -rf {} +
  if matches "$hash" "$stage"; then
    rm -rf "${dest:?}/$f"; mv "$stage" "$dest/$f"
  else
    if [ -d "$dest/$f" ]; then kept="kept the local copy"; else kept="not installed"; fi
    warn "$name: upstream $src no longer matches skills-lock.json; $kept. To take the new version, review it, run: npx skills add $src --skill '$name' -a claude-code -y, and commit skills-lock.json"
  fi
done <<< "$todo"

if [ "$fail" = 0 ]; then printf '%s\n' "$want" > "$stamp"; else rm -f "$stamp"; fi
exit "$fail"
