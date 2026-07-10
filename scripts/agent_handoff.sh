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
if [ -n "${PAISATRACK_FORCE_TARGET:-}" ]; then
  # Human-triggered resume/force (scripts/handoff.sh resume). Bypasses board
  # gating, dedup, and rate limit — never set this from automation.
  target="$PAISATRACK_FORCE_TARGET"
  forced=1
elif [ "$in_review_open" -gt 0 ]; then
  target="claude"
elif [ "$in_progress_codex" -eq 0 ] && [ "$ready_codex" -gt 0 ]; then
  target="codex"
fi

[ -z "$target" ] && { log "board has no actionable handoff"; exit 0; }
forced="${forced:-0}"

# Dedup: same board content already dispatched to this target -> skip.
fingerprint="$(git hash-object TASKS.md 2>/dev/null || cksum TASKS.md)"
state_file="$hd/last.$target"
if [ "$forced" -eq 0 ] && [ -f "$state_file" ] && [ "$(cat "$state_file")" = "$fingerprint" ]; then
  log "already dispatched $target for this board state"
  exit 0
fi

# Rate limit: 10 min per target.
if [ "$forced" -eq 0 ] && [ -f "$state_file" ]; then
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

# Failure latch: if the previous run of this target exited non-zero (expired
# session, crash), the loop pauses itself and stays off until the human runs
# `scripts/handoff.sh on`. Dispatched runs are wrapped so their exit code is
# recorded and a non-zero exit writes .handoff/paused.
latched() { # latched <target>
  if [ -s "$hd/$1.exit" ] && [ "$(cat "$hd/$1.exit")" != "0" ]; then
    log "previous $1 run exited $(cat "$hd/$1.exit") — latching loop OFF (scripts/handoff.sh on to resume)"
    echo "auto-latched: $1 run exited $(cat "$hd/$1.exit") at $(date) — run scripts/handoff.sh on to resume" >"$hd/paused"
    return 0
  fi
  return 1
}

# Per-task model selection: a task block may carry an optional line
#   Model: <model-name> [low|medium|high]
# set by @claude at grooming time (trivial tasks -> cheaper model / lower
# effort; design-heavy tasks -> stronger). Looks at the In Progress (@codex)
# task first (crash resume), then the first Ready (@codex) task. Empty -> CLI
# defaults.
codex_model_line() {
  awk '
    /^## (In Progress|Ready)/ { sec=1; next }
    /^## / { sec=0 }
    !sec { next }
    /^- \[/ && intask { exit }     # first (@codex) task ended without a Model line
    /^- \[ \] .*\(@codex\)/ { intask=1; next }
    intask && /^ +Model: / { sub(/^ +Model: /,""); print; exit }
  ' TASKS.md
}

dispatch_codex() {
  command -v codex >/dev/null 2>&1 || { log "codex not on PATH; skipped"; return; }
  latched codex && return
  model_line="$(codex_model_line)"
  model_args=""
  if [ -n "$model_line" ]; then
    model="$(echo "$model_line" | awk '{print $1}')"
    effort="$(echo "$model_line" | awk '{print $2}')"
    model_args="-m $model"
    case "$effort" in
      low|medium|high) model_args="$model_args -c model_reasoning_effort=$effort" ;;
    esac
    log "task model override: $model_line"
  fi
  log "dispatching codex (log: .handoff/logs/codex-$stamp.log)"
  # network_access: the Flutter test runner binds 127.0.0.1, which the default
  # codex workspace-write sandbox forbids (T-066 run was blocked by this).
  # The codex sandbox keeps .git read-only, so dispatched runs cannot commit.
  # Protocol: codex writes its commit message to .handoff/commit-msg and this
  # wrapper (unsandboxed) commits on its behalf after a clean exit.
  nohup env PAISATRACK_HANDOFF=1 CODEX_SKIP_COMMIT_REVIEW=1 MODEL_ARGS="$model_args" sh -c '
    rm -f .handoff/commit-msg
    # shellcheck disable=SC2086 — MODEL_ARGS is deliberately word-split
    codex exec --full-auto $MODEL_ARGS \
      -c sandbox_workspace_write.network_access=true \
      "$(cat scripts/prompts/codex_session.md)"
    ec=$?
    echo "$ec" > .handoff/codex.exit
    if [ "$ec" -ne 0 ]; then
      echo "auto-latched: codex run exited $ec (session limit/crash?) at $(date) — run scripts/handoff.sh on to resume" > .handoff/paused
    elif [ -s .handoff/commit-msg ] && [ -n "$(git status --porcelain)" ]; then
      # Clear only STALE lock files (>60s) — never a live git operation.
      [ -f .git/index.lock ] && [ -n "$(find .git/index.lock -mmin +1 2>/dev/null)" ] && rm -f .git/index.lock
      git add -A
      if git commit -F .handoff/commit-msg; then
        echo "wrapper: committed on behalf of codex"
        rm -f .handoff/commit-msg
      else
        echo "wrapper: commit FAILED — changes left staged; commit manually with: git commit -F .handoff/commit-msg"
      fi
    fi
  ' >"$hd/logs/codex-$stamp.log" 2>&1 &
  echo $! >"$lock"
  echo "$fingerprint" >"$state_file"
}

dispatch_claude() {
  latched claude && return
  if command -v claude >/dev/null 2>&1; then
    log "dispatching claude CLI (log: .handoff/logs/claude-$stamp.log)"
    nohup env PAISATRACK_HANDOFF=1 CODEX_SKIP_COMMIT_REVIEW=1 sh -c '
      claude -p "$(cat scripts/prompts/claude_session.md)" --permission-mode acceptEdits
      ec=$?
      echo "$ec" > .handoff/claude.exit
      if [ "$ec" -ne 0 ]; then
        echo "auto-latched: claude run exited $ec (session limit/crash?) at $(date) — run scripts/handoff.sh on to resume" > .handoff/paused
      fi
    ' >"$hd/logs/claude-$stamp.log" 2>&1 &
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
