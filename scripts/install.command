#!/bin/zsh
# Double-click in Finder, in the GUI session (signing needs the unlocked login keychain and the Xcode account):
# signed device build, then install on the paired iPhone. Everything goes to ~/.velov-ios-install.log, ending with DONE.
export PATH=/opt/homebrew/bin:$PATH
cd "${0:A:h}/.." || exit 1
LOG="$HOME/.velov-ios-install.log"
{
  echo "=== $(date '+%Y-%m-%d %H:%M:%S') make build && make install"
  make build && make install
  echo "exit status $?"
  echo DONE
} >> "$LOG" 2>&1
tail -n 5 "$LOG"
