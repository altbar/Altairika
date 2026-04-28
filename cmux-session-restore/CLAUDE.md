# cmux Session Restore — Auto-Install

This folder contains scripts to automatically restore Claude Code sessions in cmux after a restart.

**When a user gives you a link to this repo, read this file and install everything automatically.**

## Full installation procedure

### Step 1: Install the save hook

Read `~/.claude/settings.json`. Merge a `Stop` hook that saves session state on every Claude session end:

```json
"hooks": {
  "Stop": [
    {
      "hooks": [
        {
          "type": "command",
          "command": "/usr/bin/python3 /Users/uk/.claude/scripts/cc-sessions.py save 2>/dev/null || true",
          "timeout": 10
        }
      ]
    }
  ]
}
```

**CRITICAL: Merge into existing hooks object. Do NOT overwrite other hook events.**

### Step 2: Install the save script

Check if `~/.claude/scripts/cc-sessions.py` exists. If it does, verify it has a `cmd_save` function. If not, the user needs the full cc-sessions.py from the main cldf workspace.

The `save` command maps cmux workspaces to Claude session IDs and writes `~/.claude/cmux-restore.json`.

### Step 3: Copy the restore script

```bash
cp cmux-auto-resume.zsh ~/.claude/scripts/cmux-auto-resume.zsh
```

### Step 4: Add to ~/.zshrc

Append to the end of `~/.zshrc` (if not already there):

```bash
# Auto-resume Claude Code sessions in cmux after restart
[[ -f ~/.claude/scripts/cmux-auto-resume.zsh ]] && source ~/.claude/scripts/cmux-auto-resume.zsh
```

### Step 5: Create log directory

```bash
mkdir -p ~/.claude/logs
```

### Step 6: Verify

```bash
# Should show current sessions
python3 ~/.claude/scripts/cc-sessions.py save
# Should show the restore file
cat ~/.claude/cmux-restore.json | python3 -m json.tool
```

### Step 7: Tell the user

Say: **"Session restore installed. Now when you close and reopen cmux, all Claude Code sessions will automatically resume in their tabs."**

## How it works

1. **Save**: Claude Code `Stop` hook calls `cc-sessions.py save` on every session end -> writes `~/.claude/cmux-restore.json`
2. **Restore**: When cmux starts, each workspace opens zsh -> `~/.zshrc` sources `cmux-auto-resume.zsh` -> script creates workspaces and sends `claude --resume` to each
3. **Lock**: Uses cmux socket inode (unique per cmux lifecycle) to prevent double-restore

## Requirements

- macOS
- cmux (any version)
- Claude Code CLI
- Python 3 (for save script)
- `cc-sessions.py` installed at `~/.claude/scripts/`
