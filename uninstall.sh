#!/bin/bash
set -u
launchctl bootout "gui/$(id -u)/local.scrcpydeck" 2>/dev/null || true
pkill -f 'ScrcpyDeck.app/Contents/MacOS/ScrcpyDeck' 2>/dev/null || true
rm -f "$HOME/Library/LaunchAgents/local.scrcpydeck.plist"
rm -rf "$HOME/Applications/ScrcpyDeck.app"
echo "ScrcpyDeck kaldirildi. commands.json ve kaynaklar ~/Documents/scrcpy-deck altinda duruyor."
