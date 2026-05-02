# cmux-auto-resume.zsh — restore Claude Code sessions on cmux restart
#
# Behaviour:
#   - Triggered from ~/.zshrc on every shell startup
#   - One restore per cmux lifecycle (socket inode lock)
#   - Deduplicates restore.json by sessionId (keeps latest savedAt)
#   - cmux v0.63.2 restores workspace TABS but NOT processes inside —
#     each restored workspace has an empty shell. We need to start
#     claude in each.
#   - For each session in restore.json:
#       * if a workspace with that name exists AND has live claude
#         in its tty (ps check) → skip (already running)
#       * if a workspace with that name exists with empty shell
#         → cmux send "claude --resume X" + Enter to its tty
#       * if no such workspace exists → create with `new-workspace --command`
#   - Stagger: 30s pause between starts. Avoids:
#       * spawning N parallel claude processes (CPU/RAM spike)
#       * triggering Anthropic API rate limits
#       * 14 statusline.sh forking 14 parallel ccusage processes
#       * (latter is also gated by flock in statusline.sh now)
#   - Whole loop runs in background (&) so shell isn't blocked
#     for ~7 minutes (14 sessions × 30s)

_cmux_auto_resume() {
  local LOG="$HOME/.claude/logs/cmux-resume-zsh.log"
  echo "$(date '+%H:%M:%S'): ENTER cmux_auto_resume CMUX_WS=$CMUX_WORKSPACE_ID" >> "$LOG"

  [[ -z "$CMUX_WORKSPACE_ID" ]] && { echo "$(date '+%H:%M:%S'): EXIT no CMUX_WORKSPACE_ID" >> "$LOG"; return; }

  local CMUX="/Applications/cmux.app/Contents/Resources/bin/cmux"
  local RESTORE="$HOME/.claude/cmux-restore.json"
  local LOCK="$HOME/.claude/cmux-restore.lock"
  _log() { echo "$(date '+%H:%M:%S'): $*" >> "$LOG"; }

  [[ ! -x "$CMUX" ]] && { _log "EXIT cmux not found"; return; }
  [[ ! -f "$RESTORE" ]] && { _log "EXIT no restore file"; return; }

  # Socket inode lock — one restore per cmux lifecycle
  local sock="$HOME/Library/Application Support/cmux/cmux.sock"
  [[ ! -S "$sock" ]] && return
  local sock_id=$(stat -f%i "$sock" 2>/dev/null)
  [[ -z "$sock_id" ]] && return
  if [[ -f "$LOCK" ]] && [[ "$(cat "$LOCK" 2>/dev/null)" == "$sock_id" ]]; then
    return
  fi
  echo "$sock_id" > "$LOCK"

  _log "starting staggered restore (socket=$sock_id), running in background"

  # Detach: 14 sessions × 30s ≈ 7 min, do not block this shell
  ( python3 - "$CMUX" "$RESTORE" "$LOG" << 'PYEOF' </dev/null &>/dev/null &
import json, subprocess, time, sys, re

CMUX, RESTORE, LOGF = sys.argv[1], sys.argv[2], sys.argv[3]
log = open(LOGF, "a")
def L(msg): log.write(f"  {msg}\n"); log.flush()

raw = json.loads(open(RESTORE).read())

# Dedup by sessionId — keep most recent by savedAt
seen = {}
for e in raw:
    sid = e.get("sessionId")
    if not sid: continue
    if sid not in seen or e.get("savedAt", "") > seen[sid].get("savedAt", ""):
        seen[sid] = e
restore = list(seen.values())
L(f"dedup: {len(raw)} -> {len(restore)} entries")

def parse_tree():
    """Parse `cmux tree --all` → list of {ref, name, tty}."""
    out = subprocess.run([CMUX, "tree", "--all"], capture_output=True, text=True, timeout=5).stdout
    items = []
    cur = None
    for line in out.split("\n"):
        m_ws = re.search(r'workspace (workspace:\d+)\s+"([^"]*)"', line)
        if m_ws:
            cur = {"ref": m_ws.group(1), "name": m_ws.group(2), "tty": None, "consumed": False}
            items.append(cur)
            continue
        m_tty = re.search(r'tty=(\S+)', line)
        if m_tty and cur and cur["tty"] is None:
            cur["tty"] = m_tty.group(1)
    return items

def ttys_with_claude():
    """Set of TTYs where a real `claude` process is running.

    NB: `--settings` carries a JSON blob mentioning "claude-hook"; never
    substring-match against the full cmd. We only check the binary path —
    first whitespace-separated token.
    """
    out = subprocess.run(["ps", "-eo", "tty,command"], capture_output=True, text=True, timeout=5).stdout
    ttys = set()
    for line in out.strip().split("\n")[1:]:
        parts = line.split(None, 1)
        if len(parts) < 2: continue
        tty, cmd = parts[0], parts[1]
        bin_path = cmd.split(None, 1)[0]
        # Match: /opt/homebrew/bin/claude, /usr/local/bin/claude, bare 'claude'
        if bin_path == "claude" or bin_path.endswith("/claude"):
            ttys.add(tty)
    return ttys

workspaces = parse_tree()
live_ttys = ttys_with_claude()
L(f"cmux has {len(workspaces)} workspaces; {len(live_ttys)} ttys with live claude")

FLAGS = "--dangerously-skip-permissions"
PAUSE = 30  # seconds between session starts

def find_empty_workspace(name):
    """Find workspace by name with empty shell (no live claude). Mark consumed."""
    for w in workspaces:
        if w["consumed"] or w["name"] != name: continue
        if w["tty"] and w["tty"] in live_ttys:
            continue  # has live claude — skip
        w["consumed"] = True
        return w
    return None

def find_live_workspace(name):
    """Workspace with this name where claude already runs."""
    for w in workspaces:
        if w["name"] != name: continue
        if w["tty"] and w["tty"] in live_ttys:
            return w
    return None

# Plan actions
plan = []  # list of (action, entry, workspace_or_None)
for entry in restore:
    name = entry.get("workspaceName", "Claude Code")
    live = find_live_workspace(name)
    if live:
        plan.append(("skip-live", entry, live))
        continue
    empty = find_empty_workspace(name)
    if empty:
        plan.append(("send", entry, empty))
    else:
        plan.append(("create", entry, None))

skip_n = sum(1 for a,_,_ in plan if a == "skip-live")
send_n = sum(1 for a,_,_ in plan if a == "send")
create_n = sum(1 for a,_,_ in plan if a == "create")
L(f"plan: skip-live={skip_n}, send={send_n}, create={create_n}")

work = [(a,e,w) for a,e,w in plan if a != "skip-live"]
total = len(work)

for i, (action, entry, w) in enumerate(work, 1):
    sid = entry["sessionId"]
    cwd = entry.get("cwd", "/Users/uk")
    name = entry.get("workspaceName", "Claude Code")
    cmd = f"claude --resume {sid} {FLAGS}"
    try:
        if action == "send":
            subprocess.run([CMUX, "send", "--workspace", w["ref"], cmd],
                          capture_output=True, timeout=5)
            subprocess.run([CMUX, "send-key", "--workspace", w["ref"], "Enter"],
                          capture_output=True, timeout=5)
            L(f"[{i}/{total}] send -> {w['ref']} ({name}, tty={w['tty']}) sid={sid[:8]}")
        else:  # create
            subprocess.run([CMUX, "new-workspace", "--name", name, "--cwd", cwd, "--command", cmd],
                          capture_output=True, timeout=10)
            L(f"[{i}/{total}] create -> {name} sid={sid[:8]}")
    except Exception as ex:
        L(f"[{i}/{total}] FAIL {name}: {ex}")
    if i < total:
        time.sleep(PAUSE)

# Close empty default workspace "~" cmux creates on start
try:
    out2 = subprocess.run([CMUX, "list-workspaces"], capture_output=True, text=True, timeout=5).stdout
    for line in out2.strip().split("\n"):
        m = re.search(r'(workspace:\d+)\s+(~)\s*(?:\[selected\])?$', line.strip().lstrip("* "))
        if m:
            subprocess.run([CMUX, "close-workspace", "--workspace", m.group(1)], capture_output=True, timeout=5)
            L(f"closed empty: {m.group(1)}")
            break
except Exception as ex:
    L(f"close-empty FAIL: {ex}")

L(f"done: {send_n} sent + {create_n} created (skipped {skip_n} live)")
log.close()
PYEOF
  ) &
  _log "background restore launched (pid=$!)"
}

_cmux_auto_resume
