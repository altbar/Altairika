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
Opus 4.6 | К: ◆◆◆◆◆◇◇◇◇◇ 76% (128k|200k) $0.28 | С: 162k $6.05
.        | 5ч: ◼◼◼◼◻◻◻◻◻◻ 38% 0:14 | Н: ◑ 61% 3д2ч
.        | Д: 2M $35 | 7д: 21M $464 | 30д: 115M $1228
```

- **Line 1**: Model, context window usage (bar + % + tokens), last request cost, session totals
- **Line 2**: 5-hour rate limit (bar + % + time to reset), 7-day limit (pie + % + time to reset)
- **Line 3**: Token counts and USD costs for today / 7 days / 30 days

## Platform compatibility

| Feature | macOS | Linux |
|---------|-------|-------|
| Line 1 (model + context) | Works | Works (replace `stat -f %m` with `stat -c %Y`) |
| Line 2 (rate limits) | Works | Needs adaptation: replace `security find-generic-password` with reading `~/.claude/.credentials.json` |
| Line 3 (expenses) | Works | Works if ccusage is installed |

If on Linux, after copying the script, make these two edits in `~/.claude/statusline.sh`:

1. Replace all `stat -f %m` with `stat -c %Y`
2. Replace the `_fetch_lim()` function's token retrieval:
   ```bash
   # macOS (original):
   tk=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
     | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)

   # Linux (replacement):
   tk=$(jq -r '.claudeAiOauth.accessToken // empty' ~/.claude/.credentials.json 2>/dev/null)
   ```

## Customization (if the user asks)

- **Remove expense line (line 3)**: Delete from `# LINE 3: EXPENSES` to end of file
- **Remove rate limits line (line 2)**: Delete the `# LINE 2: LIMITS` block
- **Keep only line 1**: Delete everything after line 98 in the script
- **Change bar width**: Edit last arg in `bar()` calls (default 10)
- **Change bar symbols**: Edit fill/empty chars in `bar()` calls (e.g., `'■' '□'` instead of `'◆' '◇'`)
- **Uninstall**: Remove `"statusLine"` from `~/.claude/settings.json`, delete `~/.claude/statusline.sh`
