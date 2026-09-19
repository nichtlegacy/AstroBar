#!/usr/bin/env bash
# Exports the Sparkle EdDSA private key from the login keychain to a file.
#
#   scripts/backup_sparkle_key.sh ~/Desktop/sparkle-private-key.txt
#
# Without an Apple Developer account this key is the only thing that proves an
# update came from you. Lose it and every installed copy stops accepting
# updates; leak it and anyone can ship an update to every installed copy.
#
# Put the exported file somewhere encrypted (password manager, encrypted disk
# image) and delete the plaintext copy afterwards. The key can be restored with:
#   .build/artifacts/sparkle/Sparkle/bin/generate_keys -f <file>
set -euo pipefail

cd "$(dirname "$0")/.."

GENERATE_KEYS=".build/artifacts/sparkle/Sparkle/bin/generate_keys"
DEST="${1-}"

if [ -z "$DEST" ]; then
  echo "usage: scripts/backup_sparkle_key.sh <destination-file>" >&2
  exit 1
fi
if [ ! -x "$GENERATE_KEYS" ]; then
  echo "error: ${GENERATE_KEYS} not found, run 'swift package resolve' first" >&2
  exit 1
fi

DEST_DIR="$(cd "$(dirname "$DEST")" && pwd)"
REPO_DIR="$PWD"
case "$DEST_DIR/" in
  "$REPO_DIR"/*)
    echo "error: refusing to write the private key inside the repository" >&2
    echo "hint: pick a path outside ${REPO_DIR}" >&2
    exit 1
    ;;
esac
if [ -e "$DEST" ]; then
  echo "error: ${DEST} already exists, refusing to overwrite" >&2
  exit 1
fi

umask 077
"$GENERATE_KEYS" -x "$DEST"
chmod 600 "$DEST"

echo
echo "Private key exported to ${DEST} (mode 600)."
echo "Move it into encrypted storage and delete the plaintext copy."
echo "Public key currently in the bundle:"
"$GENERATE_KEYS" -p
