#!/bin/sh
# Automated agent handoff (ADR 0004). Runs from .githooks/post-commit after
# every commit: reads the TASKS.md board, decides which agent has actionable
# work, and dispatches it. All *judgment* lives in the agents (their session
# prompts tell them to re-verify the board and exit cleanly when nothing is
# actionable); this script is deliberately dumb string-matching.
#
# Dispatch rules (serial by design — one active agent at a time):
#   @claude  <- any open item in "## In Review" (review is the priority path)
#   @codex   <- In Review empty AND no @codex task In Progress AND at least
#               one unchecked (@codex) task in "## Ready"
#
# Safety rails:
#   - kill switch: `touch .handoff/paused` disables all dispatching
#   - dedup: a given (target, board-fingerprint) pair dispatches at most once
#   - rate limit: >=10 minutes between dispatches to the same target
#   - lock: no second dispatch to a target while its previous run is alive
#   - never blocks or fails the commit (exit 0 everywhere)
#
# Claude runs inside Cowork and cannot be spawned from a shell, so the claude
# target drops .handoff/claude.pending; a Cowork scheduled task polls for it.
# If the Claude Code CLI (`claude`) is installed, it is used directly instead.

set -u

repo="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$repo" || exit 0
hd="$repo/.handoff"
mkdir -p "$hd/logs"

log() { echo "agent-handoff: $1"; }

[ -f "$hd/paused" ] && { log "paused (.handoff/paused exists)"; exit 0; }
[ -f "TASKS.md" ] || exit 0

section() {
  awk -v name="$1" '
    $0 ~ "^## "name { f=1; next }
    /^## / { f=0 }
    f' TASKS.md
}

in_review_open="$(section 'In Review' | grep -c '^- \[' || true)"
in_progress_codex="$(section 'In Progress' | grep -c '(@codex)' || true)"
ready_codex="$(section 'Ready' | grep -c '^- \[ \] .*(@codex)' || true)"

target=""
if [ "$in_review_open" -gt 0 ]; then
  target="claude"
elif [ "$in_progress_codex" -eq 0 ] && [ "$ready_codex" -gt 0 ]; then
  target="codex"
fi

[ -z "$target" ] && { log "board has no actionable handoff"; exit 0; }

# Dedup: same board content already dispatched to this target -> skip.
fingerprint="$(git hash-object TASKS.md 2>/dev/null || cksum TASKS.md)"
state_file="$hd/last.$target"
if [ -f "$state_file" ] && [ "$(cat "$state_file")" = "$fingerprint" ]; then
  log "already dispatched $target for this board state"
  exit 0
fi

# Rate limit: 10 min per target.
if [ -f "$state_file" ]; then
  now="$(date +%s)"
  then_="$(stat -f %m "$state_file" 2>/dev/null || stat -c %Y "$state_file" 2>/dev/null || echo 0)"
  if [ $((now - then_)) -lt 600 ]; then
    log "rate-limited ($target dispatched <10min ago)"
    exit 0
  fi
fi

# Lock: previous dispatched run still alive -> skip.
lock="$hd/$target.pid"
if [ -f "$lock" ] && kill -0 "$(cat "$lock")" 2>/dev/null; then
  log "$target run still in progress (pid $(cat "$lock"))"
  exit 0
fi

stamp="$(date +%Y%m%d-%H%M%S)"

dispatch_codex() {
  command -v codex >/dev/null 2>&1 || { log "codex not on PATH; skipped"; return; }
  log "dispatching codex (log: .handoff/logs/codex-$stamp.log)"
  nohup env PAISATRACK_HANDOFF=1 CODEX_SKIP_COMMIT_REVIEW=1 \
    codex exec --full-auto "$(cat scripts/prompts/codex_session.md)" \
    >"$hd/logs/codex-$stamp.log" 2>&1 &
  echo $! >"$lock"
  echo "$fingerprint" >"$state_file"
}

dispatch_claude() {
  if command -v claude >/dev/null 2>&1; then
    log "dispatching claude CLI (log: .handoff/logs/claude-$stamp.log)"
    nohup env PAISATRACK_HANDOFF=1 CODEX_SKIP_COMMIT_REVIEW=1 \
      claude -p "$(cat scripts/prompts/claude_session.md)" --permission-mode acceptEdits \
      >"$hd/logs/claude-$stamp.log" 2>&1 &
    echo $! >"$lock"
  else
    log "claude CLI not found; flagging for the Cowork scheduled task"
    date >"$hd/claude.pending"
  fi
  echo "$fingerprint" >"$state_file"
}

case "$target" in
  codex) dispatch_codex ;;
  claude) dispatch_claude ;;
esac

exit 0
