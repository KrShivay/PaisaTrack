#!/bin/sh
# Control CLI for the ADR 0004 agent-handoff loop.
#
#   scripts/handoff.sh off     stop: pause the loop and kill any running agent
#   scripts/handoff.sh on      start: clear pause/latch/stale state, evaluate board
#   scripts/handoff.sh status  what's armed, running, latched, and on the board
#   scripts/handoff.sh kick    force one board evaluation (clears dedup only)
#
# The loop also latches itself OFF (.handoff/paused) whenever a dispatched
# agent run exits non-zero — e.g. an expired session or a crash — and will
# not continue until you run `scripts/handoff.sh on`.

set -u
repo="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo"; exit 1; }
cd "$repo" || exit 1
hd=".handoff"
mkdir -p "$hd/logs"

board_count() { # board_count <section> <pattern>
  awk -v name="$1" '$0 ~ "^## "name { f=1; next } /^## / { f=0 } f' TASKS.md \
    | grep -c "$2" 2>/dev/null || true
}

case "${1:-status}" in
  off)
    echo "stopped manually via scripts/handoff.sh at $(date)" >"$hd/paused"
    for a in codex claude; do
      if [ -f "$hd/$a.pid" ] && kill -0 "$(cat "$hd/$a.pid")" 2>/dev/null; then
        kill "$(cat "$hd/$a.pid")" 2>/dev/null && echo "killed running $a (pid $(cat "$hd/$a.pid"))"
      fi
    done
    echo "handoff loop OFF"
    ;;
  on)
    rm -f "$hd/paused" "$hd"/last.* "$hd"/*.exit "$hd"/*.pid "$hd/claude.pending"
    echo "handoff loop ON (pause/latch/state cleared); evaluating board..."
    sh scripts/agent_handoff.sh
    ;;
  kick)
    rm -f "$hd"/last.*
    sh scripts/agent_handoff.sh
    ;;
  resume)
    # Human-triggered restart of a codex run that died (or was blocked) with
    # its task still In Progress. The codex session prompt's CRASH RESUME rule
    # reconciles the working tree and finishes the task.
    if [ -f "$hd/codex.pid" ] && kill -0 "$(cat "$hd/codex.pid")" 2>/dev/null; then
      echo "refusing: codex is still running (pid $(cat "$hd/codex.pid"))"
      exit 1
    fi
    rm -f "$hd/paused" "$hd/last.codex" "$hd/codex.exit" "$hd/codex.pid"
    echo "resuming codex..."
    PAISATRACK_FORCE_TARGET=codex sh scripts/agent_handoff.sh
    ;;
  status)
    if [ -f "$hd/paused" ]; then
      echo "PAUSED/LATCHED: $(cat "$hd/paused")"
    else
      echo "ARMED"
    fi
    for a in codex claude; do
      if [ -f "$hd/$a.pid" ] && kill -0 "$(cat "$hd/$a.pid")" 2>/dev/null; then
        echo "$a: RUNNING (pid $(cat "$hd/$a.pid"))"
      elif [ -f "$hd/$a.exit" ]; then
        echo "$a: idle (last run exited $(cat "$hd/$a.exit"))"
      else
        echo "$a: idle"
      fi
    done
    [ -f "$hd/claude.pending" ] && echo "claude.pending set (awaiting scheduled poll)"
    echo "board: in-review=$(board_count 'In Review' '^- \[') codex-in-progress=$(board_count 'In Progress' '(@codex)') codex-ready=$(board_count 'Ready' '^- \[ \] .*(@codex)')"
    latest="$(ls -t "$hd/logs" 2>/dev/null | head -1)"
    [ -n "${latest:-}" ] && echo "latest log: .handoff/logs/$latest"
    ;;
  *)
    echo "usage: scripts/handoff.sh {on|off|status|kick|resume}"
    exit 1
    ;;
esac
