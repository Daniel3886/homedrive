#!/bin/sh
# Regenerates docs/images/*.png: the app icon and real screenshots of the app,
# taken against a staged demo "PC" (a local folder behind a fake ssh).
# No Linux PC, network or Screen Recording permission needed.
set -e
cd "$(dirname "$0")/.."
ROOT=$(pwd)
OUT="$ROOT/docs/images"
DEMO=/tmp/homedrive-demo
mkdir -p "$OUT"

echo "▸ Icon"
swift scripts/make-icon.swift "$(mktemp -d)/HomeDrive.iconset" "$DEMO-icon.png" >/dev/null
sips -Z 256 "$DEMO-icon.png" --out "$OUT/icon.png" >/dev/null

echo "▸ Staging demo machines in $DEMO"
rm -rf "$DEMO"
PC="$DEMO/pc/home/daniel"
MAC="$DEMO/mac/Users/daniel"
mkdir -p "$PC"/Desktop "$PC"/Documents/Projects/homedrive "$PC"/Documents/Taxes "$PC"/Downloads \
         "$PC"/Music "$PC"/Pictures/Wallpapers "$PC"/Videos "$DEMO/bin" \
         "$MAC"/Downloads "$MAC"/Desktop "$MAC"/Documents "$MAC/Downloads/Photos 2026"

blob() { head -c "$2" /dev/urandom > "$1"; }
blob "$PC/Documents/Thesis final.pdf" 2457600
blob "$PC/Documents/Budget 2026.xlsx" 184320
blob "$PC/Documents/Resume.docx" 96256
printf 'Agenda\n- backups\n' > "$PC/Documents/meeting notes.txt"
blob "$PC/Documents/scan-passport.png" 1363148
blob "$MAC/Downloads/Vacation 2026.mov" 14680064
blob "$MAC/Downloads/Invoice-1042.pdf" 204800
blob "$MAC/Downloads/Screenshot 2026-11-20 at 18.04.png" 921600
blob "$MAC/Downloads/Presentation.key" 3145728
printf '# todo\n' > "$MAC/Downloads/todo.md"
for i in 1 2 3 4 5 6; do blob "$MAC/Downloads/Photos 2026/IMG_10$i.heic" 1048576; done

# Spread the modification dates out a little so the listing looks lived-in.
d=0
for f in "$PC"/Documents/* "$MAC"/Downloads/*; do
  d=$((d + 1)); touch -t "202611$(printf %02d $((22 - d)))$(printf %02d $((9 + d)))15" "$f"
done

# Fake Linux tools on the "PC".
printf '#!/bin/sh\necho ubuntu-pc\n' > "$DEMO/bin/hostname"
printf '#!/bin/sh\n[ "$1" = -sr ] && { echo "Linux 6.8.0-49-generic"; exit; }\nexec /usr/bin/uname "$@"\n' > "$DEMO/bin/uname"
printf '#!/bin/sh\necho "Filesystem 1024-blocks Used Available Capacity Mounted on"\necho "/dev/nvme0n1p2 960379920 402451880 509089752 45%% /"\n' > "$DEMO/bin/df"
cat > "$DEMO/fake-ssh" <<FAKE
#!/bin/sh
# Stand-in for ssh: runs the remote command locally as user "daniel" on "ubuntu-pc",
# throttled to ~1 MB/s so transfers are still running when the screenshot is taken.
for last; do :; done
case " \$* " in *" -O "*|*" -M "*) exit 0 ;; esac
export HOME="$PC" PATH="$DEMO/bin:\$PATH"
throttle() { perl -e '\$|=1; while (read(STDIN, \$b, 32768)) { print \$b; select(undef, undef, undef, 0.03) }' homedrive-throttle; }
case "\$last" in
  *"tar -xf"*) throttle | /bin/sh -c "\$last" & ;;
  *"tar -cf"*) /bin/sh -c "\$last" | throttle & ;;
  *) exec /bin/sh -c "\$last" ;;
esac
# Like a real ssh client, die (taking the pipeline with us) when HomeDrive cancels.
pipeline=\$!
trap 'pkill -P \$pipeline; kill \$pipeline 2>/dev/null; exit 143' TERM
wait \$pipeline
FAKE
chmod +x "$DEMO"/fake-ssh "$DEMO"/bin/*

echo "▸ Building"
swift build --product HomeDrive >/dev/null
BIN=$(swift build --show-bin-path)/HomeDrive

SETTINGS='{"host":"ubuntu-home","remoteStartPath":"~/Documents","localStartPath":"~/Downloads","useMultiplexing":true}'
defaults write HomeDrive screenshotSettings -data "$(printf '%s' "$SETTINGS" | xxd -p | tr -d '\n')"

for appearance in dark light; do
  echo "▸ Capturing ($appearance)"
  rm -rf "$MAC/Downloads/Budget 2026.xlsx" "$PC/Documents/Vacation 2026.mov" "$PC/Documents/Photos 2026"
  HOMEDRIVE_SSH="$DEMO/fake-ssh" \
  HOMEDRIVE_SETTINGS_KEY=screenshotSettings \
  HOMEDRIVE_DEBUG_MAC_HOME="$MAC" \
  HOMEDRIVE_DEBUG_MAC_NAME="Daniel's MacBook Pro" \
  HOMEDRIVE_DEBUG_APPEARANCE=$appearance \
  HOMEDRIVE_SNAPSHOT="$DEMO/$appearance" \
  HOMEDRIVE_SNAPSHOT_RETRIEVE="Budget 2026.xlsx" \
  HOMEDRIVE_SNAPSHOT_SEND="Vacation 2026.mov|Photos 2026" \
  HOMEDRIVE_SNAPSHOT_SELECT_MAC="Vacation 2026.mov" \
  HOMEDRIVE_SNAPSHOT_WAIT=5 \
  "$BIN" >/dev/null 2>&1
  pkill -f "homedrive-throttle|$DEMO" 2>/dev/null || true
  cp "$DEMO/$appearance-main.png" "$OUT/screenshot-$appearance.png"
  # A blank (all-white) capture compresses to a tiny file; don't publish that.
  if [ -f "$DEMO/$appearance-settings.png" ] && [ "$(wc -c < "$DEMO/$appearance-settings.png")" -gt 100000 ]; then
    cp "$DEMO/$appearance-settings.png" "$OUT/settings-$appearance.png"
  else
    echo "  (settings capture came out blank; skipped)"
  fi
done

defaults delete HomeDrive screenshotSettings
pkill -f "$DEMO/fake-ssh" 2>/dev/null || true
echo "✓ Wrote $(ls "$OUT" | tr '\n' ' ')"
