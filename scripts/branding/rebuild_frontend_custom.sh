#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASELINE_DIR="${1:-$ROOT_DIR/frontend}"
TARGET_DIR="${2:-$ROOT_DIR/frontend-custom}"
OVERLAY_DIR="${3:-$ROOT_DIR/branding/overlay/frontend}"

if [[ ! -d "$BASELINE_DIR" ]]; then
  echo "Baseline frontend directory not found: $BASELINE_DIR" >&2
  exit 1
fi

mkdir -p "$TARGET_DIR"

rsync -a --delete \
  --exclude 'node_modules/' \
  --exclude '.nuxt/' \
  --exclude '.output/' \
  --exclude '.data/' \
  --exclude '.cache/' \
  --exclude 'dist/' \
  "$BASELINE_DIR"/ "$TARGET_DIR"/

if [[ -d "$OVERLAY_DIR" ]]; then
  # Use checksum so same-size/same-mtime files in overlay still override baseline content.
  rsync -a --checksum "$OVERLAY_DIR"/ "$TARGET_DIR"/
fi

DELETE_LIST="$OVERLAY_DIR/.delete-list"
if [[ -f "$DELETE_LIST" ]]; then
  while IFS= read -r relative_path; do
    [[ -z "$relative_path" ]] && continue
    rm -rf "$TARGET_DIR/$relative_path"
  done < "$DELETE_LIST"
fi

echo "frontend-custom rebuilt from baseline + overlay."
