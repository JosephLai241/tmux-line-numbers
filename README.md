# tmux-line-numbers

> [!IMPORTANT]
>
> Requires tmux 3.2+ (uses `pane-mode-changed` hook and `copy_cursor_y` format).

Display line numbers in tmux when in copy-mode. Like vim's `relativenumber`, a narrow pane appears on the left showing how many lines away each line is from your cursor so you can instantly see that you need `5k`, `12j`, etc. to get where you want.

The cursor line shows its absolute line number in the buffer, while all other lines show their relative distance.

```
  5 │
  4 │
  3 │
  2 │
  1 │
188 │  <- cursor is here (absolute line number)
  1 │
  2 │
  3 │
  4 │
  5 │
```

When relative numbers are turned off, all lines show their absolute line number instead:

```
183 │
184 │
185 │
186 │
187 │
188 │  <- cursor is here (highlighted)
189 │
190 │
191 │
192 │
193 │
```

# Installing with [TPM](https://github.com/tmux-plugins/tpm)

Add the plugin to your `~/.tmux.conf`:

```tmux
set -g @plugin 'JosephLai241/tmux-line-numbers'
```

Then install with TPM: `prefix` + `I`.

# Configuration

Configuration is optional. Add any of these to `~/.tmux.conf`:

```tmux
# Background color for the current line (default: default)
set -g @line-numbers-current-line-bg '#2A2A37'

# Bold the current line number (default: on)
set -g @line-numbers-current-line-bold off

# Foreground color for the current line (default: yellow)
set -g @line-numbers-current-line-fg '#FF9E3B'

# Background color for other line numbers (default: default)
set -g @line-numbers-bg '#2A2A37'

# Foreground color for other line numbers (default: colour243)
set -g @line-numbers-fg '#54546D'

# Minimum pane width required to show line numbers (default: 40)
set -g @line-numbers-min-pane-width 60

# Poll interval in seconds for cursor position updates (default: 0.1)
set -g @line-numbers-poll-interval 0.05

# Position of the line number column (default: left)
set -g @line-numbers-position right

# Show relative distances from cursor or absolute line numbers (default: on)
set -g @line-numbers-relative off
```

Colors accept the following values:

- Tmux color names (`red`, `brightcyan`)
- 256-palette (`colour0` - `colour255`)
- Hex (`#ff6600`)
- Or `default`.

# How It Works

1. A `pane-mode-changed` hook detects when you enter or exit copy-mode.
1. On entry, a narrow pane is split to the left running a render loop.
1. The render loop polls `copy_cursor_y` (~10 times/sec) and redraws the line numbers when the cursor moves.
1. On exit, the line-number pane is automatically cleaned up.

The width of the line-number column adapts to the size of your scrollback buffer.
