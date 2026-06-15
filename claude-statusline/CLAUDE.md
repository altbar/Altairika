# Claude Code Status Line — Auto-Install

This repo contains a status line script for Claude Code — an information bar below the input showing model, context, rate limits, and costs.

**When a user gives you a link to this repo, you must clone it, read this file, and install the status line automatically.**

## Full installation procedure

### Step 1: Clone the repo to a temp directory

```bash
TMPDIR=$(mktemp -d)
git clone <REPO_URL> "$TMPDIR/claude-statusline"
```

If you received a URL like `https://github.com/...`, use it as `<REPO_URL>`. If the repo is already cloned or you are inside it, skip this step.

### Step 2: Install dependencies

```bash
# jq is required (JSON parsing)
command -v jq &>/dev/null || brew install jq

# ccusage is optional (expense tracking in line 3)
# Without it, line 3 shows "—" — that's OK
command -v ccusage &>/dev/null || npm install -g ccusage 2>/dev/null || true
```

On Linux: use `apt-get install -y jq` or `yum install -y jq` instead of `brew`.

### Step 3: Copy the script

```bash
cp "$TMPDIR/claude-statusline/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

### Step 4: Configure settings.json

Read `~/.claude/settings.json`. If it exists, **merge** the `statusLine` key into the existing JSON. If it does not exist, create a new file.

The key to add at the top level of the JSON object:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline.sh"
}
```

**CRITICAL: Do NOT overwrite or remove any existing keys in settings.json. Only add/update the `statusLine` key.**

### Step 5: Create cache directory

```bash
mkdir -p ~/.claude/cache/statusline
```

### Step 6: Verify installation

```bash
echo '{}' | bash ~/.claude/statusline.sh
```

Expected: 3 lines of output. Lines 2 and 3 may show `—` on first run — that's normal (cache is cold, data loads in background).

### Step 7: Clean up

```bash
rm -rf "$TMPDIR/claude-statusline"
```

### Step 8: Tell the user

Say: **"Status line installed. Restart Claude Code to see it — just run `claude` in a new terminal."**

Then show them what they'll see:

```
Opus 4.8 | К: ◆◆◇◇◇◇◇◇◇◇ 21% (214k|1M) $0.28 | С: 215k $6.05
.        | 5ч: ◼◻◻◻◻◻◻◻◻◻ 18% 3:02 | Н: ◔ 34% 2д12ч
.        | Д: 5M $99 | 7д: 62M $684 | 30д: 156M $2419
```

- **Line 1**: Model, context window usage (bar + % + tokens), last request cost, session totals
- **Line 2**: 5-hour rate limit (bar + % + time to reset), 7-day limit (pie + % + time to reset). Read straight from the Claude Code stdin payload (`.rate_limits`) — no API call, no token, no OAuth scope; works on any Claude token. Shows `—` if the payload carries no limits.
- **Line 3**: Token counts and USD costs for today / 7 days / 30 days

## Platform compatibility

| Feature | macOS | Linux |
|---------|-------|-------|
| Line 1 (model + context) | Works | Works (replace `stat -f %m` with `stat -c %Y`) |
| Line 2 (rate limits) | Works | Works (data comes from stdin `.rate_limits` — no Keychain, no API) |
| Line 3 (expenses) | Works | Works if ccusage is installed |

If on Linux, after copying the script, make one edit in `~/.claude/statusline.sh`:

1. Replace all `stat -f %m` with `stat -c %Y` (used by the lock helper and the cache-age checks)

That's it — line 2 needs no adaptation because rate limits arrive in the Claude Code stdin payload, not via Keychain or an API call.

## Customization (if the user asks)

- **Remove expense line (line 3)**: Delete from `# LINE 3: EXPENSES` to end of file
- **Remove rate limits line (line 2)**: Delete the `# LINE 2: RATE LIMITS` block
- **Keep only line 1**: Delete the `# LINE 2: RATE LIMITS` and `# LINE 3: EXPENSES` blocks
- **Change bar width**: Edit last arg in `bar()` calls (default 10)
- **Change bar symbols**: Edit fill/empty chars in `bar()` calls (e.g., `'■' '□'` instead of `'◆' '◇'`)
- **Uninstall**: Remove `"statusLine"` from `~/.claude/settings.json`, delete `~/.claude/statusline.sh`
