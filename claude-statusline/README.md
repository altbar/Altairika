# Claude Code Status Line

Custom status bar for Claude Code — shows model, context, rate limits, and costs in real time.

```
 Opus 4.6 | К: ◆◆◆◆◆◇◇◇◇◇ 76% (128k|200k) $0.28 | С: 162k $6.05
 .        | 5ч: ◼◼◼◼◻◻◻◻◻◻ 38% 0:14 | Н: ◑ 61% 3д2ч
 .        | Д: 2M $35 | 7д: 21M $464 | 30д: 115M $1228
```

## Quick Install

Give this repo URL to your Claude Code and say: **"Install this status line"**

Claude will clone the repo, install dependencies, copy the script, update settings, and verify — fully automatic.

## Manual Install

```bash
# 1. Dependencies
brew install jq
npm install -g ccusage  # optional, for expense tracking

# 2. Copy script
cp statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh

# 3. Add to ~/.claude/settings.json (merge into existing file if present)
# "statusLine": { "type": "command", "command": "bash ~/.claude/statusline.sh" }

# 4. Restart Claude Code
```

## What each element means

### Line 1 — Model + Context + Session

| Element | Example | Meaning |
|---------|---------|---------|
| `Opus 4.6` | | Current model |
| `К:` | `◆◆◆◆◆◇◇◇◇◇` | Context window usage bar (`◆` used, `◇` free) |
| `76%` | | Context utilization |
| `(128k\|200k)` | | (tokens used \| window size) |
| `$0.28` | | Last request cost |
| `С:` | `162k $6.05` | Session totals: tokens + cost |

### Line 2 — Rate Limits

| Element | Example | Meaning |
|---------|---------|---------|
| `5ч:` | `◼◼◼◼◻◻◻◻◻◻ 38%` | 5-hour limit: bar + % |
| `0:14` | | Time until 5h reset (hours:minutes) |
| `Н:` | `◑ 61%` | 7-day limit: pie icon + % |
| `3д2ч` | | Time until 7-day reset |

Pie icons: `○` ≤20% · `◔` ≤40% · `◑` ≤60% · `◕` ≤80% · `●` >80%

> Cached 15 min. Requires Claude Max subscription.

### Line 3 — Expenses

| Element | Example | Meaning |
|---------|---------|---------|
| `Д:` | `2M $35` | Today's tokens + cost |
| `7д:` | `21M $464` | Last 7 days |
| `30д:` | `115M $1228` | Last 30 days |

> Cached 60 sec. Requires `ccusage` CLI.

## Customization

| What | How |
|------|-----|
| Remove expenses (line 3) | Delete `# LINE 3: EXPENSES` block from `statusline.sh` |
| Remove limits (line 2) | Delete `# LINE 2: LIMITS` block from `statusline.sh` |
| Change bar width | Edit last arg in `bar()` calls (default: 10) |
| Change bar symbols | Edit fill/empty chars, e.g. `'■' '□'` instead of `'◆' '◇'` |
| Uninstall | Remove `"statusLine"` from `~/.claude/settings.json`, delete `~/.claude/statusline.sh` |

## Platform

- **macOS**: works out of the box
- **Linux**: lines 1 + 3 work; line 2 needs Keychain replaced with `~/.claude/.credentials.json` + `stat -f %m` → `stat -c %Y`
