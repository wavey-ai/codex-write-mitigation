# Codex write mitigation

A reversible local mitigation for excessive writes to Codex's internal
`logs_2.sqlite` database.

Codex CLI `0.144.6` was observed retaining about 180,000 log rows after more
than 75 million inserts. Most traffic was `TRACE`, `DEBUG`, or `INFO`, so the
bounded log store still generated sustained insert, prune, WAL, and index work.

This repository applies two controls:

1. Shell wrappers default `RUST_LOG` to `warn` for the normal command path and
   the standalone package entrypoint.
2. A SQLite `BEFORE INSERT` trigger rejects `TRACE`, `DEBUG`, and `INFO` rows
   before they reach the log table.

The trigger is the containment layer. It remains effective if a Codex process
bypasses the command wrapper or initializes more verbose logging internally.

## Install

Requirements: a standalone Codex installation, `sqlite3`, and standard macOS
or Linux command-line tools.

Stop Codex clients before the first installation, then run:

```sh
git clone https://github.com/wavey-ai/codex-write-mitigation.git
cd codex-write-mitigation
./scripts/install.sh
./scripts/verify.sh 30
```

By default the installer manages:

```text
~/.local/bin/codex
~/.codex/packages/standalone/current/bin/codex
~/.codex/packages/standalone/current/bin/codex.real
~/.codex/logs_2.sqlite
```

The previous command entrypoint is moved to a timestamped
`*.before-write-mitigation` backup. The package's native executable becomes
`codex.real`. The replacement package entrypoint sets the log filter and then
executes that binary.

Set `CODEX_HOME`, `CODEX_COMMAND_BIN`, `CODEX_PACKAGE_BIN`, or `CODEX_LOG_DB` to
override those paths. An explicitly supplied `RUST_LOG` value is preserved.

## Compact an existing database

Installing the trigger stops low-priority writes but does not return existing
free pages to the filesystem. Stop all Codex clients before compaction and make
sure the disk has enough temporary free space, then run:

```sh
./scripts/install.sh --vacuum
```

Or compact the database directly:

```sh
sqlite3 ~/.codex/logs_2.sqlite 'VACUUM;'
```

`VACUUM` takes an exclusive lock and can require temporary space comparable to
the database size. It is deliberately opt-in.

## Verify

The verifier confirms that an `INFO` insert is rejected and compares the
`logs` autoincrement sequence over an interval:

```sh
./scripts/verify.sh 60
```

A zero delta during ordinary Codex activity indicates that verbose traffic is
not reaching the table. A nonzero delta can be legitimate when Codex records a
`WARN` or `ERROR`. Inspect retained levels with:

```sh
sqlite3 ~/.codex/logs_2.sqlite \
  'SELECT level, COUNT(*) FROM logs GROUP BY level ORDER BY level;'
```

## Codex updates

The standalone updater may replace either wrapper. After every Codex update,
rerun:

```sh
./scripts/install.sh
./scripts/verify.sh 30
```

If the package entrypoint is a new native executable, the installer promotes it
to `codex.real` before restoring the wrapper. It refuses to move unknown script
entrypoints.

## Remove the mitigation

Stop Codex clients, then run:

```sh
./scripts/uninstall.sh
```

This drops the trigger, restores the native package executable, and restores
the normal command symlink. Existing command-entrypoint backups are retained.

## macOS storage note

Do not redirect the database to `/tmp` to reduce SSD writes on macOS. `/tmp` is
normally backed by APFS and still writes to the SSD. A genuine RAM-backed
redirect requires a RAM disk, but the trigger avoids that added operational
complexity.

## Tradeoffs

The mitigation intentionally discards verbose internal diagnostics. Remove it
temporarily when an upstream support investigation requires `INFO`, `DEBUG`, or
`TRACE` logs. The SQLite schema and standalone package layout are not public
compatibility guarantees, so review the scripts when Codex changes either one.

This project is an independent operational workaround and is not affiliated
with or endorsed by OpenAI.
