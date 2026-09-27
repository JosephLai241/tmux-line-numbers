#!/usr/bin/env bash
# Test suite for tmux-line-numbers.
#
# Two halves:
#   1. Unit tests for the pure color conversion in scripts/color.sh.
#   2. Integration tests that drive a real tmux server through copy-mode and assert
#      on the line-number pane it creates.
#
# The integration half runs against its own tmux server, isolated via TMUX_TMPDIR,
# so it never reads or writes the developer's running server or global options.
#
# Usage: tests/run.sh

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0

# Renders escape sequences readable so a failure message is diffable.
show() {
    printf '%s' "$1" | cat -v
}

# $1 = label, $2 = expected, $3 = actual
assert_eq() {
    if [ "$2" = "$3" ]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       expected [%s]\n       actual   [%s]\n' \
            "$1" "$(show "$2")" "$(show "$3")"
    fi
}

###############################################################################
# 1. Unit tests: scripts/color.sh
###############################################################################

# shellcheck source=scripts/color.sh
# shellcheck disable=SC1091 # Resolved at runtime from the repo root.
source "$REPO_DIR/scripts/color.sh"

echo "color.sh: named colors"
assert_eq "black fg"        "$(printf '\e[30m')" "$(tmux_color_to_ansi black fg)"
assert_eq "red fg"          "$(printf '\e[31m')" "$(tmux_color_to_ansi red fg)"
assert_eq "red bg"          "$(printf '\e[41m')" "$(tmux_color_to_ansi red bg)"
assert_eq "white fg"        "$(printf '\e[37m')" "$(tmux_color_to_ansi white fg)"
assert_eq "white bg"        "$(printf '\e[47m')" "$(tmux_color_to_ansi white bg)"

echo "color.sh: bright colors"
assert_eq "brightblack fg"  "$(printf '\e[90m')"  "$(tmux_color_to_ansi brightblack fg)"
assert_eq "brightred fg"    "$(printf '\e[91m')"  "$(tmux_color_to_ansi brightred fg)"
assert_eq "brightwhite fg"  "$(printf '\e[97m')"  "$(tmux_color_to_ansi brightwhite fg)"
assert_eq "brightred bg"    "$(printf '\e[101m')" "$(tmux_color_to_ansi brightred bg)"
assert_eq "brightwhite bg"  "$(printf '\e[107m')" "$(tmux_color_to_ansi brightwhite bg)"

echo "color.sh: 256 palette"
assert_eq "colour0 fg"      "$(printf '\e[38;5;0m')"   "$(tmux_color_to_ansi colour0 fg)"
assert_eq "colour243 fg"    "$(printf '\e[38;5;243m')" "$(tmux_color_to_ansi colour243 fg)"
assert_eq "colour255 bg"    "$(printf '\e[48;5;255m')" "$(tmux_color_to_ansi colour255 bg)"

echo "color.sh: hex RGB"
assert_eq "#ff8800 fg"      "$(printf '\e[38;2;255;136;0m')" "$(tmux_color_to_ansi '#ff8800' fg)"
assert_eq "#FF8800 upper"   "$(printf '\e[38;2;255;136;0m')" "$(tmux_color_to_ansi '#FF8800' fg)"
assert_eq "#2A2A37 bg"      "$(printf '\e[48;2;42;42;55m')"  "$(tmux_color_to_ansi '#2A2A37' bg)"
assert_eq "#000000 fg"      "$(printf '\e[38;2;0;0;0m')"     "$(tmux_color_to_ansi '#000000' fg)"

echo "color.sh: invalid input falls back to terminal default"
assert_eq "default fg"      "$(printf '\e[39m')" "$(tmux_color_to_ansi default fg)"
assert_eq "default bg"      "$(printf '\e[49m')" "$(tmux_color_to_ansi default bg)"
assert_eq "unknown name"    "$(printf '\e[39m')" "$(tmux_color_to_ansi chartreuse fg)"
assert_eq "hex too short"   "$(printf '\e[39m')" "$(tmux_color_to_ansi '#ff88' fg)"
assert_eq "hex too long"    "$(printf '\e[39m')" "$(tmux_color_to_ansi '#ff880011' fg)"
assert_eq "hex non-digit"   "$(printf '\e[39m')" "$(tmux_color_to_ansi '#gggggg' fg)"
assert_eq "empty string"    "$(printf '\e[39m')" "$(tmux_color_to_ansi '' fg)"

###############################################################################
# 2. Integration tests: the real plugin against a real tmux server
###############################################################################

if ! command -v tmux > /dev/null 2>&1; then
    echo
    echo "SKIP integration tests: tmux is not installed"
    echo
    printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ] || exit 1
    exit 0
fi

# Isolate the test server.
#
# Order matters here. tmux reads the socket path out of $TMUX before it ever consults
# TMUX_TMPDIR, so a suite that only sets TMUX_TMPDIR while running inside tmux talks
# to the developer's own server - and `kill-server` then takes down their sessions.
# Drop $TMUX first, then point TMUX_TMPDIR at a private directory. Plain `tmux` now
# resolves to a private socket for this script and for the plugin's own scripts.
unset TMUX
TMUX_TMPDIR="$(mktemp -d)" || exit 1
[ -d "$TMUX_TMPDIR" ] || exit 1
# Resolve to the physical path before the guard below compares against it. On macOS
# mktemp hands back /var/folders/... while tmux reports /private/var/folders/...,
# because /var is a symlink; the two must be spelled the same way to compare.
TMUX_TMPDIR="$(cd -- "$TMUX_TMPDIR" && pwd -P)"
export TMUX_TMPDIR

# Hard stop unless `tmux` really resolves inside TMUX_TMPDIR. Every destructive call
# below goes through this first, so a future change to the isolation cannot quietly
# start operating on a real server.
# True when plain `tmux` resolves to a socket inside TMUX_TMPDIR.
is_isolated() {
    case "$(tmux display-message -p '#{socket_path}' 2> /dev/null)" in
        "$TMUX_TMPDIR"/*) return 0 ;;
    esac
    return 1
}

assert_isolated() {
    is_isolated && return 0
    printf 'ABORT: tmux resolved to [%s], which is outside [%s].\n' \
        "$(tmux display-message -p '#{socket_path}' 2> /dev/null)" "$TMUX_TMPDIR" >&2
    printf '       Refusing to run destructive tmux commands against that server.\n' >&2
    exit 1
}

# Kills the test server, but only once it is confirmed to be the test server.
stop_server() {
    tmux has-session 2> /dev/null || return 0
    assert_isolated
    tmux kill-server 2> /dev/null
}

# Runs on exit, including the abort path, so it checks quietly instead of asserting.
cleanup() {
    if is_isolated; then
        tmux kill-server 2> /dev/null
    fi
    # Only ever remove something that still looks like the temp directory we made.
    case "$TMUX_TMPDIR" in
        /tmp/*/ | /tmp/*) rm -rf "$TMUX_TMPDIR" ;;
        /private/tmp/*) rm -rf "$TMUX_TMPDIR" ;;
        /var/folders/*) rm -rf "$TMUX_TMPDIR" ;;
        /private/var/folders/*) rm -rf "$TMUX_TMPDIR" ;;
        *) printf 'skipping cleanup of unexpected path [%s]\n' "$TMUX_TMPDIR" >&2 ;;
    esac
}
trap cleanup EXIT

# Settle time for the pane-mode-changed hook and the render loop's first frame.
SETTLE=0.6

# Lines of scrollback each test session generates before entering copy-mode.
SCROLLBACK_LINES=300

# Blocks until the scrollback has actually landed. A fixed sleep is not enough: the
# pane's shell may still be starting, in which case the plugin sizes the number column
# from an almost empty history while the assertions below measure a full one, and every
# digit-width check disagrees by one.
wait_for_history() {
    local height target i
    height=$(tmux display -p '#{pane_height}')
    # history_size counts only the lines that scrolled off, and the last screenful of
    # output is still visible, so it settles just short of SCROLLBACK_LINES.
    target=$((SCROLLBACK_LINES - height))
    for ((i = 0; i < 100; i++)); do
        if [ "$(tmux display -p '#{history_size}')" -ge "$target" ]; then
            return 0
        fi
        sleep 0.1
    done
    printf '  WARN scrollback stalled at %s, wanted %s\n' \
        "$(tmux display -p '#{history_size}')" "$target" >&2
    return 1
}

# Starts a fresh single-pane session with scrollback and no user config.
new_session() {
    stop_server
    # The pane's own command generates the scrollback. Sending it as keystrokes instead
    # races the shell's startup: until the prompt exists the input is dropped, and the
    # session then tests against an almost empty history.
    tmux -f /dev/null new-session -d -x "${1:-80}" -y "${2:-24}" \
        "seq 1 $SCROLLBACK_LINES; sleep 3600" || return 1
    # Confirm isolation before anything touches this server.
    assert_isolated
    # copy-mode freezes history_size, so waiting here makes every later assertion agree
    # with what the plugin saw when it sized the column.
    wait_for_history
    # Register the hook from the working tree under test.
    "$REPO_DIR/line-numbers.tmux"
}

# Prints the pane id of the target (first) pane.
target_pane() {
    tmux list-panes -F '#{pane_id}' | head -1
}

# Prints the line-number pane id recorded on the target pane, or nothing.
ln_pane() {
    tmux show-option -p -t "$1" -v @line_numbers_pane 2> /dev/null
}

# Prints one rendered row. $1 = pane id, $2 = zero-indexed row. Deliberately avoids
# mapfile, which bash 3.2 (still the stock macOS shell) does not have.
row_at() {
    tmux capture-pane -p -t "$1" 2> /dev/null | sed -n "$(($2 + 1))p"
}

echo
echo "integration: tmux $(tmux -V | awk '{print $2}'), isolated server"

# --- creates the pane on copy-mode entry, sized to the digit count -----------
new_session
T=$(target_pane)
tmux copy-mode -t "$T"
sleep "$SETTLE"
LN=$(ln_pane "$T")

if [ -z "$LN" ]; then
    FAIL=$((FAIL + 1))
    echo "  FAIL entering copy-mode created a line-number pane"
    echo "       no @line_numbers_pane recorded; skipping dependent assertions"
else
    PASS=$((PASS + 1))
    echo "  ok   entering copy-mode created a line-number pane"

    # Width tracks the widest renderable line number plus one column of padding.
    MAX_LINE=$(tmux display -p -t "$T" '#{e|+:#{history_size},#{pane_height}}')
    assert_eq "pane width is digits+1" "$(( ${#MAX_LINE} + 1 ))" \
        "$(tmux display -p -t "$LN" '#{pane_width}')"

    # Relative mode: the row holding the cursor shows the absolute line number, and
    # row 0 shows its distance from the cursor. Both are derived from live tmux
    # values rather than hardcoded, so this asserts the formula, not a magic number.
    read -r CURSOR_Y HIST SCROLL <<< \
        "$(tmux display -p -t "$T" '#{copy_cursor_y} #{history_size} #{scroll_position}')"
    EXPECTED_ABS=$((HIST - SCROLL + CURSOR_Y + 1))
    assert_eq "current row shows absolute number" \
        "$EXPECTED_ABS" "$(row_at "$LN" "$CURSOR_Y" | tr -d ' ')"
    assert_eq "row 0 shows distance from cursor" \
        "$CURSOR_Y" "$(row_at "$LN" 0 | tr -d ' ')"

    # --- exiting copy-mode tears the pane down ---------------------------------
    tmux send-keys -t "$T" -X cancel
    sleep "$SETTLE"
    assert_eq "exiting copy-mode kills the pane" "1" \
        "$(tmux list-panes -F '#{pane_id}' | wc -l | tr -d ' ')"
    assert_eq "exiting copy-mode clears the option" "" "$(ln_pane "$T")"
fi

# --- absolute mode numbers ascend -------------------------------------------
new_session
T=$(target_pane)
tmux set-option -g @line-numbers-relative off
tmux copy-mode -t "$T"
sleep "$SETTLE"
LN=$(ln_pane "$T")
FIRST=$(row_at "$LN" 0 | tr -d ' ')
SECOND=$(row_at "$LN" 1 | tr -d ' ')
assert_eq "absolute mode ascends by one" "$((FIRST + 1))" "$SECOND"

# --- current-line-number off draws a solid bar ------------------------------
new_session
T=$(target_pane)
tmux set-option -g @line-numbers-current-line-number off
tmux copy-mode -t "$T"
sleep "$SETTLE"
LN=$(ln_pane "$T")
CURSOR_Y=$(tmux display -p -t "$T" '#{copy_cursor_y}')
MAX_LINE=$(tmux display -p -t "$T" '#{e|+:#{history_size},#{pane_height}}')
EXPECTED_BAR=""
for ((i = 0; i < ${#MAX_LINE}; i++)); do
    EXPECTED_BAR+="█"
done
assert_eq "current line is a full-width bar" \
    "$EXPECTED_BAR" "$(row_at "$LN" "$CURSOR_Y")"

# --- position right puts the column after the target pane -------------------
new_session
T=$(target_pane)
tmux set-option -g @line-numbers-position right
tmux copy-mode -t "$T"
sleep "$SETTLE"
assert_eq "position right is the last pane" "$(ln_pane "$T")" \
    "$(tmux list-panes -F '#{pane_id}' | tail -1)"

# --- position left (the default) puts it before ------------------------------
new_session
T=$(target_pane)
tmux copy-mode -t "$T"
sleep "$SETTLE"
assert_eq "position left is the first pane" "$(ln_pane "$T")" \
    "$(tmux list-panes -F '#{pane_id}' | head -1)"

# --- min-pane-width declines to split ---------------------------------------
new_session
T=$(target_pane)
tmux set-option -g @line-numbers-min-pane-width 9999
tmux copy-mode -t "$T"
sleep "$SETTLE"
assert_eq "min-pane-width blocks the split" "" "$(ln_pane "$T")"

# --- a narrow pane under the default 40-column minimum ----------------------
new_session 30 24
T=$(target_pane)
tmux copy-mode -t "$T"
sleep "$SETTLE"
assert_eq "default minimum blocks a 30-column pane" "" "$(ln_pane "$T")"

# --- an invalid poll interval still renders ---------------------------------
new_session
T=$(target_pane)
tmux set-option -g @line-numbers-poll-interval "not-a-number"
tmux copy-mode -t "$T"
sleep "$SETTLE"
LN=$(ln_pane "$T")
assert_eq "invalid poll interval still renders" "" \
    "$(tmux capture-pane -p -t "$LN" 2> /dev/null | head -1 | tr -d ' 0-9')"

# --- unset options must not shift the render-loop arguments -----------------
# The options are fetched in one tmux format string with "|" delimiters. If an unset
# option ever stopped yielding an empty field, every later value would shift up by
# one and the colors and modes would silently swap. Set exactly one option and pin
# all eleven arguments.
new_session
T=$(target_pane)
tmux set-option -g @line-numbers-fg red
tmux copy-mode -t "$T"
sleep "$SETTLE"
LN=$(ln_pane "$T")
MAX_LINE=$(tmux display -p -t "$T" '#{e|+:#{history_size},#{pane_height}}')
# Drop the leading script path, then join the quoted arguments with commas.
ARGS=$(tmux display -p -t "$LN" '#{pane_start_command}' |
    grep -o "'[^']*'" | tail -n +2 | sed "s/'//g" | paste -sd, -)
assert_eq "unset options stay empty fields" \
    "$T,,on,,on,${#MAX_LINE},,red,,on" "$ARGS"

###############################################################################

echo
printf 'passed: %d  failed: %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] || exit 1
