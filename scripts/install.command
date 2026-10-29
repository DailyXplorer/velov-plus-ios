#!/bin/zsh
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
