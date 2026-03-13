#!/usr/bin/env bash
# Continuously renders relative line numbers for a pane in copy-mode.

# Stores the pane in copy-mode.
TARGET_PANE="$1"

# The absolute path to the scripts directory.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=color.sh
source "$SCRIPTS_DIR/color.sh"

# Background ANSI code for the current line.
CUR_BG_CODE="$(tmux_color_to_ansi "${2:-default}" bg)"
# Whether to bold the current line number.
CUR_BOLD="${3:-on}"
# Foreground ANSI code for the current line.
CUR_FG_CODE="$(tmux_color_to_ansi "${4:-yellow}" fg)"
# Number of digits to use for formatting. This is calculated at split time.
DIGITS="${5:-3}"
# Printf format string for line numbers.
FMT="%${DIGITS}d"
# Background ANSI code for non-current line numbers.
LN_BG_CODE="$(tmux_color_to_ansi "${6:-default}" bg)"
# Foreground ANSI code for non-current line numbers.
LN_FG_CODE="$(tmux_color_to_ansi "${7:-colour243}" fg)"
# Seconds between cursor position polls.
POLL_INTERVAL="${8:-0.1}"
# Whether to show relative ("on") or absolute ("off") line numbers.
RELATIVE="${9:-on}"

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

        if [ $rel -eq 0 ]; then
            # Current line: bold with configured colors.
            printf "${STYLE_CURRENT}${FMT}${STYLE_RESET}\e[K" "$abs_line"
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

while true; do
    # Single tmux call to get all values. This is much faster than separate calls.
    state=$(tmux display -p -t "$TARGET_PANE" \
        '#{pane_mode} #{copy_cursor_y} #{history_size} #{scroll_position} #{pane_height}' \
        2>/dev/null) || break

    # Parse space-separated values.
    read -r pane_mode screen_y hist_size scroll_pos pane_height <<< "$state"

    if [ "$pane_mode" != "copy-mode" ]; then
        break
    fi

    if [ -z "$screen_y" ] || [ -z "$pane_height" ]; then
        break
    fi

	# Get the absolute line number (distance from top of scrollback to cursor).
	# Adds 1 to make it 1-indexed (line 1 is the first line of the output).
    abs_line=$((hist_size - scroll_pos + screen_y + 1))

    # Only re-render if the position or height has changed.
    if [ "$screen_y" = "$LAST_SCREEN_Y" ] && [ "$pane_height" = "$LAST_HEIGHT" ] && [ "$abs_line" = "$LAST_ABS" ]; then
        sleep "$POLL_INTERVAL"
        continue
    fi
    LAST_SCREEN_Y="$screen_y"
    LAST_HEIGHT="$pane_height"
    LAST_ABS="$abs_line"

    render "$screen_y" "$pane_height" "$abs_line"

    sleep "$POLL_INTERVAL"
done
