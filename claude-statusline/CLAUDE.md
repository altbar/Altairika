# Claude Code Status Line — Auto-Install

This repo contains a status line script for Claude Code — an information bar below the input showing model, context, rate limits, and costs.

**When a user gives you a link to this repo, you must clone it, read this file, and install the status line automatically.**

Updated 2026-08-20.

## Full installation procedure

### Step 1: Clone the repo to a temp directory

```bash
TMPDIR=$(mktemp -d)
git clone --depth 1 https://github.com/altbar/Altairika.git "$TMPDIR/altairika"
SRC="$TMPDIR/altairika/claude-statusline"
```

**Do not pass the URL you were given to `git clone` as-is.** The link people share points
at the subfolder — `https://github.com/altbar/Altairika/tree/main/claude-statusline` — and
cloning that fails with `fatal: repository ... not found`. The status line lives in a
subfolder of a larger repo: clone the repo root (`.../Altairika.git`) and take the script
from `claude-statusline/` inside it, as above.

If the repo is already cloned or you are inside it, skip this step and point `SRC` at the
`claude-statusline` folder.

### Step 2: Install dependencies

`jq` is the only hard requirement — it parses every value on all three lines. Install it
for the platform you are actually on:

```bash
# macOS
command -v jq &>/dev/null || brew install jq
# Linux
command -v jq &>/dev/null || apt-get install -y jq      # or: yum install -y jq
# Windows (Git Bash) — run from PowerShell, then restart the terminal so PATH picks it up
winget install --id jqlang.jq -e --accept-source-agreements --accept-package-agreements
```

**`bc` is no longer a dependency** — the cost delta is computed with `awk`, which is
present everywhere. Do not add `bc` back: it ships with macOS but not with Git Bash on
Windows, and it is missing from minimal Linux images too.

```bash
# ccusage is optional (line 3, expenses) — but if you install it, it MUST be >= 20.
# On 18.x the bundled price snapshot predates the current models and every figure
# collapses to $0. Always install the latest, never pin an old major.
npm install -g ccusage@latest 2>/dev/null || true
ccusage --version   # verify: must print 20.x or newer
```

If `ccusage --version` reports anything below 20, tell the user line 3 will show `$0` until they upgrade — do not silently proceed.

On Windows npm puts the binary in `~/AppData/Roaming/npm`. If `ccusage --version` says
`command not found` there while the package installed fine, that folder is not on Git
Bash's PATH — line 3 stays `—` until it is added.

### Step 3: Copy the script

```bash
cp "$SRC/statusline.sh" ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

No post-copy edits are needed on any platform: the script probes for BSD vs GNU
`stat`/`date` at startup (`_mtime`, `_days_ago`) and adapts on its own.

### Step 4: Configure settings.json

Read `~/.claude/settings.json`. If it exists, **merge** the `statusLine` key into the existing JSON. If it does not exist, create a new file.

The key to add at the top level of the JSON object:

```json
"statusLine": {
  "type": "command",
  "command": "bash ~/.claude/statusline.sh"
}
```

On **Windows**, write an absolute Git Bash path instead of `~`, which is not guaranteed to
expand there:

```json
"statusLine": {
  "type": "command",
  "command": "bash '/c/Users/<USER>/.claude/statusline.sh'"
}
```

**CRITICAL: Do NOT overwrite or remove any existing keys in settings.json. Only add/update the `statusLine` key.**

If the user already has a `statusLine` pointing at a different script, tell them which file
you are replacing it with, and leave their old script on disk — do not delete it.

### Step 5: Create cache directory

```bash
mkdir -p ~/.claude/cache/statusline
```

### Step 6: Verify installation

Feed the script a realistic payload rather than `{}` — `resets_at` is a unix epoch, so
compute it from `now` or the reset times render as `-`:

```bash
now=$(date +%s)
echo "{\"model\":{\"display_name\":\"Opus 5\"},
       \"context_window\":{\"context_window_size\":1000000,
         \"current_usage\":{\"input_tokens\":266000}},
       \"rate_limits\":{\"five_hour\":{\"used_percentage\":18,\"resets_at\":$((now+10800))},
                        \"seven_day\":{\"used_percentage\":34,\"resets_at\":$((now+216000))}}}" \
  | bash ~/.claude/statusline.sh
```

Expected: 3 lines, with line 2 reading `5ч: ◼◻◻◻◻◻◻◻◻◻ 18% 3:00 | Н: ◔ 34% 2д12ч`.
Line 3 may show `—` on the first run — that is normal, the cache is cold and ccusage
fills it in the background (allow ~1 minute, then re-run).

Diagnosing a bad run:

| What you see | Cause |
|---|---|
| `jq не найден — статусбар не работает` | `jq` is not on PATH — step 2 was skipped, or the terminal was not restarted after a Windows install |
| Line 2 reads `5ч: —` and `Н: —` while lines 1 and 3 are fine | Claude Code is too old to send `.rate_limits`, or there is no Pro/Max subscription — see the section below |
| Line 3 reads `Д: —`, `7д: —`, `30д: —` | `ccusage` is missing, or the cache is still cold (wait ~1 min, re-run) |
| Line 3 shows `$0` everywhere | `ccusage` is below 20 — upgrade it, do not patch the script |

### Step 7: Clean up

```bash
rm -rf "$TMPDIR/claude-statusline"
```

### Step 8: Tell the user

Say: **"Status line installed. Restart Claude Code to see it — just run `claude` in a new terminal."**

Then show them what they'll see:

```
Opus 5 | К:  ◼◼◻◻◻◻◻◻◻◻ 26% (266k|1M) $0.21 | С: 266k $11.15
.      | 5ч: ◼◼◼◼◻◻◻◻◻◻ 40% 1:56 | Н: ● 88% 5ч13м
.      | Д: 6M $360 | 7д: 191M $4607 | 30д: 280M $6878
```

- **Line 1**: Model, context window usage (bar + % + tokens), last request cost, session totals
- **Line 2**: 5-hour rate limit (bar + % + time to reset), weekly limit (pie + % + time to reset)
- **Line 3**: Token counts and USD costs for today / 7 days / 30 days

## How line 2 works — do not "fix" it with an API call

The 5-hour and weekly limits come **straight from the stdin payload Claude Code passes to
the status line**: `.rate_limits.{five_hour,seven_day}.{used_percentage, resets_at}`.
No network request, no token, no `user:profile` scope, no cache.

An earlier version of this script polled `https://api.anthropic.com/api/oauth/usage` with
the short-lived claude.ai token from the macOS Keychain. When that token expired the line
froze on a stale cache and rendered `-`. **Never route these two values back through an
API**, and never add a cache for them.

If line 2 renders `5ч: — | Н: —` in real use, the user's Claude Code is too old to send
`.rate_limits` (or there is no Pro/Max subscription) — tell them to update, do not patch
the script.

## Performance invariants — do not weaken these

`statusline.sh` runs on **every redraw in every session**. With many sessions open, any
heavy work must stay behind the `mkdir`-based lock in `_bg_locked`, and:

1. The **stale-lock threshold (1800s) must exceed the slowest guarded job**. At 120s a
   long ccusage run outlived its own lock, the next redraw cleared it as stale and started
   a second copy — which stacked into a pile of 100%-CPU processes and a load average
   around 20.
2. The **cache TTL (900s) must also exceed the run duration**, or the cache expires before
   it is written and ccusage never stops.
3. ccusage runs in the **background QoS band** — `taskpolicy -b nice -n 19`, falling back
   to `nice -n 19` where `taskpolicy` is absent (Linux).
4. The `.tmp` file is **promoted only after its contents are checked**
   (`jq -e '.daily | length > 0'`). A ccusage run killed mid-write still exits 0, so an
   exit-status-only check would move an empty file over a good cache.

## Platform compatibility

| Feature | macOS | Linux | Windows (Git Bash) |
|---------|-------|-------|--------------------|
| Line 1 (model + context) | Works | Works | Works |
| Line 2 (rate limits) | Works | Works — reads stdin, no Keychain involved | Works |
| Line 3 (expenses) | Works | Works if ccusage >= 20 | Works if ccusage >= 20 and `~/AppData/Roaming/npm` is on PATH |

Verified on Windows 11 (Git Bash, jq 1.8.2, ccusage 20.0.20) on 2026-08-20: all three
lines render.

**No per-platform edits to the copied script.** Earlier revisions told you to swap
`stat -f %m` for `stat -c %Y` and `date -v-30d` for `date -d '30 days ago'` by hand on
Linux. The script now picks the right flavour itself, and the shims are written the only
way that actually works in both directions:

- `stat` must be **probed once** (`stat -c %Y . &>/dev/null`), never chained. On GNU, `-f`
  means `--file-system`: `stat -f %m file` prints filesystem info and **exits 0**, so a
  `stat -f %m || stat -c %Y` chain never falls through, and the caller silently gets
  garbage where it expected an mtime.
- `date` may use a chain, because BSD's `-v` fails cleanly on GNU (exit 1, empty stdout):
  `date -v-"$1"d +"$2" 2>/dev/null || date -d "$1 days ago" +"$2"`.

`taskpolicy` exists only on macOS — the script already falls back to `nice -n 19` there,
no edit needed.

## Customization (if the user asks)

- **Remove expense line (line 3)**: Delete from `# LINE 3: EXPENSES` to end of file
- **Remove rate limits line (line 2)**: Delete the `# LINE 2: RATE LIMITS` block
- **Change bar width**: Edit last arg in `bar()` calls (default 10)
- **Change bar symbols**: Edit fill/empty chars in `bar()` calls (e.g. `'■' '□'` instead of `'◼' '◻'`)
- **Add a field**: labels on lines 2-3 are padded with spaces to the width of the longest
  one (`5ч:`) — keep that or the columns drift
- **Uninstall**: Remove `"statusLine"` from `~/.claude/settings.json`, delete `~/.claude/statusline.sh`

Keep the dependency surface at `jq` (plus optional `ccusage`). If a change seems to need
`bc`, `gdate`, `coreutils`, or a GNU-only flag, express it with `awk` or the existing
`_mtime` / `_days_ago` shims instead — every added dependency breaks the one-step install
for somebody.
