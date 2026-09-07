#!/usr/bin/env bash
# Tests for lib/install-claude-md.sh (and the install.sh wiring around it).
#
# Run:  bash tests/test-install-claude-md.sh
# Exits nonzero if anything fails. Touches only a scratch dir under tests/.
set -u

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MERGER="$REPO_ROOT/lib/install-claude-md.sh"
INSTALLER="$REPO_ROOT/install.sh"
ROOT="$(cd "$(dirname "$0")" && pwd)/.testrun"
rm -rf "$ROOT"
mkdir -p "$ROOT"

PASS=0
FAIL=0
pass() { PASS=$((PASS+1)); echo "  PASS: $*"; }
fail() { FAIL=$((FAIL+1)); echo "  FAIL: $*"; }
check() { if [ "$1" -eq 0 ]; then pass "$2"; else fail "$2"; fi; }

BEGIN='<!-- BEGIN managed: claude-skills -->'
END='<!-- END managed: claude-skills -->'

# Count marker lines the way the script does: exact match, ignoring one CR.
count_marker() {
    awk -v m="$2" '
        function stripcr(s) {
            if (length(s) > 0 && substr(s, length(s), 1) == "\r")
                return substr(s, 1, length(s) - 1)
            return s
        }
        { if (stripcr($0) == m) c++ }
        END { print c + 0 }
    ' "$1"
}

# Assert exactly one BEGIN and one END. This is the check that catches a
# silently dropped or silently duplicated block.
assert_one_marker_pair() { # file, label
    b=$(count_marker "$1" "$BEGIN")
    e=$(count_marker "$1" "$END")
    if [ "$b" -eq 1 ] && [ "$e" -eq 1 ]; then
        pass "$2: exactly one BEGIN and one END marker"
    else
        fail "$2: expected 1 BEGIN / 1 END, got $b / $e"
    fi
}

# Number of lines NOT ending in CR (0 means the whole file is CRLF).
count_lf_only_lines() {
    awk '{ if (length($0) == 0 || substr($0, length($0), 1) != "\r") c++ } END { print c + 0 }' "$1"
}

make_source() {
    cat > "$1" <<EOF
# Global user instructions

$BEGIN
> shipped preamble, version 1

## Rule A

Body of rule A.

## Rule B

Body of rule B.
$END
EOF
}

make_source_v2() {
    cat > "$1" <<EOF
# Global user instructions

$BEGIN
> shipped preamble, version 2

## Rule A

Body of rule A, revised.

## Rule B

Body of rule B.

## Rule C

Brand new rule C.
$END
EOF
}

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 1: target missing -> file created identical to source"
D="$ROOT/t1"; mkdir -p "$D/backups"
make_source "$D/src.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
[ -f "$D/CLAUDE.md" ]; check $? "target created"
cmp -s "$D/src.md" "$D/CLAUDE.md"; check $? "target byte-identical to source"
assert_one_marker_pair "$D/CLAUDE.md" "fresh install"
case "$out" in *"Installed CLAUDE.md"*) pass "reported 'Installed CLAUDE.md'";; *) fail "message was: $out";; esac

echo "TEST 1b: target missing, parent directory missing too"
D="$ROOT/t1b"; mkdir -p "$D"
make_source "$D/src.md"
out=$(bash "$MERGER" "$D/src.md" "$D/deep/nested/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
cmp -s "$D/src.md" "$D/deep/nested/CLAUDE.md"; check $? "parent dirs created, file written"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 2: target with markers + custom content above and below"
D="$ROOT/t2"; mkdir -p "$D/backups"
make_source "$D/src.md"
cat > "$D/CLAUDE.md" <<EOF
# Global user instructions

> my own preamble

## My note above	(tab kept)

Above content.

$BEGIN
> shipped preamble, version 1

## Rule A

OLD body of rule A.
$END

## My machine-specific note

  indented line
	tab-indented line

Trailing blank lines follow.


EOF
cp "$D/CLAUDE.md" "$D/before.md"
make_source_v2 "$D/src2.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
case "$out" in *"Updated managed block"*) pass "reported 'Updated managed block'";; *) fail "message was: $out";; esac
[ -f "$D/backups/CLAUDE.md" ]; check $? "backup written"
cmp -s "$D/before.md" "$D/backups/CLAUDE.md"; check $? "backup byte-identical to pre-merge target"
assert_one_marker_pair "$D/CLAUDE.md" "replace"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$D/CLAUDE.md" > "$D/got-block"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$D/src2.md" > "$D/want-block"
diff "$D/got-block" "$D/want-block" >/dev/null; check $? "managed block replaced with source block"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} !f{print} $0==e{f=0}' "$D/before.md" > "$D/surr-before"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} !f{print} $0==e{f=0}' "$D/CLAUDE.md" > "$D/surr-after"
diff "$D/surr-before" "$D/surr-after" >/dev/null; check $? "all non-managed lines preserved byte-for-byte"
if grep -q "OLD body of rule A" "$D/CLAUDE.md"; then fail "old block content still present"; else pass "old block content gone"; fi
if grep -q "shipped preamble, version 2" "$D/CLAUDE.md"; then pass "shipped preamble updated in place"; else fail "shipped preamble not updated"; fi

echo "TEST 3 (was 5): idempotence — rerun of TEST 2"
cp "$D/CLAUDE.md" "$D/after-first.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
cmp -s "$D/after-first.md" "$D/CLAUDE.md"; check $? "target unchanged on second run"
case "$out" in *"already up to date"*) pass "reported 'already up to date'";; *) fail "message was: $out";; esac

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 4: target with no markers -> block appended, original preserved"
D="$ROOT/t4"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# My own file\n\nSome content.\n\n## A section\n\nMore.\n' > "$D/CLAUDE.md"
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
case "$out" in *"Appended managed block"*) pass "reported 'Appended managed block'";; *) fail "message was: $out";; esac
[ -f "$D/backups/CLAUDE.md" ]; check $? "backup written"
assert_one_marker_pair "$D/CLAUDE.md" "append"
n=$(awk 'END{print NR}' "$D/before.md")
head -n "$n" "$D/CLAUDE.md" > "$D/prefix"
diff "$D/before.md" "$D/prefix" >/dev/null; check $? "original content preserved byte-for-byte as prefix"
if [ "$(sed -n "$((n+1))p" "$D/CLAUDE.md")" = "" ]; then pass "blank line separates original from block"; else fail "no blank separator"; fi
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$D/CLAUDE.md" > "$D/got-block"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} f{print} $0==e{f=0}' "$D/src.md" > "$D/want-block"
diff "$D/got-block" "$D/want-block" >/dev/null; check $? "appended block matches source block"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 5: malformed target -> untouched, .new written, exit 0"
for variant in two-begin end-before-begin begin-only end-only; do
    D="$ROOT/t5-$variant"; mkdir -p "$D/backups"
    make_source "$D/src.md"
    case "$variant" in
        two-begin)        printf '# Mine\n\n%s\nstuff\n%s\n\n%s\nmore\n%s\n' "$BEGIN" "$END" "$BEGIN" "$END" > "$D/CLAUDE.md" ;;
        end-before-begin) printf '# Mine\n\n%s\nstuff\n%s\n' "$END" "$BEGIN" > "$D/CLAUDE.md" ;;
        begin-only)       printf '# Mine\n\n%s\nstuff\n' "$BEGIN" > "$D/CLAUDE.md" ;;
        end-only)         printf '# Mine\n\nstuff\n%s\n' "$END" > "$D/CLAUDE.md" ;;
    esac
    cp "$D/CLAUDE.md" "$D/before.md"
    out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
    check $rc "$variant: exit code 0 (got $rc)"
    cmp -s "$D/before.md" "$D/CLAUDE.md"; check $? "$variant: target unchanged byte-for-byte"
    [ -f "$D/CLAUDE.md.new" ]; check $? "$variant: .new file written"
    cmp -s "$D/src.md" "$D/CLAUDE.md.new"; check $? "$variant: .new is a copy of the source"
    [ ! -f "$D/backups/CLAUDE.md" ]; check $? "$variant: no pointless backup taken"
done
case "$out" in *"malformed"*) pass "warned about malformed markers";; *) fail "message was: $out";; esac
case "$out" in *'diff "'*'CLAUDE.md" "'*'CLAUDE.md.new"'*) pass "printed the exact diff command";; *) fail "no usable diff hint in: $out";; esac

echo "TEST 5b: an in-progress hand merge in .new is not clobbered"
D="$ROOT/t5b"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# Mine\n\n%s\nstuff\n%s\n\n%s\nmore\n%s\n' "$BEGIN" "$END" "$BEGIN" "$END" > "$D/CLAUDE.md"
printf 'my half-finished hand merge\n' > "$D/CLAUDE.md.new"
cp "$D/CLAUDE.md.new" "$D/new-before"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
cmp -s "$D/new-before" "$D/CLAUDE.md.new"; check $? "existing .new left untouched"
case "$out" in *"merge in progress"*) pass "warned that a merge looks in progress";; *) fail "message was: $out";; esac

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 6: target without trailing newline, no markers -> clean append"
D="$ROOT/t6"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# My own file\n\nLast line has no newline' > "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
grep -q '^Last line has no newline$' "$D/CLAUDE.md"; check $? "final original line intact on its own line"
if grep -q 'no newline<!-- BEGIN' "$D/CLAUDE.md"; then fail "lines ran together"; else pass "no run-together line"; fi
if [ "$(sed -n '4p' "$D/CLAUDE.md")" = "" ]; then pass "blank separator line present"; else fail "line 4 not blank"; fi
if [ "$(sed -n '5p' "$D/CLAUDE.md")" = "$BEGIN" ]; then pass "BEGIN marker on line 5"; else fail "BEGIN not on line 5"; fi
printf '# My own file\n\nLast line has no newline\n' > "$D/expected-prefix"
head -n 3 "$D/CLAUDE.md" > "$D/got-prefix"
diff "$D/expected-prefix" "$D/got-prefix" >/dev/null; check $? "original content preserved as prefix"
assert_one_marker_pair "$D/CLAUDE.md" "append, no trailing newline"

echo "TEST 6b: target without trailing newline, WITH markers above the tail"
D="$ROOT/t6b"; mkdir -p "$D/backups"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
printf '# Mine\n\n%s\n## Rule A\n\nOLD.\n%s\n\ntail with no newline' "$BEGIN" "$END" > "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
[ -n "$(tail -c 1 "$D/CLAUDE.md")" ]; check $? "missing trailing newline preserved"
tail -n 1 "$D/CLAUDE.md" | grep -q '^tail with no newline$'; check $? "tail line intact"
grep -q 'Brand new rule C' "$D/CLAUDE.md"; check $? "new block content present"
assert_one_marker_pair "$D/CLAUDE.md" "replace, no trailing newline"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 7: malformed SOURCE -> nonzero exit, target untouched"
D="$ROOT/t7"; mkdir -p "$D/backups"
printf '# Src\n\n%s\nblock\n%s\n\n%s\nagain\n%s\n' "$BEGIN" "$END" "$BEGIN" "$END" > "$D/src.md"
printf '# Mine\n\nuntouched\n' > "$D/CLAUDE.md"
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
[ "$rc" -ne 0 ]; check $? "nonzero exit (got $rc)"
cmp -s "$D/before.md" "$D/CLAUDE.md"; check $? "target untouched"
[ ! -f "$D/CLAUDE.md.new" ]; check $? "no .new written for a bad source"

echo "TEST 7b: source with END before BEGIN -> nonzero exit"
D="$ROOT/t7b"; mkdir -p "$D/backups"
printf '# Src\n\n%s\nblock\n%s\n' "$END" "$BEGIN" > "$D/src.md"
printf '# Mine\n\nuntouched\n' > "$D/CLAUDE.md"
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
[ "$rc" -ne 0 ]; check $? "nonzero exit (got $rc)"
cmp -s "$D/before.md" "$D/CLAUDE.md"; check $? "target untouched"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 8: marker text quoted unindented inside a fenced code block"
D="$ROOT/t8"; mkdir -p "$D/backups"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cat > "$D/CLAUDE.md" <<EOF
# Global user instructions

\`\`\`markdown
$BEGIN
example of what the block looks like
$END
\`\`\`

$BEGIN
## Rule A

OLD body.
$END
EOF
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
# Those fenced lines are genuine whole-line matches, so the file really is
# ambiguous. Refusing is the correct call.
[ "$rc" -eq 0 ]; check $? "exit code 0 (got $rc)"
cmp -s "$D/before.md" "$D/CLAUDE.md"; check $? "ambiguous target left untouched"
[ -f "$D/CLAUDE.md.new" ]; check $? ".new written for manual merge"

echo "TEST 8b: marker text as substring / indented, never as a bare line"
D="$ROOT/t8b"; mkdir -p "$D/backups"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cat > "$D/CLAUDE.md" <<EOF
# Global user instructions

Prose: we wrap the rules in \`$BEGIN\` and \`$END\` marker lines.

Indented (four spaces, so not a bare line):
    $BEGIN
    $END

$BEGIN
## Rule A

OLD body.
$END

Trailing prose mentioning $END inline at the end of a sentence.
EOF
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
case "$out" in *"Updated managed block"*) pass "reported 'Updated managed block'";; *) fail "message was: $out";; esac
grep -q 'Brand new rule C' "$D/CLAUDE.md"; check $? "real block was replaced"
grep -q 'we wrap the rules in' "$D/CLAUDE.md"; check $? "prose mention preserved"
grep -q '^    <!-- BEGIN managed: claude-skills -->$' "$D/CLAUDE.md"; check $? "indented mention preserved verbatim"
grep -q 'Trailing prose mentioning' "$D/CLAUDE.md"; check $? "trailing prose preserved"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} !f{print} $0==e{f=0}' "$D/before.md" > "$D/surr-before"
awk -v b="$BEGIN" -v e="$END" '$0==b{f=1} !f{print} $0==e{f=0}' "$D/CLAUDE.md" > "$D/surr-after"
diff "$D/surr-before" "$D/surr-after" >/dev/null; check $? "all non-managed lines byte-for-byte identical"

echo "TEST 8c: marker hidden behind trailing whitespace -> refuse, do not append"
D="$ROOT/t8c"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# Mine\n\n%s  \nstuff\n%s\t\n' "$BEGIN" "$END" > "$D/CLAUDE.md"
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
cmp -s "$D/before.md" "$D/CLAUDE.md"; check $? "target unchanged (no second block appended)"
[ -f "$D/CLAUDE.md.new" ]; check $? ".new written"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 9: CRLF target with an existing block (Git Bash / Windows)"
D="$ROOT/t9"; mkdir -p "$D/backups"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
printf '# Mine\r\n\r\n%s\r\n> shipped preamble, version 1\r\n\r\n## Rule A\r\n\r\nOLD body.\r\n%s\r\n\r\n## My tail note\r\n\r\nkeep me\r\n' \
    "$BEGIN" "$END" > "$D/CLAUDE.md"
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
case "$out" in *"Updated managed block"*) pass "took the replace path (not append)";; *) fail "message was: $out";; esac
assert_one_marker_pair "$D/CLAUDE.md" "CRLF replace"
lf=$(count_lf_only_lines "$D/CLAUDE.md")
if [ "$lf" -eq 0 ]; then pass "every line still ends CRLF (no mixed endings)"; else fail "$lf lines lost their CR"; fi
grep -q 'Brand new rule C' "$D/CLAUDE.md"; check $? "new block content present"
if grep -q 'OLD body' "$D/CLAUDE.md"; then fail "stale block still present"; else pass "stale block replaced, not duplicated"; fi
grep -q 'keep me' "$D/CLAUDE.md"; check $? "content after the block preserved"

echo "TEST 9b: CRLF target, second run is a no-op (no permanent stale duplicate)"
cp "$D/CLAUDE.md" "$D/after-first.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
cmp -s "$D/after-first.md" "$D/CLAUDE.md"; check $? "unchanged on second run"
case "$out" in *"already up to date"*) pass "reported 'already up to date'";; *) fail "message was: $out";; esac
assert_one_marker_pair "$D/CLAUDE.md" "CRLF, second run"

echo "TEST 9c: CRLF target with no markers -> append in CRLF"
D="$ROOT/t9c"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# Mine\r\n\r\nMy own notes.\r\n' > "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
assert_one_marker_pair "$D/CLAUDE.md" "CRLF append"
lf=$(count_lf_only_lines "$D/CLAUDE.md")
if [ "$lf" -eq 0 ]; then pass "appended block written in CRLF too"; else fail "$lf lines are LF-only"; fi
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
case "$out" in *"already up to date"*) pass "rerun is a no-op";; *) fail "rerun message was: $out";; esac
assert_one_marker_pair "$D/CLAUDE.md" "CRLF append, rerun"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 10: symlinked target (dotfiles repo)"
D="$ROOT/t10"; mkdir -p "$D/backups" "$D/dotfiles" "$D/home"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cp "$D/src.md" "$D/dotfiles/CLAUDE.md"
printf '\n## Local extras\n\nkeep me\n' >> "$D/dotfiles/CLAUDE.md"
ln -s "$D/dotfiles/CLAUDE.md" "$D/home/CLAUDE.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/home/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
[ -L "$D/home/CLAUDE.md" ]; check $? "symlink survived (still a symlink)"
[ "$(readlink "$D/home/CLAUDE.md")" = "$D/dotfiles/CLAUDE.md" ]; check $? "symlink still points at the same file"
grep -q 'Brand new rule C' "$D/dotfiles/CLAUDE.md"; check $? "real file behind the link was updated"
grep -q 'keep me' "$D/dotfiles/CLAUDE.md"; check $? "user content in the real file preserved"
assert_one_marker_pair "$D/dotfiles/CLAUDE.md" "symlink target"
[ -f "$D/backups/CLAUDE.md" ]; check $? "backup written"
[ ! -e "$D/home/CLAUDE.md.claude-skills.tmp.$$" ]; check $? "no temp file left beside the link"

echo "TEST 9d: mostly-LF file with one stray CRLF line -> append stays LF"
D="$ROOT/t9d"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# Mine\n\nplain line\na line pasted from Windows\r\nanother plain line\n' > "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
assert_one_marker_pair "$D/CLAUDE.md" "mixed-endings append"
# The one pre-existing CRLF line stays; the appended block must not add more.
cr=$(awk '{ if (length($0) > 0 && substr($0, length($0), 1) == "\r") c++ } END { print c + 0 }' "$D/CLAUDE.md")
if [ "$cr" -eq 1 ]; then pass "block appended in LF; the single stray CR line is the only one"; else fail "expected 1 CR line, found $cr"; fi
grep -q 'a line pasted from Windows' "$D/CLAUDE.md"; check $? "stray line preserved"

echo "TEST 9e: mostly-CRLF file with one stray LF line -> append stays CRLF"
D="$ROOT/t9e"; mkdir -p "$D/backups"
make_source "$D/src.md"
printf '# Mine\r\n\r\nline one\r\na stray unix line\nline three\r\n' > "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
lf=$(count_lf_only_lines "$D/CLAUDE.md")
if [ "$lf" -eq 1 ]; then pass "block appended in CRLF; the single stray LF line is the only one"; else fail "expected 1 LF-only line, found $lf"; fi

echo "TEST 10b: two-hop symlink chain"
D="$ROOT/t10b"; mkdir -p "$D/backups"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cp "$D/src.md" "$D/real.md"
ln -s "$D/real.md" "$D/hop1.md"
ln -s "$D/hop1.md" "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
[ -L "$D/CLAUDE.md" ] && [ -L "$D/hop1.md" ]; check $? "both links survived"
grep -q 'Brand new rule C' "$D/real.md"; check $? "the real file at the end of the chain was updated"

echo "TEST 10d: symlink through ../ hops -> INFO line shows a tidy path"
D="$ROOT/t10d"; mkdir -p "$D/backups" "$D/a" "$D/b" "$D/c"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cp "$D/src.md" "$D/c/real.md"
ln -s "$D/a/../b/../c/real.md" "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
grep -q 'Brand new rule C' "$D/c/real.md"; check $? "real file updated through the ../ hops"
case "$out" in *".."*) fail "INFO line still shows ../ hops: $out";; *) pass "INFO line shows a normalised path";; esac
case "$out" in *"$D/c/real.md"*) pass "INFO line names the real file";; *) fail "INFO line was: $out";; esac

echo "TEST 10e: a plain (non-symlink) target is not announced as a symlink"
D="$ROOT/t10e"; mkdir -p "$D/backups"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cp "$D/src.md" "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
case "$out" in *"is a symlink"*) fail "plain file wrongly announced as a symlink: $out";; *) pass "no spurious symlink message";; esac

echo "TEST 10f: read-only directory -> honest error, target untouched"
D="$ROOT/t10f"; mkdir -p "$D/backups" "$D/ro"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cp "$D/src.md" "$D/ro/CLAUDE.md"
cp "$D/ro/CLAUDE.md" "$D/before.md"
chmod a-w "$D/ro"
out=$(bash "$MERGER" "$D/src2.md" "$D/ro/CLAUDE.md" "$D/backups" 2>&1); rc=$?
chmod u+w "$D/ro"
[ "$rc" -ne 0 ]; check $? "nonzero exit (got $rc)"
cmp -s "$D/before.md" "$D/ro/CLAUDE.md"; check $? "target untouched"
case "$out" in *"writable"*) pass "error blames the unwritable directory";; *) fail "message was: $out";; esac
case "$out" in *"Could not read the managed block"*) fail "error misattributes the cause to the block read";; *) pass "does not misattribute the cause";; esac

echo "TEST 10c: broken symlink -> nothing written, exit 0"
D="$ROOT/t10c"; mkdir -p "$D/backups"
make_source "$D/src.md"
ln -s "$D/nowhere/CLAUDE.md" "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src.md" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
[ ! -d "$D/nowhere" ]; check $? "did not create the link's dangling destination"
[ -L "$D/CLAUDE.md" ] && [ ! -e "$D/CLAUDE.md" ]; check $? "broken link left as it was"
case "$out" in *"broken symlink"*) pass "warned about the broken symlink";; *) fail "message was: $out";; esac

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 11: real repo source, fresh target then a machine-specific tail"
D="$ROOT/t11"; mkdir -p "$D/backups"
REAL_SRC="$REPO_ROOT/claude-config/CLAUDE.md"
out=$(bash "$MERGER" "$REAL_SRC" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "fresh install exit 0 (got $rc)"
cmp -s "$REAL_SRC" "$D/CLAUDE.md"; check $? "fresh install matches repo source"
assert_one_marker_pair "$D/CLAUDE.md" "repo source, fresh install"
printf '\n## Machine-specific: this laptop only\n\nUse the local GPU.\n' >> "$D/CLAUDE.md"
cp "$D/CLAUDE.md" "$D/before.md"
out=$(bash "$MERGER" "$REAL_SRC" "$D/CLAUDE.md" "$D/backups" 2>&1); rc=$?
check $rc "re-run exit 0 (got $rc)"
case "$out" in *"already up to date"*) pass "no-op reported as up to date";; *) fail "message was: $out";; esac
cmp -s "$D/before.md" "$D/CLAUDE.md"; check $? "machine-specific tail untouched"

echo "TEST 11b: repo source ships the preamble INSIDE the managed block"
b_line=$(awk -v m="$BEGIN" '$0==m{print NR; exit}' "$REAL_SRC")
e_line=$(awk -v m="$END" '$0==m{print NR; exit}' "$REAL_SRC")
p_line=$(awk '/^> /{print NR; exit}' "$REAL_SRC")
if [ -n "$p_line" ] && [ "$p_line" -gt "$b_line" ] && [ "$p_line" -lt "$e_line" ]; then
    pass "preamble sits inside the markers (so it stays correctable)"
else
    fail "preamble at line ${p_line:-none}, markers at $b_line/$e_line"
fi
if [ "$(awk 'NR==1' "$REAL_SRC")" = "# Global user instructions" ]; then
    pass "heading stays outside as the file title"
else
    fail "first line is not the heading"
fi

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 12: backup dir does not exist yet"
D="$ROOT/t12"; mkdir -p "$D"
make_source "$D/src.md"; make_source_v2 "$D/src2.md"
cp "$D/src.md" "$D/CLAUDE.md"
out=$(bash "$MERGER" "$D/src2.md" "$D/CLAUDE.md" "$D/does/not/exist" 2>&1); rc=$?
check $rc "exit code 0 (got $rc)"
[ -f "$D/does/not/exist/CLAUDE.md" ]; check $? "backup dir created and backup written"

echo "TEST 13: bad usage / missing source"
out=$(bash "$MERGER" only-one-arg 2>&1); rc=$?
[ "$rc" -ne 0 ]; check $? "wrong arg count exits nonzero (got $rc)"
out=$(bash "$MERGER" "$ROOT/nope.md" "$ROOT/t13.md" "$ROOT/bk" 2>&1); rc=$?
[ "$rc" -ne 0 ]; check $? "missing source exits nonzero (got $rc)"
[ ! -f "$ROOT/t13.md" ]; check $? "nothing written when the source is missing"

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 14: install.sh wiring"
bash -n "$INSTALLER" >/dev/null 2>&1; check $? "install.sh is syntactically valid"
bash -n "$MERGER" >/dev/null 2>&1; check $? "install-claude-md.sh is syntactically valid"
[ -x "$MERGER" ]; check $? "merge script is executable"
# The two `for file in ...` loops, in file order: the first backs up, the
# second copies. CLAUDE.md must be in the first and absent from the second.
backup_loop=$(grep -n '^ *for file in ' "$INSTALLER" | sed -n '1p')
copy_loop=$(grep -n '^ *for file in ' "$INSTALLER" | sed -n '2p')
case "$backup_loop" in *CLAUDE.md*) pass "CLAUDE.md is in the backup loop";; *) fail "backup loop: $backup_loop";; esac
case "$copy_loop" in *CLAUDE.md*) fail "CLAUDE.md must NOT be in the copy loop: $copy_loop";; *) pass "CLAUDE.md is not in the copy loop";; esac
if [ "$(grep -c '^ *for file in ' "$INSTALLER")" -eq 2 ]; then
    pass "exactly two 'for file in' loops (the assertion above targets the right ones)"
else
    fail "expected 2 'for file in' loops, found $(grep -c '^ *for file in ' "$INSTALLER")"
fi
grep -q 'lib/install-claude-md.sh' "$INSTALLER"; check $? "install.sh invokes lib/install-claude-md.sh"
grep -q 'SCRIPT_DIR/lib/install-claude-md.sh' "$INSTALLER"; check $? "helper resolved via \$SCRIPT_DIR"
grep -q 'Merge helper not found' "$INSTALLER"; check $? "warns instead of aborting when the helper is missing"
grep -q 'in the repo. Skipped the CLAUDE.md merge' "$INSTALLER"; check $? "warns when the repo source is missing"
if grep -n 'install-claude-md.sh' "$INSTALLER" | grep -q '^[0-9]*:.*'; then
    merge_line=$(grep -n 'bash "\$CLAUDE_MD_MERGER"' "$INSTALLER" | cut -d: -f1)
    copy_line=$(echo "$copy_loop" | cut -d: -f1)
    if [ -n "$merge_line" ] && [ "$merge_line" -gt "$copy_line" ]; then
        pass "merge runs after the top-level copy loop"
    else
        fail "merge at line ${merge_line:-none}, copy loop at $copy_line"
    fi
fi

# ─────────────────────────────────────────────────────────────────────────────
echo "TEST 15: no temp files left behind by any path"
leftovers=$(find "$ROOT" -name '*.claude-skills.tmp.*' -o -name '*.trimmed' 2>/dev/null)
if [ -z "$leftovers" ]; then pass "no *.tmp.* or *.trimmed files anywhere under the test root"; else fail "leftovers: $leftovers"; fi

echo ""
echo "======================================"
echo "PASSED: $PASS   FAILED: $FAIL"
echo "======================================"
[ "$FAIL" -eq 0 ]
