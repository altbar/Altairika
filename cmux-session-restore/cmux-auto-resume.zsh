# cmux-auto-resume.zsh — restore Claude Code sessions on cmux restart
# Source from ~/.zshrc:
#   [[ -f ~/.claude/scripts/cmux-auto-resume.zsh ]] && source ~/.claude/scripts/cmux-auto-resume.zsh

_cmux_auto_resume() {
  [[ -z "$CMUX_WORKSPACE_ID" ]] && return

  local CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
  local RESTORE="$HOME/.claude/cmux-restore.json"
  local LOCK="$HOME/.claude/cmux-restore.lock"
  local LOG="$HOME/.claude/logs/cmux-resume-zsh.log"
  _log() { echo "$(date '+%H:%M:%S'): $*" >> "$LOG"; }

  [[ ! -x "$CMUX" ]] && return
  [[ ! -f "$RESTORE" ]] && return

  # Socket inode lock — one restore per cmux lifecycle
  local sock="$HOME/Library/Application Support/cmux/cmux.sock"
  [[ ! -S "$sock" ]] && return
  local sock_id=$(stat -f%i "$sock" 2>/dev/null)
  [[ -z "$sock_id" ]] && return
  if [[ -f "$LOCK" ]] && [[ "$(cat "$LOCK" 2>/dev/null)" == "$sock_id" ]]; then
    return
  fi
  echo "$sock_id" > "$LOCK"

  local total=$(python3 -c "import json; print(len(json.loads(open('$RESTORE').read())))" 2>/dev/null)
  [[ "$total" == "0" || -z "$total" ]] && return

  _log "restoring $total sessions (socket=$sock_id)..."

  python3 - "$CMUX" "$RESTORE" "$LOG" << 'PYEOF'
import json, subprocess, time, sys, re

CMUX, RESTORE, LOGF = sys.argv[1], sys.argv[2], sys.argv[3]
restore = json.loads(open(RESTORE).read())
log = open(LOGF, "a")
FLAGS = "--dangerously-skip-permissions"

# Get existing workspaces (cmux may have restored layout)
ws_out = subprocess.run([CMUX, "list-workspaces"], capture_output=True, text=True, timeout=5).stdout
existing = {}
for line in ws_out.strip().split("\n"):
    m = re.search(r'(workspace:\d+)\s+(.*?)(?:\s+\[selected\])?$', line.strip().lstrip("* "))
    if m:
        existing[m.group(2).strip()] = m.group(1)

for entry in restore:
    sid = entry["sessionId"]
    cwd = entry.get("cwd", "/Users/uk")
    name = entry.get("workspaceName", "Claude Code")
    cmd = f"claude --resume {sid} {FLAGS}"

    ws_ref = existing.get(name)
    if ws_ref:
        subprocess.run([CMUX, "send", "--workspace", ws_ref, cmd], capture_output=True, timeout=5)
        subprocess.run([CMUX, "send-key", "--workspace", ws_ref, "Enter"], capture_output=True, timeout=5)
        log.write(f"  resumed in {ws_ref} -> {name}\n")
    else:
        subprocess.run([CMUX, "new-workspace", "--name", name, "--cwd", cwd, "--command", cmd],
                      capture_output=True, timeout=10)
        log.write(f"  created -> {name}\n")
    log.flush()
    time.sleep(0.3)

# Close empty default workspace "~" that cmux creates on start
ws_out2 = subprocess.run([CMUX, "list-workspaces"], capture_output=True, text=True, timeout=5).stdout
for line in ws_out2.strip().split("\n"):
    m = re.search(r'(workspace:\d+)\s+(~)\s*(?:\[selected\])?$', line.strip().lstrip("* "))
    if m:
        subprocess.run([CMUX, "close-workspace", "--workspace", m.group(1)], capture_output=True, timeout=5)
        log.write(f"  closed empty: {m.group(1)}\n")
        break

log.write(f"  done: {len(restore)} sessions\n")
log.close()
PYEOF
  _log "finished"
}

_cmux_auto_resume
