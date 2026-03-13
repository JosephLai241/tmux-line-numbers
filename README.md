# tmux-line-numbers

![GitHub Actions Workflow Status](https://img.shields.io/github/actions/workflow/status/JosephLai241/tmux-line-numbers/lint.yml?style=flat-square&label=shellcheck)

> [!IMPORTANT]
>
> Requires tmux 3.2+ (uses `pane-mode-changed` hook and `copy_cursor_y` format).

Display line numbers in tmux when in `copy-mode`. Like vim's `relativenumber`, a narrow pane appears on the left showing how many lines away each line is from your cursor so you can instantly see that you need `5k`, `12j`, etc. to get where you want.

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

> [!NOTE]
>
> The default values are shown in the example configuration below.

Configuration is optional. Add any of these to `~/.tmux.conf`:

```tmux
# Background color for the current line.
set -g @line-numbers-current-line-bg default

# Bold the current line number (`on`, `off`).
set -g @line-numbers-current-line-bold on

# Foreground color for the current line.
set -g @line-numbers-current-line-fg yellow

# Background color for other line numbers.
set -g @line-numbers-bg default

# Foreground color for other line numbers.
set -g @line-numbers-fg colour243

# Minimum pane width required to show line numbers.
set -g @line-numbers-min-pane-width 40

# Poll interval in seconds for cursor position updates.
set -g @line-numbers-poll-interval 0.1

# Position of the line number column (`left`, `right`).
set -g @line-numbers-position left

# Show relative distances from cursor or absolute line numbers (`on`, `off`).
set -g @line-numbers-relative on
```

Colors accept the following values:

- Tmux color names (`red`, `brightcyan`)
- 256-palette (`colour0` - `colour255`)
- Hex (`#ff6600`)
- Or `default`.

# How It Works

## Scripts

- **`line-numbers.tmux`**: Entry point sourced by TPM. Registers a global `pane-mode-changed` hook.
- **`scripts/on-mode-changed.sh`**: Hook handler. Reads all user configuration, then either creates or destroys the `line-number` pane.
- **`scripts/render-loop.sh`**: Runs inside the `line-number` pane. Polls the target pane's `copy_cursor_y` and redraws when the cursor moves.

## Flow

1. When you enter `copy-mode`, the `pane-mode-changed` hook fires and calls `on-mode-changed.sh`.
1. The script checks the pane is in `copy-mode` (not command mode), reads configuration, and verifies the pane meets the minimum width.
1. A narrow pane is split to the configured side running `render-loop.sh`, which polls cursor position (~10 times/sec by default) and renders line numbers.
1. When you exit `copy-mode`, the hook fires again and the `line-number` pane is automatically killed.

The width of the `line-number` column adapts to the size of your scrollback buffer. A helper script (`scripts/color.sh`) converts tmux color names, 256-palette values, and hex codes to ANSI escape sequences at startup.
