# cmux-auto-resume.zsh — restore Claude Code sessions on cmux restart
#
# Tested: cmux 0.64.3
#
# cmux 0.64.3 regressions vs 0.63.x — workarounds in this script:
#   1. `new-workspace --command "X"` is silently dropped (workspace is
#      created with empty shell, command never runs).
#      → Don't use --command. Always send via `cmux send` after creation.
#   2. cmux closes the pty-write socket after a short idle gap. Waiting
#      30s between two `cmux send` calls returns "Broken pipe (errno 32)".
#      → Issue all sends in a tight loop (no inter-send sleeps).
#      → Stagger claude startup *inside the target shell* with `sleep N &&`.
#   3. New workspaces are created with lazy pty: send-output is silently
#      buffered until something focuses the workspace.
#      → Create with `--focus true`. Costs a brief flash of each tab in
#      the UI but guarantees pty is alive when send hits.
#   4. `cmux tree` shows stale `surface:N`/`tty=ttysNN` from the previous
#      cmux process; sending to those refs returns "Surface is not a terminal".
#      → Match by workspace name, never trust surface refs from tree.
#
# Pacing intent: 14 sessions × 30s shell-sleep ≈ 7min until all alive.
# That avoids spawning 14 simultaneous claude processes (RAM/CPU spike,
# potential Anthropic rate-limit on parallel auth, plus 14 statusline.sh
# starts that would otherwise stampede ccusage even with the flock).

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

  # Remember current workspace so we can return focus at the end
  local origin_ws="$CMUX_WORKSPACE_ID"

  _log "starting staggered restore (socket=$sock_id), running in background"

  # Detach: shell-side stagger means total wall time is short on our side
  ( python3 - "$CMUX" "$RESTORE" "$LOG" "$origin_ws" << 'PYEOF' </dev/null &>/dev/null &
import json, subprocess, time, sys, re

CMUX, RESTORE, LOGF, ORIGIN_WS = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
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

def list_workspaces():
    """Returns list of (ref, name, selected). Names can repeat."""
    out = subprocess.run([CMUX, "list-workspaces"], capture_output=True, text=True, timeout=5).stdout
    items = []
    for line in out.strip().split("\n"):
        m = re.search(r'(workspace:\d+)\s+(.*?)(?:\s+\[selected\])?$', line.strip().lstrip("* "))
        if m:
            items.append({"ref": m.group(1), "name": m.group(2).strip(),
                          "selected": "[selected]" in line, "consumed": False})
    return items

def ttys_with_claude():
    """Set of TTYs where a real `claude` binary is running.
    Match only on the binary path (first whitespace-delimited token);
    `claude --settings` carries hook JSON that contains 'claude-hook',
    so substring matches give false positives on every live process."""
    out = subprocess.run(["ps", "-eo", "tty,command"], capture_output=True, text=True, timeout=5).stdout
    ttys = set()
    for line in out.strip().split("\n")[1:]:
        parts = line.split(None, 1)
        if len(parts) < 2: continue
        tty, cmd = parts[0], parts[1]
        bin_path = cmd.split(None, 1)[0]
        if bin_path == "claude" or bin_path.endswith("/claude"):
            ttys.add(tty)
    return ttys

def workspace_tty(ws_ref):
    """Best-effort tty for a workspace via `tree`. Result may be stale —
    only use it for live-claude detection on workspaces that already
    existed before this script ran."""
    out = subprocess.run([CMUX, "tree", "--workspace", ws_ref],
                         capture_output=True, text=True, timeout=5).stdout
    m = re.search(r'tty=(\S+)', out)
    return m.group(1) if m else None

workspaces = list_workspaces()
live_ttys = ttys_with_claude()
L(f"cmux has {len(workspaces)} workspaces; {len(live_ttys)} ttys with live claude")

# Plan
def find_workspace_for(name, allow_live=False):
    """Find unconsumed workspace by exact name. Skip ones with live claude
    unless allow_live=True (then return live one as 'skip-live' signal)."""
    for w in workspaces:
        if w["consumed"] or w["name"] != name: continue
        tty = workspace_tty(w["ref"])
        if tty and tty in live_ttys:
            if allow_live:
                w["consumed"] = True
                return ("live", w)
            continue
        w["consumed"] = True
        return ("empty", w)
    return None

plan = []  # list of (action, entry, workspace_or_None)
for entry in restore:
    name = entry.get("workspaceName", "Claude Code")
    found = find_workspace_for(name, allow_live=True)
    if found is None:
        plan.append(("create", entry, None))
    else:
        kind, w = found
        if kind == "live":
            plan.append(("skip-live", entry, w))
        else:
            plan.append(("send", entry, w))

skip_n = sum(1 for a,_,_ in plan if a == "skip-live")
send_n = sum(1 for a,_,_ in plan if a == "send")
create_n = sum(1 for a,_,_ in plan if a == "create")
L(f"plan: skip-live={skip_n}, send={send_n}, create={create_n}")

work = [(a,e,w) for a,e,w in plan if a != "skip-live"]
total = len(work)

PAUSE_BETWEEN = 0.5   # short — keeps cmux session warm, no Broken pipe
SHELL_STAGGER = 30    # seconds between successive claude startups
FLAGS = "--dangerously-skip-permissions"

for i, (action, entry, w) in enumerate(work):
    sid = entry["sessionId"]
    cwd = entry.get("cwd", "/Users/uk")
    name = entry.get("workspaceName", "Claude Code")
    delay = i * SHELL_STAGGER
    if delay == 0:
        cmd = f"claude --resume {sid} {FLAGS}"
    else:
        cmd = f"sleep {delay} && claude --resume {sid} {FLAGS}"

    try:
        if action == "create":
            # --focus true forces pty to be created immediately. Without it,
            # cmux 0.64.3 lazily creates the pty on first focus — meanwhile
            # any `send` is silently buffered and may never arrive.
            r = subprocess.run([CMUX, "new-workspace", "--name", name,
                               "--cwd", cwd, "--focus", "true"],
                              capture_output=True, text=True, timeout=10)
            # parse new ws ref from stdout (e.g. "workspace:42 created")
            m = re.search(r'(workspace:\d+)', r.stdout + r.stderr)
            if not m:
                L(f"[{i+1}/{total}] FAIL create '{name}': no ref returned ({r.stdout!r}/{r.stderr!r})")
                continue
            new_ref = m.group(1)
            time.sleep(0.3)  # let shell init enough to accept input
            r2 = subprocess.run([CMUX, "send", "--workspace", new_ref, f"{cmd}\n"],
                              capture_output=True, text=True, timeout=5)
            if r2.returncode != 0:
                L(f"[{i+1}/{total}] FAIL send-after-create {new_ref}: {r2.stderr.strip()[:200]}")
            else:
                L(f"[{i+1}/{total}] created+sent {new_ref} '{name[:40]}' delay={delay}s sid={sid[:8]}")
        else:  # send (workspace exists, possibly with empty pty)
            ws_ref = w["ref"]
            r = subprocess.run([CMUX, "send", "--workspace", ws_ref, f"{cmd}\n"],
                              capture_output=True, text=True, timeout=5)
            if r.returncode != 0:
                L(f"[{i+1}/{total}] FAIL send {ws_ref} '{name[:40]}': {r.stderr.strip()[:200]}")
            else:
                L(f"[{i+1}/{total}] sent {ws_ref} '{name[:40]}' delay={delay}s sid={sid[:8]}")
    except Exception as ex:
        L(f"[{i+1}/{total}] EXC {action} '{name[:40]}': {ex}")

    # Short pause keeps cmux's pty-socket alive without idling it out.
    # Long pause (>~5s) reproducibly causes "Broken pipe" on next send.
    time.sleep(PAUSE_BETWEEN)

# Restore focus to the workspace that triggered this restore (the user's
# "current" tab). Without this, the last-created workspace stays focused.
try:
    out = subprocess.run([CMUX, "list-workspaces"], capture_output=True, text=True, timeout=5).stdout
    # ORIGIN_WS is a UUID; list-workspaces doesn't show UUIDs by default.
    # Find by `--id-format both` instead.
    out2 = subprocess.run([CMUX, "--id-format", "both", "list-workspaces"],
                         capture_output=True, text=True, timeout=5).stdout
    origin_ref = None
    for line in out2.split("\n"):
        if ORIGIN_WS in line:
            m = re.search(r'(workspace:\d+)', line)
            if m: origin_ref = m.group(1); break
    if origin_ref:
        # Focus first pane of the origin workspace
        out3 = subprocess.run([CMUX, "list-panes", "--workspace", origin_ref],
                             capture_output=True, text=True, timeout=5).stdout
        m_pane = re.search(r'(pane:\d+)', out3)
        if m_pane:
            subprocess.run([CMUX, "focus-pane", "--pane", m_pane.group(1),
                           "--workspace", origin_ref], capture_output=True, timeout=5)
            L(f"focus restored to {origin_ref} ({m_pane.group(1)})")
        else:
            L(f"focus-restore: no pane found in {origin_ref}")
    else:
        L(f"focus-restore: origin ws ${ORIGIN_WS[:8]}.. not found in list")
except Exception as ex:
    L(f"focus-restore FAIL: {ex}")

# Close empty default workspace "~" cmux creates on start
try:
    out2 = subprocess.run([CMUX, "list-workspaces"], capture_output=True, text=True, timeout=5).stdout
    for line in out2.strip().split("\n"):
        m = re.search(r'(workspace:\d+)\s+(~)\s*(?:\[selected\])?$', line.strip().lstrip("* "))
        if m:
            subprocess.run([CMUX, "close-workspace", "--workspace", m.group(1)],
                           capture_output=True, timeout=5)
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
