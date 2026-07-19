#!/bin/sh
set -eu

repo_root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
command_template="$repo_root/bin/codex"
package_template="$repo_root/bin/codex-package-bin-wrapper"

codex_home=${CODEX_HOME:-"$HOME/.codex"}
command_bin=${CODEX_COMMAND_BIN:-"$HOME/.local/bin/codex"}
package_bin=${CODEX_PACKAGE_BIN:-"$codex_home/packages/standalone/current/bin/codex"}
real_bin="$package_bin.real"
log_db=${CODEX_LOG_DB:-"$codex_home/logs_2.sqlite"}

if [ -f "$log_db" ]; then
  sqlite3 -cmd '.timeout 5000' "$log_db" \
    'DROP TRIGGER IF EXISTS codex_drop_logs_below_warn;'
  printf 'Removed codex_drop_logs_below_warn from %s\n' "$log_db"
fi

if [ -x "$real_bin" ]; then
  if cmp -s "$package_bin" "$package_template" || grep -q 'codex\.real' "$package_bin"; then
    rm -f "$package_bin"
    mv "$real_bin" "$package_bin"
    printf 'Restored native package entrypoint: %s\n' "$package_bin"
  else
    printf 'Left unrecognized package entrypoint unchanged: %s\n' "$package_bin" >&2
  fi
fi

if [ -e "$command_bin" ] || [ -L "$command_bin" ]; then
  if cmp -s "$command_bin" "$command_template"; then
    rm -f "$command_bin"
    ln -s "$package_bin" "$command_bin"
    printf 'Restored command symlink: %s -> %s\n' "$command_bin" "$package_bin"
  else
    printf 'Left unrecognized command entrypoint unchanged: %s\n' "$command_bin" >&2
  fi
fi
