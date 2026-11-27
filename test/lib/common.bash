# Shared by test/run and the release tools (bin/release/faults, repeat, trust-report). Needs HERE (test/) and REPO.

RESULTS="$HERE/results"

scratch() { # sets WORK_EXTRA to a new scratch folder; the caller's EXIT trap removes it
  WORK_EXTRA="$(mktemp -d "${TMPDIR:-/tmp}/test-trust.XXXXXX")" || { echo "no scratch folder" >&2; exit 2; }
  # the real path: on macOS TMPDIR is behind a symlink, and a clone must see one spelling of its own folder
  WORK_EXTRA="$(cd "$WORK_EXTRA" && pwd -P)"
}

stamp() { # <now in ET> on <os>, commit <c>
  local c
  c="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  [ -z "$(git -C "$REPO" status --porcelain 2>/dev/null | grep -v ' test/results/\| TESTING.md\| README.md')" ] || c="$c with uncommitted changes"
  echo "$(TZ=America/New_York date '+%Y-%m-%d %I:%M %p ET') on $(uname -s), commit $c"
}

# has_tag <file> <tag>: the file carries the tag (a bats tag line, or `# <tag>` in a pytest file)
has_tag() { grep -qE "^[[:space:]]*#[[:space:]]*(bats[[:space:]]+(file|test)_tags=(.*,)?[[:space:]]*)?$2([[:space:],]|\$)" "$1"; }

# the ids of test/features.txt
feature_ids() { sed -n 's/^[[:space:]]*\([a-z0-9-][a-z0-9-]*\)[[:space:]]*|.*/\1/p' "$HERE/features.txt"; }

# every test file: the .bats files of the three tiers and the pytest files (a name starting with `_` is not a test)
test_files() {
  local f
  for f in "$HERE"/quick/*.bats "$HERE"/machine/*.bats "$HERE"/docker/*.bats \
           "$REPO"/skills/*/tests/test_*.py "$REPO"/hooks/*/tests/test_*.py "$REPO"/helper-mcp/tests/test_*.py "$REPO"/assistant/tests/test_*.py; do
    [ -f "$f" ] || continue
    case "$(basename "$f")" in _*) continue ;; esac
    printf '%s\n' "$f"
  done
}

# tags_of <kind>: the distinct `<kind>:<id>` tags on the bats files (escape, standin)
tags_of() {
  grep -hE '^[[:space:]]*#[[:space:]]*bats[[:space:]]+(file|test)_tags=' "$HERE"/quick/*.bats "$HERE"/machine/*.bats "$HERE"/docker/*.bats /dev/null 2>/dev/null |
    grep -oE "$1:[A-Za-z0-9_-]+" | sort -u
}

# shuffle <seed>: stdin lines in an order that depends only on the seed and the lines
# (not awk's srand: Ubuntu's mawk gives a different order for the same seed)
shuffle() {
  python3 -c '
import hashlib, sys
lines = sys.stdin.buffer.read().splitlines()
lines.sort(key=lambda l: hashlib.sha256(sys.argv[1].encode() + b" " + l).digest())
sys.stdout.buffer.write(b"".join(l + b"\n" for l in lines))' "$1"
}
