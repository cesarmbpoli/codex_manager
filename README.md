# Codex Account Manager - v1.2

Local multi-account manager for the Codex CLI.

It keeps account authentication isolated while sharing Codex sessions/configuration,
supports automatic account failover for `codex exec`, and can schedule session resume
with `systemd --user` when every account is temporarily rate-limited.

## v1.2: transparent Codex runtime updates

v1.1 installed the manager wrapper directly at:

```text
~/.local/bin/codex
```

That collides with the default visible command used by the official Codex standalone
installer.

v1.2 separates the two responsibilities:

```text
~/.local/lib/codex-manager/bin/codex   manager wrapper
~/.local/lib/codex-manager/codex-runtime  runtime launcher
~/.local/bin/codex                     free for official Codex
```

The manager's `codex_real` now points to the stable `codex-runtime` launcher rather
than to one specific Codex release.

The runtime launcher discovers the actual official Codex automatically from:

- the legacy v1.1 runtime target, preserved as a hint;
- `~/.local/bin/codex`;
- the default standalone installation under `~/.codex/packages/standalone`;
- standalone installations under managed account `CODEX_HOME` directories;
- other Codex installations visible on `PATH` (npm, bun, system installs).

When multiple runtimes are found, it probes their versions and selects the newest
detectable version. Discovery is cached for 300 seconds by default.

This means an official Codex update can replace its own binary/symlink without
overwriting the manager wrapper.

## Install / upgrade

From the cloned repository:

```bash
git pull origin main
./install.sh
source ~/.bashrc
```

Then validate:

```bash
which codex
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
codex-account doctor
codex-account list
```

Expected `which codex`:

```text
~/.local/lib/codex-manager/bin/codex
```

The official Codex can still live at `~/.local/bin/codex`; our wrapper wins because
its dedicated directory is prepended to `PATH`.

## Force runtime rediscovery

Normally rediscovery happens automatically after the cache TTL.

To force it immediately:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-refresh
```

To inspect without changing normal CLI behavior:

```bash
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
```

Example:

```json
{
  "method": "standalone",
  "path": "/home/user/.local/bin/codex",
  "version": "codex-cli 0.x.y"
}
```

## Accounts

Import the current Codex account:

```bash
codex-account bootstrap principal
```

Add more accounts:

```bash
codex-account add secundaria
codex-account add terceira
```

List:

```bash
codex-account list
```

Choose a preferred account:

```bash
codex-account use secundaria
```

## Normal use

Interactive:

```bash
codex
```

Non-interactive with automatic failover:

```bash
codex exec "implement the next milestone"
```

If one account reaches its usage limit, the manager marks it unavailable and resumes
the same Codex session with another account.

## All accounts limited

For `codex exec`, if all accounts are unavailable, the manager records the session and
creates a persistent `systemd --user` timer for the earliest known reset.

Inspect pending resumes:

```bash
codex-account pending
systemctl --user list-timers 'codex-resume-*'
```

Cancel:

```bash
codex-account cancel <SESSION_ID>
```

Force resume now:

```bash
codex-account resume-session <SESSION_ID>
```

## Layout

```text
~/.codex-manager/
|-- accounts/
|   |-- principal/home/
|   |-- secundaria/home/
|   `-- ...
|-- shared/
|   |-- config.toml
|   |-- sessions/
|   |-- archived_sessions/
|   |-- skills/
|   |-- rules/
|   `-- sqlite/
|-- pending/
|-- manager.json
|-- runtime-cache.json
`-- state.json

~/.local/lib/codex-manager/
|-- bin/codex
`-- codex-runtime
```

## Diagnostics

```bash
codex-account doctor
codex-account list
~/.local/lib/codex-manager/codex-runtime --manager-runtime-info
```

For runtime selection debug on a normal invocation:

```bash
CODEX_MANAGER_RUNTIME_DEBUG=1 codex --version
```

## Configuration

`~/.codex-manager/manager.json`

Relevant v1.2 fields:

```json
{
  "codex_real": "/home/user/.local/lib/codex-manager/codex-runtime",
  "codex_runtime_hints": [],
  "runtime_check_ttl_seconds": 300,
  "auto_schedule": true,
  "schedule_grace_seconds": 20,
  "default_cooldown_minutes": 30
}
```

## Rollback

The original `~/.codex` account data is not removed by the manager.

Remove the v1.2 wrapper:

```bash
rm ~/.local/lib/codex-manager/bin/codex
```

Then remove the PATH block between:

```text
# >>> codex-manager >>>
# <<< codex-manager <<<
```

from `~/.bashrc`.

The official `~/.local/bin/codex` remains untouched.
