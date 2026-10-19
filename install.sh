#!/bin/bash
# ScrcpyDeck kurucusu — root GEREKTIRMEZ.
set -eu
SRC=$(cd "$(dirname "$0")" && pwd)
DEST="$HOME/Applications"
AGENT="$HOME/Library/LaunchAgents/local.scrcpydeck.plist"
mkdir -p "$DEST" "$(dirname "$AGENT")"

if [ ! -x "$SRC/ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck" ]; then
  echo "Uygulama henuz derlenmemis. Derleyip kurmak icin:  bash $SRC/deploy.sh --here"
  exit 1
fi
# Komut listesi yoksa repodakini koy; varsa (elle duzenlenmis olabilir) dokunma.
CONF="$HOME/.config/scrcpy-deck/commands.json"
[ -f "$CONF" ] || { mkdir -p "$(dirname "$CONF")"; cp "$SRC/commands.json" "$CONF"; }

launchctl bootout "gui/$(id -u)/local.scrcpydeck" 2>/dev/null || true
pkill -f 'ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck' 2>/dev/null || true
sleep 1

rm -rf "$DEST/ScrcpyDeck.app"
cp -R "$SRC/ScrcpyDeck.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/ScrcpyDeck.app" 2>/dev/null || true

cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>local.scrcpydeck</string>
  <key>ProgramArguments</key>
  <array><string>$DEST/ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><dict><key>SuccessfulExit</key><false/></dict>
</dict>
</plist>
PLIST
launchctl bootstrap "gui/$(id -u)" "$AGENT"
sleep 2
if pgrep -f 'ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck' >/dev/null; then
  echo "ScrcpyDeck kuruldu ve calisiyor. Sag ustte telefon ikonu gorunmeli."
else
  echo "UYARI: baslatilamadi. Su komutla elle dene:"
  echo "  $DEST/ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck"
fi
echo "Kaldirmak icin:  bash $SRC/uninstall.sh"
