#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

SERVER="$DIR/llama-server"

MODEL_BIG="/mnt/archy/gguf-models/big.gguf"
MODEL_SMALL="/mnt/archy/gguf-models/small.gguf"

HOST="0.0.0.0"

LOG_DIR="$DIR/logs"
PID_DIR="$DIR/pids"

# =========================================================
# GRAMMAR (GBNF for agent mode)
# =========================================================
GRAMMAR_FILE="$DIR/grammar/agent.gbnf"

mkdir -p "$LOG_DIR" "$PID_DIR"

# =========================================================
# REASONING MODE (balanced creativity + accuracy)
# =========================================================
start_reason() {
  NAME="reason"
  PORT=8083
  MODEL="$MODEL_BIG"

  echo "[llm] starting reasoning model..."

  PID_FILE="$PID_DIR/${NAME}.pid"
  LOG_FILE="$LOG_DIR/${NAME}.log"

  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[llm] reasoning already running"
    exit 0
  fi

  nohup "$SERVER" \
    --model "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --ctx-size 32768 \
    --batch-size 1024 \
    --ubatch-size 64 \
    --n-gpu-layers -1 \
    --cache-type-k q5_1 \
    --cache-type-v q5_1 \
    --jinja \
    --parallel 1 \
    --cont-batching \
    --no-mmap \
    --temperature 0.8 \
    --top-k 40 \
    --top-p 0.9 \
    > "$LOG_FILE" 2>&1 &

  echo $! > "$PID_FILE"
  echo "[llm] reasoning started (PID $(cat "$PID_FILE"))"
}

stop_reason() {
  NAME="reason"
  PID_FILE="$PID_DIR/${NAME}.pid"

  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "[llm] reasoning stopped"
  else
    echo "[llm] reasoning not running"
  fi
}

# =========================================================
# AUTOCOMPLETE (FAST / LOW LATENCY / DETERMINISTIC)
# =========================================================
start_autocomplete() {
  NAME="autocomplete"
  PORT=8081
  MODEL="$MODEL_SMALL"

  echo "[llm] starting autocomplete..."

  PID_FILE="$PID_DIR/${NAME}.pid"
  LOG_FILE="$LOG_DIR/${NAME}.log"

  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[llm] autocomplete already running"
    exit 0
  fi

  nohup "$SERVER" \
    --model "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --ctx-size 2048 \
    --batch-size 128 \
    --ubatch-size 32 \
    --n-gpu-layers 0 \
    --cache-type-k q5_1 \
    --cache-type-v q5_1 \
    --jinja \
    --parallel 1 \
    --cont-batching \
    --no-mmap \
    --temperature 0.4 \
    --top-k 20 \
    --top-p 0.8 \
    > "$LOG_FILE" 2>&1 &

  echo $! > "$PID_FILE"
  echo "[llm] autocomplete started (PID $(cat "$PID_FILE"))"
}

stop_autocomplete() {
  NAME="autocomplete"
  PID_FILE="$PID_DIR/${NAME}.pid"

  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "[llm] autocomplete stopped"
  else
    echo "[llm] autocomplete not running"
  fi
}

# =========================================================
# AGENT MODE (GBNF CONSTRAINED OUTPUT + BALANCED SAMPLING)
# =========================================================
start_agent() {
  NAME="agent"
  PORT=8083
  MODEL="$MODEL_BIG"

  echo "[llm] starting agent model..."

  PID_FILE="$PID_DIR/${NAME}.pid"
  LOG_FILE="$LOG_DIR/${NAME}.log"

  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
    echo "[llm] agent already running"
    exit 0
  fi

  if [[ ! -f "$GRAMMAR_FILE" ]]; then
    echo "[llm] ERROR: grammar file not found:"
    echo "       $GRAMMAR_FILE"
    exit 1
  fi

  nohup "$SERVER" \
    --model "$MODEL" \
    --host "$HOST" \
    --port "$PORT" \
    --ctx-size 32768 \
    --batch-size 1024 \
    --ubatch-size 64 \
    --n-gpu-layers -1 \
    --cache-type-k q5_1 \
    --cache-type-v q5_1 \
    --jinja \
    --grammar-file "$GRAMMAR_FILE" \
    --parallel 1 \
    --cont-batching \
    --no-mmap \
    --temperature 0.6 \
    --top-k 40 \
    --top-p 0.9 \
    > "$LOG_FILE" 2>&1 &

  echo $! > "$PID_FILE"
  echo "[llm] agent started (PID $(cat "$PID_FILE"))"
}

stop_agent() {
  NAME="agent"
  PID_FILE="$PID_DIR/${NAME}.pid"

  if [[ -f "$PID_FILE" ]]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null || true
    rm -f "$PID_FILE"
    echo "[llm] agent stopped"
  else
    echo "[llm] agent not running"
  fi
}

# =========================================================
# STATUS
# =========================================================
status() {
  for NAME in reason agent autocomplete; do
    PID_FILE="$PID_DIR/${NAME}.pid"

    if [[ -f "$PID_FILE" ]]; then
      PID=$(cat "$PID_FILE")
      if kill -0 "$PID" 2>/dev/null; then
        echo "[llm] $NAME RUNNING (PID $PID)"
      else
        echo "[llm] $NAME STALE PID"
      fi
    else
      echo "[llm] $NAME STOPPED"
    fi
  done
}

# =========================================================
# CLI
# =========================================================
case "${1:-}" in
  start-reason)
    start_reason
    ;;
  stop-reason)
    stop_reason
    ;;
  start-autocomplete)
    start_autocomplete
    ;;
  stop-autocomplete)
    stop_autocomplete
    ;;
  start-agent)
    start_agent
    ;;
  stop-agent)
    stop_agent
    ;;
  status)
    status
    ;;
  *)
    echo "Usage:"
    echo "  llm start-reason"
    echo "  llm stop-reason"
    echo "  llm start-autocomplete"
    echo "  llm stop-autocomplete"
    echo "  llm start-agent"
    echo "  llm stop-agent"
    echo "  llm status"
    ;;
esac
