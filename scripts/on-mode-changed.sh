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
    # Fetch pane geometry and every plugin option in a single tmux round-trip. One
    # `tmux display` costs ~6ms, so asking 12 separate times spent ~70ms before the
    # line-number pane could even be created. Fields are "|"-delimited: an unset
    # option yields an empty field, and a non-whitespace IFS preserves empty fields
    # instead of shifting every later value up. Order must match the `read` below.
    FMT='#{pane_mode}|#{e|+:#{history_size},#{pane_height}}|#{pane_width}'
    FMT="$FMT|#{@line-numbers-current-line-bg}|#{@line-numbers-current-line-bold}"
    FMT="$FMT|#{@line-numbers-current-line-fg}|#{@line-numbers-current-line-number}"
    FMT="$FMT|#{@line-numbers-bg}|#{@line-numbers-fg}"
    FMT="$FMT|#{@line-numbers-min-pane-width}|#{@line-numbers-poll-interval}"
    FMT="$FMT|#{@line-numbers-position}|#{@line-numbers-relative}"

    IFS='|' read -r PANE_MODE MAX_LINE PANE_WIDTH CUR_BG CUR_BOLD CUR_FG CUR_NUMBER \
        LN_BG LN_FG MIN_WIDTH POLL_INTERVAL POSITION RELATIVE \
        <<< "$(tmux display -p -t "$PANE_ID" "$FMT" 2>/dev/null)"

    # Check this pane is actually in copy-mode (not command mode, etc.).
    if [ "$PANE_MODE" != "copy-mode" ]; then
        exit 0
    fi

    # Don't create a second line-number pane if one already exists.
    if tmux list-panes -F '#{pane_id} #{pane_start_command}' 2>/dev/null |
        grep -qF "$MARKER=$PANE_ID"; then
        exit 0
    fi

    # Width is based on the largest possible line number (history + visible), so
    # $MAX_LINE above already holds it. Count the digits needed to render it.
    DIGITS=${#MAX_LINE}
    # Add 1 column of padding.
    LN_WIDTH=$((DIGITS + 1))

    # Normalize the on/off settings. Anything other than "off" means "on".
    if [ "$CUR_BOLD" != "off" ]; then
        CUR_BOLD="on"
    fi
    if [ "$CUR_NUMBER" != "off" ]; then
        CUR_NUMBER="on"
    fi
    if [ "$RELATIVE" != "off" ]; then
        RELATIVE="on"
    fi

    # The number column sits on the left unless explicitly placed right.
    if [ "$POSITION" != "right" ]; then
        POSITION="left"
    fi

    # Fall back to the default minimum pane width when the option is unset.
    MIN_WIDTH="${MIN_WIDTH:-40}"

    # Do not activate this plugin if the current pane is too narrow.
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
    # shellcheck disable=SC2086 # Intentional word splitting on SPLIT_FLAGS.
    LN_PANE=$(tmux split-window -t "$PANE_ID" $SPLIT_FLAGS -PF '#{pane_id}' \
        -e "$MARKER=$PANE_ID" \
        "'$SCRIPTS_DIR/render-loop.sh' '$PANE_ID' '$CUR_BG' '$CUR_BOLD' '$CUR_FG' '$CUR_NUMBER' '$DIGITS' '$LN_BG' '$LN_FG' '$POLL_INTERVAL' '$RELATIVE'")

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
    LN_PANE=$(tmux show-option -p -t "$PANE_ID" -v @line_numbers_pane 2>/dev/null)
    if [ -n "$LN_PANE" ]; then
        tmux kill-pane -t "$LN_PANE" 2>/dev/null
        tmux set-option -pu -t "$PANE_ID" @line_numbers_pane 2>/dev/null
    fi
fi
