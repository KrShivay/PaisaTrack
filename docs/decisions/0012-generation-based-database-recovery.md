# ADR 0012 — Generation-based database recovery

Status: proposed for safe key-loss recovery (2026-09-27)

## Context

When Android Keystore can no longer unwrap the current SQLCipher passphrase,
the app cannot open its database to use the normal backup importer. Resetting
the database or clearing the legacy key can permanently discard the only local
copy. A restore must also survive process death without selecting a partially
imported database.

## Decision

Restore each selected encrypted backup into a new SQLCipher database file and
an independent Android Keystore key slot identified by a validated UUID. Keep
the existing database file family, legacy wrapped passphrase, and legacy key
unchanged. Verify archive authentication, SQL integrity, foreign keys, and a
byte-verified copy of the current database family before publishing the new
active generation ID with a synchronous SharedPreferences commit.

Record every uncommitted generation in a durable staging-ID set. Publishing
the active ID and removing that generation from the staging set use one
SharedPreferences commit. When the active pointer is absent, startup may
continue using the legacy database only if every generation file on disk is
identified as uncommitted staging data; an unknown generation file still
fails closed.

The active generation ID is the single selector used by foreground startup
and background database workers. Missing or invalid active generation state,
file, or key fails closed; startup must not replace a generation key. Before
the activation commit, failures clean up only the unselected staging database
and key when safe. If the commit result is uncertain, retain both so startup
can resolve the durable pointer. Explicit Settings reset may remove all
database generations, recovery archives, and their key slots.

Recovery, the nightly worker, and Settings reset share a stable database lock.
On Android the lock combines a per-path JVM semaphore (Flutter engines in the
same process share POSIX locks) with an OS file lock for other processes. Reset
holds the lock while closing the foreground database and removing database
files and keys. Native generation reset commits removal of the active selector
before deleting any generation-key aliases, so a failed selector commit cannot
strand an active database without its key.

## Consequences

- A process interruption before activation does not change the active pointer.
  A known staged generation remains retryable; startup continues using the
  prior selector when available. If staging metadata is missing or inconsistent,
  startup fails closed and the user can retry backup recovery.
- A successful restore does not destroy the original encrypted bytes or
  legacy key. The additional local archive and key slots consume storage until
  the user explicitly resets app data.
- An interrupted pre-activation import leaves a durable staging record; if
  cleanup cannot remove the staged file family, its key and staging record stay
  available so startup can keep using the legacy selector.
- Database recovery is local-only and continues to use the existing encrypted
  backup format and passphrase prompt.
- Any future database-opening entry point must resolve the active generation
  before opening SQLCipher.
