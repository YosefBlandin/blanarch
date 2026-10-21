#!/bin/sh
# Blocks commits that add company-specific strings. The list is the main checkout's git-ignored
# private/company-strings.txt (one string per line, case-insensitive, # for comments), found through git's
# common directory so every worktree uses it. Prints counts only, never the strings.
# Usage: forbidden-scan.sh staged            (pre-commit: staged added lines and file names)
#        forbidden-scan.sh message <file>    (commit-msg: the commit message)
mode=$1
case $mode in
  staged) name=pre-commit ;;
  message) name=commit-msg ;;
  *) echo "forbidden-scan.sh: unknown mode '$mode'" >&2; exit 1 ;;
esac

common=$(git rev-parse --path-format=absolute --git-common-dir) || exit 1
list="$(cd "$common/.." && pwd)/private/company-strings.txt"

patterns=$(mktemp) || exit 1
text=$(mktemp) || exit 1
trap 'rm -f "$patterns" "$text"' EXIT
# Comments and blank lines are skipped; trailing spaces and CR are trimmed.
filter="grep -v '^#' | sed 's/[[:space:]]*\$//; /^\$/d'"
[ -f "$list" ] && eval "$filter" < "$list" > "$patterns"
if [ ! -s "$patterns" ]; then
  if [ "${SKIP_FORBIDDEN_CHECK:-}" = 1 ]; then
    echo "$name: warning: no forbidden word list at $list. Skipping the check (SKIP_FORBIDDEN_CHECK=1)." >&2
    exit 0
  fi
  echo "$name: blocked. The forbidden word list is missing or empty." >&2
  echo "Expected it at: $list" >&2
  echo "If you have no list, commit with SKIP_FORBIDDEN_CHECK=1 to skip this check." >&2
  exit 1
fi

failed() {
  echo "$name: blocked. The scan failed." >&2
  exit 1
}

if [ "$mode" = staged ]; then
  git -c core.quotePath=false diff --cached --name-only --diff-filter=ACMRT > "$text" || failed
  git diff --cached -U0 --text --no-color --no-ext-diff --diff-filter=ACMRT > "$text.diff" || {
    rm -f "$text.diff"
    failed
  }
  # awk stops at a NUL byte, so drop NULs from binary content first.
  tr -d '\000' < "$text.diff" |
    awk '/^diff --git /{h=0; next} /^@@/{h=1; next} h && /^\+/{print substr($0, 2)}' >> "$text"
  rm -f "$text.diff"
  what="added line(s) or file name(s)"
  source="git diff --cached --text"
else
  # Keep # lines: with -m or -F git commits them as written. Only the --verbose diff below the scissors line
  # is dropped, since git strips it too.
  sed '/^# -* >8 -*$/,$d' "$2" > "$text" || failed
  what="line(s) of the commit message"
  source="cat '$2'"
fi

hits=$(grep -aicF -f "$patterns" "$text")
case $hits in
  '' | *[!0-9]*) failed ;;
esac
if [ "$hits" -gt 0 ]; then
  echo "$name: $hits $what contain strings from the forbidden word list." >&2
  echo "Find them with: $source | grep -inF -f <(< '$list' $filter)" >&2
  exit 1
fi
exit 0
