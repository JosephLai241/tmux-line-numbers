#!/usr/bin/env bash
# Continuously renders relative line numbers for a pane in copy-mode.

# Stores the pane in copy-mode.
TARGET_PANE="$1"

# The absolute path to the scripts directory.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/color.sh
source "$SCRIPTS_DIR/color.sh"

# Background ANSI code for the current line.
CUR_BG_CODE="$(tmux_color_to_ansi "${2:-default}" bg)"
# Whether to bold the current line number.
CUR_BOLD="${3:-on}"
# Foreground ANSI code for the current line.
CUR_FG_CODE="$(tmux_color_to_ansi "${4:-yellow}" fg)"
# Whether to show the current line's number ("on") or a solid bar ("off").
CUR_NUMBER="${5:-on}"
# Number of digits to use for formatting. This is calculated at split time.
DIGITS="${6:-3}"
# Printf format string for line numbers.
FMT="%${DIGITS}d"
# Background ANSI code for non-current line numbers.
LN_BG_CODE="$(tmux_color_to_ansi "${7:-default}" bg)"
# Foreground ANSI code for non-current line numbers.
LN_FG_CODE="$(tmux_color_to_ansi "${8:-colour243}" fg)"
# Seconds between cursor position polls.
POLL_INTERVAL="${9:-0.1}"
if ! [[ "$POLL_INTERVAL" =~ ^[0-9]*\.?[0-9]+$ ]]; then
    POLL_INTERVAL=0.1
fi
# Whether to show relative ("on") or absolute ("off") line numbers.
RELATIVE="${10:-on}"

# Pre-build a solid bar matching the digit width, used when CUR_NUMBER is off.
BAR=""
for ((i = 0; i < DIGITS; i++)); do
    BAR+="█"
done

# Pre-build bold code.
BOLD_CODE=""
if [ "$CUR_BOLD" = "on" ]; then
    BOLD_CODE="\e[1m"
fi

# Pre-build the style sequences used in every render call.
STYLE_CURRENT="${BOLD_CODE}${CUR_FG_CODE}${CUR_BG_CODE}"
STYLE_NORMAL="${LN_FG_CODE}${LN_BG_CODE}"
STYLE_RESET='\e[0m'

# Hide the cursor in this pane.
printf '\e[?25l'

# Store the previous render state to skip redundant redraws.
LAST_ABS=""
LAST_HEIGHT=""
LAST_SCREEN_Y=""

# The absolute line number only reaches the screen in absolute mode, or when the
# current line shows its number. With relative numbers and a solid current-line bar,
# scrolling changes abs_line without changing a single drawn glyph, so tracking it
# there would force redraws of an identical frame.
TRACK_ABS="on"
if [ "$RELATIVE" = "on" ] && [ "$CUR_NUMBER" = "off" ]; then
    TRACK_ABS="off"
fi

render() {
    local screen_y=$1
    local pane_height=$2
    local abs_line=$3
    local last_line=$((pane_height - 1))
    local line rel line_abs

    # Move to top left.
    printf '\e[H'

    for ((line = 0; line < pane_height; line++)); do
        rel=$((line - screen_y))

        # shellcheck disable=SC2059 # Format strings contain pre-built ANSI codes.
        if [ $rel -eq 0 ]; then
            # Current line: bold with configured colors.
            if [ "$CUR_NUMBER" = "off" ]; then
                printf "${STYLE_CURRENT}%s${STYLE_RESET}\e[K" "$BAR"
            else
                printf "${STYLE_CURRENT}${FMT}${STYLE_RESET}\e[K" "$abs_line"
            fi
        elif [ "$RELATIVE" = "on" ]; then
            # Relative mode: distance from cursor.
            if [ $rel -lt 0 ]; then
                rel=$((-rel))
            fi
            printf "${STYLE_NORMAL}${FMT}${STYLE_RESET}\e[K" "$rel"
        else
            # Absolute mode: absolute line number for this row.
            line_abs=$((abs_line + rel))
            printf "${STYLE_NORMAL}${FMT}${STYLE_RESET}\e[K" "$line_abs"
        fi

        # No newline on last line to prevent scrolling.
        if [ $line -lt $last_line ]; then
            printf '\n'
        fi
    done
}

# Waiting on a fd that never delivers avoids forking /bin/sleep on every tick, which
# costs ~2.4ms of the ~8ms this loop spends per poll. bash only accepts a fractional
# `read -t` timeout from 4.0 onward and stock macOS still ships 3.2, so this is gated
# with a plain sleep as the fallback.
nap() { sleep "$POLL_INTERVAL"; }
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
    tick_dir=$(mktemp -d 2>/dev/null) || tick_dir=""
    if [ -n "$tick_dir" ] && mkfifo "$tick_dir/tick" 2>/dev/null; then
        # Holding both ends open means the fd never carries data and never reaches
        # EOF, making `read -t` a pure timer.
        exec 9<>"$tick_dir/tick"
        rm -rf "$tick_dir"
        # Verify it actually blocks. A fd that returns early (status <= 128 means
        # data or EOF, not a timeout) would spin this loop at 100% CPU.
        read -rt 0.05 -u 9 _tick
        if [ $? -gt 128 ]; then
            nap() { read -rt "$POLL_INTERVAL" -u 9 _tick; }
        fi
    fi
fi

while true; do
    # Single tmux call to get all values. This is much faster than separate calls.
    state=$(tmux display -p -t "$TARGET_PANE" \
        '#{pane_mode} #{copy_cursor_y} #{history_size} #{scroll_position} #{pane_height}' \
        2>/dev/null) || break

    # Split on whitespace via the positional parameters. A here-string is the obvious
    # choice, but bash writes one to a temp file every iteration (~0.2ms of the ~8ms
    # tick). Every script argument was copied into a named variable above, so
    # overwriting the positional parameters here is safe.
    # shellcheck disable=SC2086 # Intentional word splitting on $state.
    set -- $state
    pane_mode=$1 screen_y=$2 hist_size=$3 scroll_pos=$4 pane_height=$5

    if [ "$pane_mode" != "copy-mode" ]; then
        break
    fi

    if [ -z "$screen_y" ] || [ -z "$pane_height" ]; then
        break
    fi

	# Get the absolute line number (distance from top of scrollback to cursor).
	# Adds 1 to make it 1-indexed (line 1 is the first line of the output).
    abs_line=$((hist_size - scroll_pos + screen_y + 1))
    if [ "$abs_line" -lt 1 ]; then
        abs_line=1
    fi

    # Only re-render if something that actually gets drawn has changed.
    if [ "$screen_y" = "$LAST_SCREEN_Y" ] && [ "$pane_height" = "$LAST_HEIGHT" ] &&
        { [ "$TRACK_ABS" = "off" ] || [ "$abs_line" = "$LAST_ABS" ]; }; then
        nap
        continue
    fi
    LAST_SCREEN_Y="$screen_y"
    LAST_HEIGHT="$pane_height"
    LAST_ABS="$abs_line"

    render "$screen_y" "$pane_height" "$abs_line"

    nap
done
