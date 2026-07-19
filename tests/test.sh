#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
tmp_root=$(mktemp -d "${TMPDIR:-/tmp}/codex-write-mitigation.XXXXXX")
trap 'rm -rf "$tmp_root"' EXIT HUP INT TERM

test_home="$tmp_root/home"
codex_home="$test_home/.codex"
package_bin="$codex_home/packages/standalone/current/bin/codex"
command_bin="$test_home/.local/bin/codex"
log_db="$codex_home/logs_2.sqlite"

mkdir -p "$(dirname "$package_bin")" "$(dirname "$command_bin")"
cp /bin/echo "$package_bin"
chmod 755 "$package_bin"

sqlite3 "$log_db" <<'SQL'
CREATE TABLE logs (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  ts INTEGER NOT NULL,
  ts_nanos INTEGER NOT NULL,
  level TEXT NOT NULL,
  target TEXT NOT NULL,
  feedback_log_body TEXT,
  module_path TEXT,
  file TEXT,
  line INTEGER,
  thread_id TEXT,
  process_uuid TEXT,
  estimated_bytes INTEGER NOT NULL DEFAULT 0
);
SQL

run_with_paths() {
  HOME="$test_home" \
  CODEX_HOME="$codex_home" \
  CODEX_COMMAND_BIN="$command_bin" \
  CODEX_PACKAGE_BIN="$package_bin" \
  CODEX_LOG_DB="$log_db" \
  "$@"
}

run_with_paths "$repo_root/scripts/install.sh"

test -x "$package_bin.real"
test -x "$command_bin"
install -m 755 "$repo_root/tests/fixtures/fake-codex" "$package_bin.real"

unset RUST_LOG || true
default_level=$(run_with_paths "$command_bin")
test "$default_level" = warn

explicit_level=$(RUST_LOG=debug run_with_paths "$command_bin")
test "$explicit_level" = debug

sqlite3 "$log_db" <<'SQL'
INSERT INTO logs (ts, ts_nanos, level, target)
VALUES (1, 0, 'INFO', 'test');
INSERT INTO logs (ts, ts_nanos, level, target)
VALUES (2, 0, 'WARN', 'test');
SQL

test "$(sqlite3 "$log_db" 'SELECT COUNT(*) FROM logs;')" = 1
test "$(sqlite3 "$log_db" 'SELECT level FROM logs;')" = WARN
test "$(sqlite3 "$log_db" "SELECT seq FROM sqlite_sequence WHERE name='logs';")" = 1

run_with_paths "$repo_root/scripts/install.sh" --vacuum
run_with_paths "$repo_root/scripts/verify.sh" 0
run_with_paths "$repo_root/scripts/uninstall.sh"

test ! -e "$package_bin.real"
test -L "$command_bin"
test "$(sqlite3 "$log_db" \
  "SELECT COUNT(*) FROM sqlite_master WHERE type='trigger' AND name='codex_drop_logs_below_warn';")" = 0

printf 'All tests passed.\n'
