# Claude Gauge

Track your Claude Code usage quotas in real time. No daemons, no extra API calls.

## Statusline hook (all platforms)

A simple hook that displays your usage with visual bars and countdown timers at the bottom of every Claude Code session.

![statusline](assets/screenshot-statusline.png)

### Quick setup

1. Download the script:

```bash
curl -o ~/.claude/statusline.sh https://raw.githubusercontent.com/zkfrov/claude-gauge/main/scripts/statusline.sh
chmod +x ~/.claude/statusline.sh
```

2. Add to your `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

That's it. Works on macOS, Linux, and WSL.

### What it shows

```
◷ ▰▰▱▱▱▱▱▱ 26% 13m  ◫ ▰▰▰▱▱▱▱▱ 39% 1d·2h
```

- `◷` Session (5h window) — percentage, bar, and countdown to reset
- `◫` Week (7d window) — percentage, bar, and countdown to reset

Updates automatically after every Claude response.

## macOS menu bar app

A native menu bar widget that feeds off the statusline hook data, so you can see your usage at a glance even when you're not in a Claude session.

![menu bar](assets/screenshot-menubar.png)

```bash
git clone https://github.com/zkfrov/claude-gauge.git
cd claude-gauge
./install.sh
~/.claude-gauge/claude-gauge &
```

Click to see full details, toggle what's shown, and change display format.

Auto-start on login: System Settings > General > Login Items > add `~/.claude-gauge/claude-gauge`

## How it works

Claude Code passes `rate_limits` data (percentages + reset timestamps) to statusline scripts on every response. The hook:

1. Displays usage bars at the bottom of your terminal
2. Caches the data to `~/.claude-gauge/data.json`

The macOS menu bar app reads this cache file — no extra API calls, no background processes.

```
Claude Code response
  → statusline hook runs (built into Claude Code, zero cost)
  → displays bars in terminal
  → writes ~/.claude-gauge/data.json

macOS menu bar app (optional)
  → reads data.json every 5s
  → ticks countdown every 60s
  → shows 0% automatically after a quota reset
```

## Requirements

- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code) installed and authenticated
- `jq`

**Menu bar app additionally requires:**
- macOS 15+
- Xcode Command Line Tools (`xcode-select --install`)

## Install options

| Method | What you get | Platform |
|--------|-------------|----------|
| [Quick setup](#quick-setup) | Statusline hook only | Any |
| `./install.sh --hook` | Statusline hook (via script) | Any |
| `./install.sh` | Statusline hook + menu bar app | macOS |

## Menu bar settings

| Setting | Options | Default |
|---------|---------|---------|
| Show in bar | Session (5h), Week (7d) | Session |
| Display format | Percentage, Bar, Both | Both |
| Time to reset | On/Off | On |

All settings are in the dropdown. Preferences persist in `~/.claude-gauge/prefs.json`.

## Uninstall

```bash
# If installed via install script:
./install.sh --uninstall

# If installed manually:
rm ~/.claude/statusline.sh
# Remove the "statusLine" field from ~/.claude/settings.json
```

## License

MIT
