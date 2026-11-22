# Architecture

HomeDrive is a SwiftUI app on top of a small, UI-free core library. The core drives the system `ssh` binary. It never embeds an SSH implementation.

```
┌──────────────────────── HomeDrive (app target, macOS only) ───────────────────────┐
│  Views: ContentView · FilePaneView · TransfersView · SettingsView                  │
│  Models: AppModel (connection, actions) · PaneModel ×2 · TransferQueue/Transfer    │
└───────────────────────────────────────┬────────────────────────────────────────────┘
                                        │
┌──────────────────────── HomeDriveCore (library, macOS + Linux) ───────────────────┐
│  RemoteFileService   list / mkdir / rename / trash / delete / probe / connect     │
│  TransferEngine      upload / download (tar over ssh, with progress + cancel)     │
│  SSHCommandBuilder   ssh argument lists (BatchMode, ControlMaster, port, key…)    │
│  RemoteScripts       the fixed POSIX sh scripts run on the PC                     │
│  Shell               quoting · ListingParser · RemotePath · SSHConfigParser       │
│  ProcessRunner       runs processes (abstracted as CommandRunning for tests)      │
│  LocalFileService    lists Mac folders in the same FileEntry shape                │
└───────────────────────────────────────┬────────────────────────────────────────────┘
                                        │  /usr/bin/ssh  ·  /usr/bin/tar
                                        ▼
                          Linux PC: sh, find, tar, mv, rm, du, df, gio
```

## Why the system `ssh`?

- **Same config as Terminal.** It reuses `~/.ssh/config`, keys, the agent/keychain and `known_hosts` with no extra setup and no second copy of credentials.
- **Nothing extra on the PC.** No server or agent runs there, and no dependencies are needed.
- **Battle-tested crypto.** HomeDrive doesn't implement any SSH itself.

The cost is that we must build command lines safely, which the next section covers.

## Running remote commands safely

Every remote operation has this shape:

```
ssh [options] -T -- <host> "sh -c '<fixed script>' sh '<arg1>' '<arg2>' …"
```

- The **script** is a constant in `RemoteScripts.swift`. It never contains user data.
- **User data** (paths, names) is passed only as positional arguments (`$1`, `$2`, `"$@"`). Each one goes through `Shell.quote`, which wraps it in single quotes. A file called `$(rm -rf ~)` is just a name.
- An explicit `sh -c` means the user's login shell (bash, zsh, fish) doesn't matter.
- `ShellTests` round-trips nasty names through a real `/bin/sh` to prove the quoting holds.

### Listing format

`RemoteScripts.list` runs GNU `find -printf '%y%Y\t%s\t%T@\t%m\t%f\0'`:

| field | example | meaning |
|---|---|---|
| `%y%Y` | `ff`, `dd`, `ld`, `lN` | type, plus the target type for symlinks (`N` = broken) |
| `%s` | `1234` | size in bytes |
| `%T@` | `1700000000.5` | modification time |
| `%m` | `644` | permission bits |
| `%f` | `name` | file name (last field, so it may contain tabs) |

Records end in NUL, so even names with newlines survive. When `find -printf` isn't available (BSD/macOS, used by the tests), the script falls back to `stat -f`. `ListingParser` understands both.

## Connection sharing

When **Keep one shared connection open** is on, `connect()` starts a background master:

```
ssh -o ControlMaster=yes -o ControlPath=~/.ssh/homedrive-%C -o ControlPersist=600 -M -N -f host
```

Every later command passes `ControlMaster=no` with the same `ControlPath`. A command reuses the master when it exists and falls back to a fresh connection when it doesn't. Folder listings then skip the SSH handshake and feel instant.

We never let an ordinary command *become* a master implicitly (`ControlMaster=auto`). A persisting master inherits the pipes of the process that spawned it and would keep them open, so our reads would never finish. For the same reason the master is started with `runDetaching`, which sends stderr to a temp file rather than a pipe. The master is closed with `ssh -O exit` on disconnect and on quit.

## Transfers

```
upload:    /usr/bin/tar -c ./name  ──stdout──▶ [HomeDrive pump] ──stdin──▶ ssh pc "sh -c '<tarExtract>' …"
download:  ssh pc "sh -c '<tarCreate>' …" ──stdout──▶ [HomeDrive pump] ──stdin──▶ /usr/bin/tar -x
```

`PipeTransfer` starts both processes and copies bytes between them on a dedicated thread, 256 KiB at a time. Sitting in the middle gives us:

- **Progress.** Bytes counted are reported at most every 100 ms. The total comes from the local size (upload) or the listing / `du -sk` (download).
- **Cancellation.** Both PIDs are signalled. If either side dies early, `EPIPE` stops the other.
- **Clear errors.** Each side's stderr is captured. Exit code 255 from ssh means a connection problem, and `HomeDriveError.friendlySSHHint` turns it into advice ("Is WireGuard connected…").

Why tar rather than `scp`/`sftp`? It handles single files and whole trees the same way and keeps modes and mtimes. It also needs no glob escaping (modern `scp` glob-expands remote paths) and is present on every Linux. On the Mac side `COPYFILE_DISABLE=1 --no-mac-metadata --no-xattrs` keeps `._*` AppleDouble files from reaching Linux. Entries are archived as `./name`, so names starting with `-` can't be read as options.

### Atomic placement

- **Upload** (`RemoteScripts.tarExtract`): `mktemp -d "$dest/.homedrive-partial.XXXXXX"` → extract → if the target exists, replace it only when allowed (exit 17 otherwise) → `mv` into place. A failed or cut-off stream makes tar fail, and the staging folder is removed.
- **Download** (`TransferEngine.download`): extract into `<dest>/.homedrive-partial-<UUID>` → move into place → the staging folder is always removed (`defer`).

## Concurrency notes

- The app's models are `@MainActor @Observable`. Core types are `Sendable` structs.
- Blocking pipe reads use **dedicated threads**, never GCD's global queue. Many concurrent commands could otherwise exhaust the pool and deadlock. (We hit this in testing.)
- `TransferQueue` runs at most 2 transfers at once. Progress callbacks hop to the main actor.
- On Linux, swift-corelibs-foundation starts children with SIGTERM blocked, so the transfer engine uses SIGKILL there. On macOS it uses SIGTERM.
