#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/verify.sh [seconds]

Checks the trigger and reports SQLite sequence movement over the requested
interval. The default interval is 30 seconds; use 0 for an immediate check.

Path override:
  CODEX_LOG_DB  Defaults to $CODEX_HOME/logs_2.sqlite
EOF
}

case "${1:-30}" in
  -h|--help)
    usage
    exit 0
    ;;
  *[!0-9]*|'')
    printf 'The interval must be a non-negative integer.\n' >&2
    exit 2
    ;;
esac

interval=${1:-30}
codex_home=${CODEX_HOME:-"$HOME/.codex"}
log_db=${CODEX_LOG_DB:-"$codex_home/logs_2.sqlite"}

if [ ! -f "$log_db" ]; then
  printf 'Codex log database was not found: %s\n' "$log_db" >&2
  exit 1
fi

sql() {
  sqlite3 -cmd '.timeout 5000' "$log_db" "$1"
}

trigger_count=$(sql \
  "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name='codex_drop_logs_below_warn';")
if [ "$trigger_count" != 1 ]; then
  printf 'Trigger is not installed: codex_drop_logs_below_warn\n' >&2
  exit 1
fi

suppressed_changes=$(sql "BEGIN; INSERT INTO logs \
  (ts, ts_nanos, level, target, estimated_bytes) \
  VALUES (0, 0, 'INFO', 'codex-write-mitigation-verify', 0); \
  SELECT changes(); ROLLBACK;")
if [ "$suppressed_changes" != 0 ]; then
  printf 'Trigger check failed: an INFO row reached the logs table.\n' >&2
  exit 1
fi

sequence_value() {
  sql "SELECT COALESCE((SELECT seq FROM sqlite_sequence WHERE name='logs'), 0);"
}

rows=$(sql 'SELECT COUNT(*) FROM logs;')
low_rows=$(sql "SELECT COUNT(*) FROM logs WHERE level IN ('TRACE', 'DEBUG', 'INFO');")
before=$(sequence_value)

printf 'Trigger: active and suppressing INFO inserts\n'
printf 'Rows: %s total, %s retained below WARN from before mitigation\n' "$rows" "$low_rows"
printf 'Sequence before: %s\n' "$before"

if [ "$interval" -gt 0 ]; then
  sleep "$interval"
fi

after=$(sequence_value)
delta=$((after - before))
printf 'Sequence after:  %s (%+d over %ss)\n' "$after" "$delta" "$interval"

if [ "$delta" -eq 0 ]; then
  printf 'No accepted log inserts were observed during the interval.\n'
else
  printf 'Accepted WARN or ERROR inserts may account for this movement.\n'
fi
