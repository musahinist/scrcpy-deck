#!/bin/bash
# Derleyip kurar: önce bu Mac'te, sonra Mac mini'de. commands.json iki Mac'te
# aynıdır. Yansıtma açık olan Mac'te uygulama yeniden başlatılmaz (yansıtma
# kesilirdi); dosyalar yine yerine konur, menüden "Yeniden yükle" yeter.
#
#   bash deploy.sh           # bu Mac + Mac mini
#   bash deploy.sh --here    # yalnızca bu Mac
set -eu
MINI=${MINI:-mshns-mac-mini.local}
SRC=$(cd "$(dirname "$0")" && pwd)
cd "$SRC"

xcrun swiftc -swift-version 5 -O -o ScrcpyDeck main.swift -framework AppKit
cp ScrcpyDeck ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck
xattr -cr ScrcpyDeck.app
codesign --force --sign - ScrcpyDeck.app 2>/dev/null

# Uygulama önce ~/.config'teki kopyayı okur (launchd + Belgeler izni sorunu).
if [ -d "$HOME/.config/scrcpy-deck" ]; then
  cp commands.json "$HOME/.config/scrcpy-deck/commands.json"
fi

if pgrep -x scrcpy >/dev/null; then
  echo "$(hostname -s): yansıtma açık — uygulama yeniden başlatılmadı. Bitince menüden 'Yeniden yükle', ya da: bash $SRC/install.sh"
  echo "  (main.swift değiştiyse yeni kod ancak yeniden başlatınca devreye girer.)"
else
  bash install.sh | head -1
fi

[ "${1:-}" = "--here" ] && exit 0

echo "--- $MINI"
ssh -o ConnectTimeout=10 "$MINI" 'mkdir -p ~/Documents/scrcpy-deck/ScrcpyDeck.app/Contents/MacOS'
scp -q main.swift commands.json README.md install.sh uninstall.sh deploy.sh "$MINI:Documents/scrcpy-deck/"
scp -q ScrcpyDeck.app/Contents/Info.plist "$MINI:Documents/scrcpy-deck/ScrcpyDeck.app/Contents/"
ssh "$MINI" 'bash ~/Documents/scrcpy-deck/deploy.sh --here'
