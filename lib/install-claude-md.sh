#!/usr/bin/env bash
# install-claude-md.sh — merge the managed block of CLAUDE.md into a target file.
#
# Usage: install-claude-md.sh <source> <target> <backup-dir>
#
# The source file must contain exactly one BEGIN marker line and exactly one
# END marker line, in that order. Everything between them (inclusive) is the
# "managed block". Only that block is ever written into the target; anything
# else already in the target is preserved byte-for-byte.
#
# Notes on the awkward cases this handles:
#   - CRLF targets (Git Bash / a Windows-authored file): markers are matched
#     ignoring a trailing CR, and the block is written back with whatever line
#     ending the target already uses, so the merge never introduces a mix.
#   - Symlinked targets (a dotfiles repo): the link chain is resolved and the
#     real file is rewritten, so the link survives.
#   - Damaged or duplicated markers: the target is left alone and a .new file
#     is written for a hand merge.
#
# Portability: POSIX shell constructs + awk only. No `sed -i`, no `mapfile`,
# no `grep -P`. Must work with BSD awk (macOS) and Git Bash on Windows.

set -eu

BEGIN_MARKER='<!-- BEGIN managed: claude-skills -->'
END_MARKER='<!-- END managed: claude-skills -->'

# ─── Output helpers (mirror install.sh's style) ──────────────────────────────

_GREEN='\033[0;32m'
_YELLOW='\033[1;33m'
_BLUE='\033[0;34m'
_RED='\033[0;31m'
_NC='\033[0m'

info()  { printf "${_BLUE}[INFO]${_NC}  %s\n" "$*"; }
ok()    { printf "${_GREEN}[OK]${_NC}    %s\n" "$*"; }
warn()  { printf "${_YELLOW}[WARN]${_NC}  %s\n" "$*"; }
error() { printf "${_RED}[ERROR]${_NC} %s\n" "$*" >&2; }

# ─── awk helpers ─────────────────────────────────────────────────────────────
#
# Shared awk function text. Trailing-CR stripping and whitespace stripping are
# written with substr() rather than regex escapes so they behave the same on
# gawk, mawk and BSD awk.

AWK_FUNCS='
function stripcr(s) {
    if (length(s) > 0 && substr(s, length(s), 1) == "\r")
        return substr(s, 1, length(s) - 1)
    return s
}
function rstrip(s,   c) {
    while (length(s) > 0) {
        c = substr(s, length(s), 1)
        if (c == " " || c == "\t" || c == "\r")
            s = substr(s, 1, length(s) - 1)
        else
            break
    }
    return s
}
'

# Count lines equal to the marker, ignoring a trailing CR.
count_marker() {
    awk -v m="$2" "$AWK_FUNCS"'
        { if (stripcr($0) == m) c++ }
        END { print c + 0 }
    ' "$1"
}

# Line number of the first such line, or 0 if absent.
find_marker() {
    awk -v m="$2" "$AWK_FUNCS"'
        { if (!found && stripcr($0) == m) { n = NR; found = 1 } }
        END { print n + 0 }
    ' "$1"
}

# Exit 0 when the first line matching the marker carried a trailing CR.
marker_line_is_crlf() {
    awk -v m="$2" "$AWK_FUNCS"'
        {
            if (stripcr($0) == m) {
                cr = (length($0) > 0 && substr($0, length($0), 1) == "\r")
                exit
            }
        }
        END { exit(cr ? 0 : 1) }
    ' "$1"
}

# Exit 0 when most of the file's lines end with CR. Deliberately a majority
# test, not a first-hit one: a single pasted CRLF line in an otherwise LF file
# should not make us append a CRLF block.
file_is_crlf() {
    awk '
        { total++; if (length($0) > 0 && substr($0, length($0), 1) == "\r") cr++ }
        END { exit((total > 0 && cr * 2 > total) ? 0 : 1) }
    ' "$1"
}

# Exit 0 when any line looks like a marker once trailing whitespace/CR is
# stripped. Used as a belt-and-braces guard before appending.
has_looselike_marker() {
    awk -v b="$BEGIN_MARKER" -v e="$END_MARKER" "$AWK_FUNCS"'
        { t = rstrip($0); if (t == b || t == e) { f = 1; exit } }
        END { exit(f ? 0 : 1) }
    ' "$1"
}

line_count() {
    awk 'END { print NR + 0 }' "$1"
}

# True when the file is non-empty and its last byte is not a newline.
# `$(...)` strips trailing newlines, so a file ending in "\n" yields "".
lacks_final_newline() {
    [ -s "$1" ] || return 1
    [ -n "$(tail -c 1 "$1")" ]
}

# Follow a symlink chain to the real path. Plain `readlink` (no -f) is used
# because BSD readlink has no -f.
resolve_symlink() {
    _rs_path="$1"
    _rs_hops=0
    while [ -L "$_rs_path" ]; do
        _rs_hops=$((_rs_hops + 1))
        if [ "$_rs_hops" -gt 40 ]; then
            error "Too many levels of symbolic links at: $1"
            return 1
        fi
        _rs_link=$(readlink "$_rs_path")
        case "$_rs_link" in
            /*) _rs_path="$_rs_link" ;;
            *)  _rs_path="$(dirname "$_rs_path")/$_rs_link" ;;
        esac
    done
    # Tidy the result so messages don't show a path full of ../ hops. The file
    # itself is never followed here — only its directory is normalised, and
    # only when that directory already exists.
    _rs_dir=$(dirname "$_rs_path")
    _rs_base=$(basename "$_rs_path")
    if [ -d "$_rs_dir" ]; then
        _rs_dir=$(cd "$_rs_dir" 2>/dev/null && pwd -P) || _rs_dir=$(dirname "$_rs_path")
    fi
    case "$_rs_dir" in
        */) printf '%s%s\n' "$_rs_dir" "$_rs_base" ;;
        *)  printf '%s/%s\n' "$_rs_dir" "$_rs_base" ;;
    esac
}

usage() {
    error "Usage: $0 <source-CLAUDE.md> <target-CLAUDE.md> <backup-dir>"
}

cleanup() {
    if [ -n "${TMPDIR_WORK:-}" ]; then
        rm -rf "$TMPDIR_WORK"
    fi
    if [ -n "${NEWFILE:-}" ]; then
        rm -f "$NEWFILE" "$NEWFILE.trimmed"
    fi
    return 0
}

# ─── Argument handling ───────────────────────────────────────────────────────

if [ "$#" -ne 3 ]; then
    usage
    exit 2
fi

SRC="$1"
TARGET="$2"
BACKUP_DIR="$3"

if [ ! -f "$SRC" ]; then
    error "Source CLAUDE.md not found: $SRC"
    exit 1
fi

# ─── Validate the source (a bad source is a repo bug — fail loudly) ──────────

src_begin_count=$(count_marker "$SRC" "$BEGIN_MARKER")
src_end_count=$(count_marker "$SRC" "$END_MARKER")

if [ "$src_begin_count" -ne 1 ] || [ "$src_end_count" -ne 1 ]; then
    error "Source $SRC has $src_begin_count BEGIN and $src_end_count END markers; expected exactly one of each."
    exit 1
fi

src_begin=$(find_marker "$SRC" "$BEGIN_MARKER")
src_end=$(find_marker "$SRC" "$END_MARKER")

if [ "$src_begin" -ge "$src_end" ]; then
    error "Source $SRC has its END marker at line $src_end before/at its BEGIN marker at line $src_begin."
    exit 1
fi

# ─── Extract the managed block ───────────────────────────────────────────────

TMPDIR_WORK=$(mktemp -d 2>/dev/null || mktemp -d -t claudemd)
NEWFILE=""
trap 'cleanup' EXIT
trap 'cleanup; trap - INT; kill -INT $$' INT
trap 'cleanup; trap - TERM; kill -TERM $$' TERM

BLOCK="$TMPDIR_WORK/block"

awk -v b="$src_begin" -v e="$src_end" 'NR >= b && NR <= e { print }' "$SRC" > "$BLOCK"

if [ ! -s "$BLOCK" ]; then
    error "Failed to extract the managed block from $SRC"
    exit 1
fi

# ─── Resolve the target through any symlinks ─────────────────────────────────

if [ -L "$TARGET" ] && [ ! -e "$TARGET" ]; then
    dangling=$(resolve_symlink "$TARGET" || true)
    warn "CLAUDE.md is a broken symlink: $TARGET -> ${dangling:-?}"
    warn "Refusing to guess. Fix or remove the link, then re-run the installer."
    exit 0
fi

REAL_TARGET=$(resolve_symlink "$TARGET")
# Test the link itself, not the strings: resolve_symlink also normalises the
# path, so the two can differ for a perfectly ordinary file.
if [ -L "$TARGET" ]; then
    info "CLAUDE.md is a symlink; updating the file it points at: $REAL_TARGET"
fi

# ─── Case 1: target missing → install verbatim (temp + mv) ───────────────────

if [ ! -f "$REAL_TARGET" ]; then
    target_parent=$(dirname "$REAL_TARGET")
    mkdir -p "$target_parent"
    NEWFILE="$REAL_TARGET.claude-skills.tmp.$$"
    cp "$SRC" "$NEWFILE"
    mv "$NEWFILE" "$REAL_TARGET"
    NEWFILE=""
    ok "Installed CLAUDE.md"
    exit 0
fi

# Build the candidate next to the real file so the final mv is same-filesystem.
NEWFILE="$REAL_TARGET.claude-skills.tmp.$$"

# ─── Inspect the target's markers ────────────────────────────────────────────

tgt_begin_count=$(count_marker "$REAL_TARGET" "$BEGIN_MARKER")
tgt_end_count=$(count_marker "$REAL_TARGET" "$END_MARKER")
tgt_begin=$(find_marker "$REAL_TARGET" "$BEGIN_MARKER")
tgt_end=$(find_marker "$REAL_TARGET" "$END_MARKER")

if [ "$tgt_begin_count" -eq 1 ] && [ "$tgt_end_count" -eq 1 ] && [ "$tgt_begin" -lt "$tgt_end" ]; then
    MODE="replace"
elif [ "$tgt_begin_count" -eq 0 ] && [ "$tgt_end_count" -eq 0 ]; then
    # Guard: a marker hidden behind trailing whitespace would otherwise get a
    # second block appended below it. Refuse instead.
    if has_looselike_marker "$REAL_TARGET"; then
        MODE="malformed"
    else
        MODE="append"
    fi
else
    MODE="malformed"
fi

# ─── Case 4: malformed markers → hands off, leave a .new for manual merge ────

if [ "$MODE" = "malformed" ]; then
    warn "CLAUDE.md has malformed claude-skills markers ($tgt_begin_count BEGIN, $tgt_end_count END)."
    if [ -e "$REAL_TARGET.new" ] && ! cmp -s "$SRC" "$REAL_TARGET.new"; then
        warn "Left it untouched. $REAL_TARGET.new already exists and differs from"
        warn "the repo version — looks like a merge in progress, so it was kept as is."
    else
        cp "$SRC" "$REAL_TARGET.new"
        warn "Left it untouched and wrote the new version to: $REAL_TARGET.new"
    fi
    warn "Merge by hand, then delete the .new file. Diff with:"
    warn "  diff \"$REAL_TARGET\" \"$REAL_TARGET.new\""
    exit 0
fi

# ─── Build the new content ───────────────────────────────────────────────────

# Which line ending does the target use? On a replace we follow the target's
# own marker lines; on an append we follow whichever ending most of the file's
# lines use. The block is written to match, so we never introduce a mix. A file
# that was already mixed stays mixed outside the block — we just don't add to it.
tgt_crlf=0
if [ "$MODE" = "replace" ]; then
    if marker_line_is_crlf "$REAL_TARGET" "$BEGIN_MARKER"; then tgt_crlf=1; fi
else
    if file_is_crlf "$REAL_TARGET"; then tgt_crlf=1; fi
fi
if [ "$tgt_crlf" -eq 1 ]; then EOL='\r\n'; else EOL='\n'; fi

if [ "$MODE" = "replace" ]; then
    # Paths go through ENVIRON, not -v: awk applies escape processing to -v
    # values, which mangles a Windows-style path containing backslashes.
    awk_rc=0
    CMD_BLOCK_FILE="$BLOCK" CMD_TARGET_CRLF="$tgt_crlf" \
        awk -v b="$tgt_begin" -v e="$tgt_end" "$AWK_FUNCS"'
        BEGIN {
            blk = ENVIRON["CMD_BLOCK_FILE"]
            eol = (ENVIRON["CMD_TARGET_CRLF"] == "1") ? "\r" : ""
        }
        NR == b {
            n = 0
            while ((r = (getline line < blk)) > 0) {
                out = stripcr(line) eol
                print out
                n++
            }
            close(blk)
            # r < 0 means the block file could not be read; n == 0 means it was
            # empty. Either way, writing on would silently drop the block.
            if (r < 0 || n == 0) exit 3
        }
        NR >= b && NR <= e { next }
        { print }
    ' "$REAL_TARGET" > "$NEWFILE" || awk_rc=$?

    # exit 3 is our own "the block could not be read" signal; anything else is
    # a failure to run awk or to write the temp file (e.g. a read-only dir).
    if [ "$awk_rc" -eq 3 ]; then
        error "Could not read the managed block while rewriting $REAL_TARGET."
        error "Left it untouched."
        exit 1
    elif [ "$awk_rc" -ne 0 ]; then
        error "Failed to build the merged file at $NEWFILE (exit $awk_rc)."
        error "Is $(dirname "$REAL_TARGET") writable? Left $REAL_TARGET untouched."
        exit 1
    fi

    # awk always terminates its last line. If the original did not end in a
    # newline and its final line survived the replacement, restore that.
    tgt_lines=$(line_count "$REAL_TARGET")
    if [ "$tgt_end" -lt "$tgt_lines" ] && lacks_final_newline "$REAL_TARGET"; then
        printf '%s' "$(cat "$NEWFILE")" > "$NEWFILE.trimmed"
        mv "$NEWFILE.trimmed" "$NEWFILE"
    fi
    ACTION_MSG="Updated managed block in CLAUDE.md"
else
    # append: existing content, a blank line, then the managed block.
    if ! cp "$REAL_TARGET" "$NEWFILE"; then
        error "Could not create $NEWFILE. Is $(dirname "$REAL_TARGET") writable?"
        error "Left $REAL_TARGET untouched."
        exit 1
    fi
    if lacks_final_newline "$REAL_TARGET"; then
        printf "$EOL$EOL" >> "$NEWFILE"  # end the last line, then a blank line
    else
        printf "$EOL" >> "$NEWFILE"      # blank line
    fi
    awk_rc=0
    CMD_BLOCK_FILE="$BLOCK" CMD_TARGET_CRLF="$tgt_crlf" \
        awk "$AWK_FUNCS"'
        BEGIN {
            blk = ENVIRON["CMD_BLOCK_FILE"]
            eol = (ENVIRON["CMD_TARGET_CRLF"] == "1") ? "\r" : ""
            n = 0
            while ((r = (getline line < blk)) > 0) {
                out = stripcr(line) eol
                print out
                n++
            }
            close(blk)
            if (r < 0 || n == 0) exit 3
        }
    ' < /dev/null >> "$NEWFILE" || awk_rc=$?

    if [ "$awk_rc" -eq 3 ]; then
        error "Could not read the managed block while appending to $REAL_TARGET."
        error "Left it untouched."
        exit 1
    elif [ "$awk_rc" -ne 0 ]; then
        error "Failed to append the managed block to $NEWFILE (exit $awk_rc)."
        error "Left $REAL_TARGET untouched."
        exit 1
    fi
    ACTION_MSG="Appended managed block to CLAUDE.md"
fi

# ─── Sanity check: the result must carry exactly one marker pair ─────────────

new_begin_count=$(count_marker "$NEWFILE" "$BEGIN_MARKER")
new_end_count=$(count_marker "$NEWFILE" "$END_MARKER")
if [ "$new_begin_count" -ne 1 ] || [ "$new_end_count" -ne 1 ]; then
    error "Refusing to write: the merged file would have $new_begin_count BEGIN and $new_end_count END markers."
    error "Left $REAL_TARGET untouched."
    exit 1
fi

# ─── Case: nothing to do ─────────────────────────────────────────────────────

if cmp -s "$NEWFILE" "$REAL_TARGET"; then
    ok "CLAUDE.md already up to date"
    exit 0
fi

# ─── Back up, then write ─────────────────────────────────────────────────────

mkdir -p "$BACKUP_DIR"
cp "$REAL_TARGET" "$BACKUP_DIR/CLAUDE.md"

mv "$NEWFILE" "$REAL_TARGET"
NEWFILE=""
ok "$ACTION_MSG"
exit 0
