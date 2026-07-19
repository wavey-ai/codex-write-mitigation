# Repository agent notes

This repository contains a temporary local mitigation for excessive writes to
Codex's internal SQLite log database. Keep the implementation small, auditable,
and reversible.

## Compatibility

- Keep all scripts compatible with POSIX `sh` on macOS and Linux.
- Do not hard-code usernames, home directories, Codex versions, or machine paths.
- Treat Codex's package layout and SQLite schema as external interfaces. Fail
  clearly when they differ instead of guessing or moving unknown files.
- Do not claim an upstream release fixes the issue without measuring its write
  rate and checking the release notes or source.

## Required checks

Run these checks before committing changes:

```sh
sh -n bin/* scripts/*.sh tests/*.sh
./tests/test.sh
```

Run `shellcheck` over the same shell files when it is installed.

Tests must use a temporary `CODEX_HOME` and database. Never run test fixtures
against `~/.codex`.

## Safety

- Never commit a Codex database, log content, credentials, or machine backups.
- Keep trigger installation transactional and idempotent.
- Keep compaction opt-in because `VACUUM` takes an exclusive database lock and
  may temporarily require substantial free disk space.
- Preserve an explicit uninstall path for both wrappers and the SQLite trigger.
