#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./scripts/install.sh [--vacuum]

Installs the Codex command wrappers and SQLite log trigger.

Options:
  --vacuum  Compact logs_2.sqlite after installing the trigger. Stop Codex first.
  -h        Show this help.

Path overrides:
  CODEX_HOME         Defaults to ~/.codex
  CODEX_COMMAND_BIN  Defaults to ~/.local/bin/codex
  CODEX_PACKAGE_BIN  Defaults to $CODEX_HOME/packages/standalone/current/bin/codex
  CODEX_LOG_DB       Defaults to $CODEX_HOME/logs_2.sqlite
EOF
}

vacuum=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --vacuum)
      vacuum=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

for command_name in cmp file install sqlite3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'Required command is unavailable: %s\n' "$command_name" >&2
    exit 1
  fi
done

repo_root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
command_template="$repo_root/bin/codex"
package_template="$repo_root/bin/codex-package-bin-wrapper"
trigger_sql="$repo_root/sql/drop-logs-below-warn.sql"

codex_home=${CODEX_HOME:-"$HOME/.codex"}
command_bin=${CODEX_COMMAND_BIN:-"$HOME/.local/bin/codex"}
package_bin=${CODEX_PACKAGE_BIN:-"$codex_home/packages/standalone/current/bin/codex"}
real_bin="$package_bin.real"
log_db=${CODEX_LOG_DB:-"$codex_home/logs_2.sqlite"}

if [ ! -f "$log_db" ]; then
  printf 'Codex log database was not found: %s\n' "$log_db" >&2
  exit 1
fi

has_logs_table=$(sqlite3 -cmd '.timeout 5000' "$log_db" \
  "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='logs';")
if [ "$has_logs_table" != 1 ]; then
  printf 'The expected logs table is missing from %s\n' "$log_db" >&2
  exit 1
fi

if [ ! -e "$package_bin" ]; then
  printf 'Codex standalone package entrypoint was not found: %s\n' "$package_bin" >&2
  exit 1
fi

package_kind=$(file -b "$package_bin")
case "$package_kind" in
  *executable*)
    mv -f "$package_bin" "$real_bin"
    ;;
  *shell\ script*)
    if [ ! -x "$real_bin" ]; then
      printf 'Refusing to replace a package script without a native codex.real: %s\n' "$package_bin" >&2
      exit 1
    fi
    if ! cmp -s "$package_bin" "$package_template" &&
       ! grep -q 'codex\.real' "$package_bin"; then
      printf 'Refusing to replace an unrecognized package wrapper: %s\n' "$package_bin" >&2
      exit 1
    fi
    ;;
  *)
    printf 'Refusing to move an unrecognized package entrypoint (%s): %s\n' \
      "$package_kind" "$package_bin" >&2
    exit 1
    ;;
esac

if [ ! -x "$real_bin" ]; then
  printf 'Codex native binary is missing or not executable: %s\n' "$real_bin" >&2
  exit 1
fi

install -m 755 "$package_template" "$package_bin"

command_dir=$(dirname "$command_bin")
mkdir -p "$command_dir"
if [ -e "$command_bin" ] || [ -L "$command_bin" ]; then
  if ! cmp -s "$command_bin" "$command_template"; then
    backup="$command_bin.before-write-mitigation"
    if [ -e "$backup" ] || [ -L "$backup" ]; then
      backup="$backup.$(date +%Y%m%d%H%M%S)"
    fi
    mv "$command_bin" "$backup"
    printf 'Saved the previous command entrypoint at %s\n' "$backup"
  fi
fi
install -m 755 "$command_template" "$command_bin"

sqlite3 -bail -cmd '.timeout 5000' "$log_db" < "$trigger_sql"
printf 'Installed codex_drop_logs_below_warn in %s\n' "$log_db"

if [ "$vacuum" -eq 1 ]; then
  printf 'Compacting %s; keep Codex stopped until this completes.\n' "$log_db"
  sqlite3 -bail -cmd '.timeout 5000' "$log_db" 'VACUUM;'
fi

printf 'Installed command wrapper: %s\n' "$command_bin"
printf 'Installed package wrapper: %s\n' "$package_bin"
printf 'Native Codex binary: %s\n' "$real_bin"
