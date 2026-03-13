#!/usr/bin/env bash
# Converts tmux color names to ANSI escape code parameters.
#
# Supports:
# - Named colors:  black, red, green, yellow, blue, magenta, cyan, white
# - Bright colors: brightblack, brightred, ..., brightwhite
# - 256 palette:   colour0 - colour255
# - Hex RGB:       #rrggbb
# - Default:       default (resets to terminal default)

# Converts a tmux color name to an ANSI escape sequence.
# $1 = tmux color name
# $2 = "fg" or "bg"
tmux_color_to_ansi() {
    local color="$1"
    local layer="$2"

    # Base offset: `30` for fg, `40` for bg.
    local base=30
    if [ "$layer" = "bg" ]; then
        base=40
    fi

    case "$color" in
        default)
            # Default fg: 39
			# Default bg: 49
            printf '\e[%dm' "$((base + 9))"
            ;;
        black)       printf '\e[%dm' "$((base + 0))" ;;
        red)         printf '\e[%dm' "$((base + 1))" ;;
        green)       printf '\e[%dm' "$((base + 2))" ;;
        yellow)      printf '\e[%dm' "$((base + 3))" ;;
        blue)        printf '\e[%dm' "$((base + 4))" ;;
        magenta)     printf '\e[%dm' "$((base + 5))" ;;
        cyan)        printf '\e[%dm' "$((base + 6))" ;;
        white)       printf '\e[%dm' "$((base + 7))" ;;
        # Bright colors:
		# - fg: 90-97
		# - bg: 100-107
        brightblack)   printf '\e[%dm' "$((base + 60))" ;;
        brightred)     printf '\e[%dm' "$((base + 61))" ;;
        brightgreen)   printf '\e[%dm' "$((base + 62))" ;;
        brightyellow)  printf '\e[%dm' "$((base + 63))" ;;
        brightblue)    printf '\e[%dm' "$((base + 64))" ;;
        brightmagenta) printf '\e[%dm' "$((base + 65))" ;;
        brightcyan)    printf '\e[%dm' "$((base + 66))" ;;
        brightwhite)   printf '\e[%dm' "$((base + 67))" ;;
        # 256 color palette: (colour0 - colour255).
        colour*)
            local n="${color#colour}"
            if [ "$layer" = "fg" ]; then
                printf '\e[38;5;%dm' "$n"
            else
                printf '\e[48;5;%dm' "$n"
            fi
            ;;
        # Hex RGB: (#rrggbb).
        \#*)
            local hex="${color#\#}"
            local r=$((16#${hex:0:2}))
            local g=$((16#${hex:2:2}))
            local b=$((16#${hex:4:2}))
            if [ "$layer" = "fg" ]; then
                printf '\e[38;2;%d;%d;%dm' "$r" "$g" "$b"
            else
                printf '\e[48;2;%d;%d;%dm' "$r" "$g" "$b"
            fi
            ;;
        *)
			# Fall back to default for unknown colors.
            printf '\e[%dm' "$((base + 9))"
            ;;
    esac
}
