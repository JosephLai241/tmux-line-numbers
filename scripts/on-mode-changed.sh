#!/usr/bin/env bash
# Called by the pane-mode-changed hook.

# This value is `1` if tmux is in a mode, `0` if not.
IN_MODE="$2"
# The pane that triggered the mode change.
PANE_ID="$1"
# The absolute path to the scripts directory.
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Marker used to find the line-number pane.
MARKER="TMUX_LINE_NUMBERS_FOR"

if [ "$IN_MODE" = "1" ]; then
    # Check this pane is actually in copy-mode (not command mode, etc.).
    PANE_MODE=$(tmux display -p -t "$PANE_ID" '#{pane_mode}' 2>/dev/null)
    if [ "$PANE_MODE" != "copy-mode" ]; then
        exit 0
    fi

    # Don't create a second line-number pane if one already exists.
    EXISTING=$(tmux list-panes -F '#{pane_id} #{pane_start_command}' 2>/dev/null | grep "$MARKER=$PANE_ID" | awk '{print $1}')
    if [ -n "$EXISTING" ]; then
        exit 0
    fi

    # Calculate width based on the largest possible line number (history + visible).
    MAX_LINE=$(tmux display -p -t "$PANE_ID" '#{e|+:#{history_size},#{pane_height}}')
    # Number of digits needed, with a minimum of 3.
    DIGITS=${#MAX_LINE}
    if [ "$DIGITS" -lt 3 ]; then
        DIGITS=3
    fi
    # Add 1 column of padding.
    LN_WIDTH=$((DIGITS + 1))

    # Load theme settings.
    CUR_BG=$(tmux show-option -gqv @line-numbers-current-line-bg 2>/dev/null)
    CUR_BOLD=$(tmux show-option -gqv @line-numbers-current-line-bold 2>/dev/null)
    if [ "$CUR_BOLD" != "off" ]; then
        CUR_BOLD="on"
    fi
    CUR_FG=$(tmux show-option -gqv @line-numbers-current-line-fg 2>/dev/null)
    LN_BG=$(tmux show-option -gqv @line-numbers-bg 2>/dev/null)
    LN_FG=$(tmux show-option -gqv @line-numbers-fg 2>/dev/null)

	# Load the minimum pane width limit setting.
    MIN_WIDTH=$(tmux show-option -gqv @line-numbers-min-pane-width 2>/dev/null)
    MIN_WIDTH="${MIN_WIDTH:-40}"

	# Load the poll interval setting.
    POLL_INTERVAL=$(tmux show-option -gqv @line-numbers-poll-interval 2>/dev/null)

	# Load the number column position setting.
    POSITION=$(tmux show-option -gqv @line-numbers-position 2>/dev/null)
    if [ "$POSITION" != "right" ]; then
        POSITION="left"
    fi

	# Load the relative or absolute line number setting.
    RELATIVE=$(tmux show-option -gqv @line-numbers-relative 2>/dev/null)
    if [ "$RELATIVE" != "off" ]; then
        RELATIVE="on"
    fi

    # Do not activate this plugin if the current pane is too narrow.
    PANE_WIDTH=$(tmux display -p -t "$PANE_ID" '#{pane_width}')
    if [ "$PANE_WIDTH" -lt "$MIN_WIDTH" ]; then
        exit 0
    fi

    # Build split-window flags. Add the -b (before) flag if rendering the numbers
	# on the left, otherwise omit it if rendering them on the right.
    SPLIT_FLAGS="-hdl $LN_WIDTH"
    if [ "$POSITION" = "left" ]; then
        SPLIT_FLAGS="-hbdl $LN_WIDTH"
    fi

    # Split a pane for line numbers. Each argument is single-quoted to protect
    # special characters like "#" in hex colors.
    LN_PANE=$(tmux split-window -t "$PANE_ID" $SPLIT_FLAGS -PF '#{pane_id}' \
        -e "$MARKER=$PANE_ID" \
        "'$SCRIPTS_DIR/render-loop.sh' '$PANE_ID' '$CUR_BG' '$CUR_BOLD' '$CUR_FG' '$DIGITS' '$LN_BG' '$LN_FG' '$POLL_INTERVAL' '$RELATIVE'")

    if [ -z "$LN_PANE" ]; then
        exit 1
    fi

    # Store the line-number pane ID so we can clean it up later.
    tmux set-option -p -t "$PANE_ID" @line_numbers_pane "$LN_PANE"

    # Disable borders/status for the line-number pane and make it non-interactive.
    tmux set-option -p -t "$LN_PANE" remain-on-exit on
    # Prevent focus from going to the line-number pane.
    tmux select-pane -t "$PANE_ID"
else
    # Kill the line-number pane if it exists when exiting copy-mode.
    LN_PANE=$(tmux show-options -p -t "$PANE_ID" -v @line_numbers_pane 2>/dev/null)
    if [ -n "$LN_PANE" ]; then
        tmux kill-pane -t "$LN_PANE" 2>/dev/null
        tmux set-option -pu -t "$PANE_ID" @line_numbers_pane 2>/dev/null
    fi
fi
