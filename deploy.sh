#!/bin/bash
# Derleyip kurar: önce bu Mac'te, sonra (tanımlıysa) ikinci bir Mac'te.
# commands.json iki Mac'te aynıdır. Yansıtma açık olan Mac'te uygulama yeniden
# başlatılmaz (yansıtma kesilirdi); dosyalar yine yerine konur, menüden
# "Yeniden yükle" yeter.
#
#   bash deploy.sh           # bu Mac + ikinci Mac (MINI ya da .deploy-host)
#   bash deploy.sh --here    # yalnızca bu Mac
#
# İkinci Mac: ssh adresi MINI ortam değişkeninden ya da repo kökündeki
# .deploy-host dosyasından okunur (git'e girmez). İkisi de yoksa yalnızca bu Mac.
set -eu
trap 'echo "deploy.sh HATA: $(hostname -s), satır $LINENO — yarıda kaldı, kurulum yapılmadı" >&2' ERR
SRC=$(cd "$(dirname "$0")" && pwd)
cd "$SRC"
MINI=${MINI:-$(cat .deploy-host 2>/dev/null || true)}
REMOTE_DIR=Documents/scrcpy-deck   # ikinci Mac'te kaynakların kopyalandığı yer

xcrun swiftc -swift-version 5 -O -o ScrcpyDeck main.swift -framework AppKit

# Paketi boş bir geçici klasörde sıfırdan kurup orada imzala. Yerinde
# imzalamak Mac mini'de aralıklı olarak "resource fork, Finder information,
# or similar detritus not allowed" veriyordu: xattr -cr ile codesign arasında
# dosyalara yeniden öznitelik ekleniyor, eski _CodeSignature da kalıyordu.
STAGE=$(mktemp -d)
mkdir -p "$STAGE/ScrcpyDeck.app/Contents/MacOS"
cat ScrcpyDeck.app/Contents/Info.plist > "$STAGE/ScrcpyDeck.app/Contents/Info.plist"
cat ScrcpyDeck > "$STAGE/ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck"
chmod +x "$STAGE/ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck"
codesign --sign - "$STAGE/ScrcpyDeck.app"
codesign -v "$STAGE/ScrcpyDeck.app"
rm -rf ScrcpyDeck.app/Contents/MacOS ScrcpyDeck.app/Contents/_CodeSignature
ditto --noextattr --noqtn "$STAGE/ScrcpyDeck.app" ScrcpyDeck.app
rm -rf "$STAGE"
codesign -v ScrcpyDeck.app

# Uygulama ~/.config'teki kopyayı okur (launchd + Belgeler izni sorunu).
mkdir -p "$HOME/.config/scrcpy-deck"
cp commands.json "$HOME/.config/scrcpy-deck/commands.json"

if pgrep -x scrcpy >/dev/null; then
  echo "$(hostname -s): yansıtma açık — uygulama yeniden başlatılmadı. Bitince menüden 'Yeniden yükle', ya da: bash $SRC/install.sh"
  echo "  (main.swift değiştiyse yeni kod ancak yeniden başlatınca devreye girer.)"
else
  bash install.sh | head -1
fi

[ "${1:-}" = "--here" ] || [ -z "$MINI" ] && exit 0

echo "--- $MINI"
ssh -o ConnectTimeout=10 "$MINI" "mkdir -p ~/$REMOTE_DIR/ScrcpyDeck.app/Contents/MacOS"
scp -q main.swift commands.json README.md install.sh uninstall.sh deploy.sh "$MINI:$REMOTE_DIR/"
scp -q ScrcpyDeck.app/Contents/Info.plist "$MINI:$REMOTE_DIR/ScrcpyDeck.app/Contents/"
ssh "$MINI" "bash ~/$REMOTE_DIR/deploy.sh --here"
