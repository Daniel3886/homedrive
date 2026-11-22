# Development

## Layout

```
Package.swift                 SwiftPM manifest (app target only on macOS)
Sources/
  HomeDriveCore/              UI-free library: SSH, remote scripts, transfers, parsers
  HomeDrive/                  SwiftUI app
    HomeDriveApp.swift        App, menus, AppDelegate (quit guard, closes SSH master)
    Models/                   AppModel, PaneModel, TransferQueue
    Views/                    ContentView, FilePaneView, TransfersView, SettingsView
    DebugSnapshot.swift       debug-only window-to-PNG helper
Tests/HomeDriveCoreTests/     Swift Testing suites
scripts/
  test.sh                     runs the tests (handles Command Line Tools quirks)
  build-app.sh                builds dist/HomeDrive.app (+ --install)
  make-icon.swift             draws the app icon
docs/                         ARCHITECTURE.md, this file
.github/workflows/ci.yml      Linux tests on every push, macOS build on main
```

## Tests

```sh
./scripts/test.sh                         # everything
./scripts/test.sh --filter IntegrationTests
```

`swift test` works as-is with full Xcode. With **only the Command Line Tools**, Swift Testing is installed but not on the default search paths, and its Foundation overlay module is missing. `scripts/test.sh` adds the right `-F`/rpath flags and `-disable-cross-import-overlays`.

What the suites cover:

| Suite | What |
|---|---|
| `ShellTests` | quoting, including a round trip of hostile names through a real `/bin/sh` |
| `RemotePathTests` | join / normalize / parent / breadcrumbs / `~` abbreviation |
| `ListingParserTests` | GNU `find` and BSD `stat` output, tabs/newlines in names, symlinks |
| `SSHCommandBuilderTests` | ssh arguments, multiplexing, master control, settings decoding |
| `SSHConfigParserTests` | reading `Host` blocks from `~/.ssh/config` |
| `RemoteSystemInfoTests` | parsing the connect probe |
| `ErrorTests` | friendly hints for common ssh failures |
| `RemoteFileServiceTests` | command construction and error mapping with a fake runner |
| `IntegrationTests` | **real** scripts, tar and pipes, end to end |
| `LocalFileServiceTests` | Mac-side listing and sizes |

### How the integration tests fake the PC

`FakeSSH` writes a tiny script that stands in for `/usr/bin/ssh`:

```sh
#!/bin/sh
for last; do :; done                                  # the remote command is the last argument
case " $* " in *" -O "*|*" -M "*) exit 0 ;; esac      # pretend master control works
exec /bin/sh -c "$last"                               # run it "on the PC" (locally)
```

Everything except the network hop is real: quoting, the remote scripts, `find`, both `tar`s, the byte pump, staging and cleanup. On macOS that exercises the BSD fallbacks. In CI the same tests run in a Linux container against GNU `find`/`tar`, which are what your PC actually uses.

To test against Linux locally (needs Docker):

```sh
docker run --rm -v "$PWD":/src:ro swift:6.1 bash -c 'cp -r /src /w && cd /w && swift test'
```

## Trying the UI without the PC

Two environment variables (read in `AppModel`) point the app at the fake ssh and keep its settings away from your real ones:

```sh
mkdir -p /tmp/hd/pc /tmp/hd/mac
cat > /tmp/hd/fake-ssh <<'EOF'
#!/bin/sh
for last; do :; done
case " $* " in *" -O "*|*" -M "*) exit 0 ;; esac
exec /bin/sh -c "$last"
EOF
chmod +x /tmp/hd/fake-ssh

HOMEDRIVE_SSH=/tmp/hd/fake-ssh HOMEDRIVE_SETTINGS_KEY=demo swift run HomeDrive
# In Settings use any host name, "Start on PC in" = /tmp/hd/pc, "Start on Mac in" = /tmp/hd/mac
```

Debug builds also support `HOMEDRIVE_SNAPSHOT=/tmp/shot`, which renders the window to `/tmp/shot-N.png` without needing Screen Recording permission. Add `HOMEDRIVE_SNAPSHOT_DEMO=1` to also send and retrieve an item and capture the Settings sheet.

## Releasing a build

```sh
./scripts/build-app.sh --install
```

The version is `0.1.0`; the build number is `git describe`. Tag a release with `git tag v0.2.0` and bump `CFBundleShortVersionString` in the script.

## Ideas for later

- Drag from the PC pane straight into Finder (needs `NSFilePromiseProvider`).
- Several saved PCs / profiles (e.g. WireGuard vs DuckDNS) with automatic fallback.
- Folder sync ("keep ~/Shared in sync with the PC").
- Thumbnails / Quick Look previews for PC files.
- Resume interrupted large transfers (`rsync --partial` when the PC has rsync).
