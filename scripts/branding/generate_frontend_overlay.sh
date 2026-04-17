#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BASELINE_DIR="${1:-$ROOT_DIR/frontend}"
SOURCE_DIR="${2:-$ROOT_DIR/frontend-custom}"
OVERLAY_DIR="${3:-$ROOT_DIR/branding/overlay/frontend}"

if [[ ! -d "$BASELINE_DIR" ]]; then
  echo "Baseline frontend directory not found: $BASELINE_DIR" >&2
  exit 1
fi

if [[ ! -d "$SOURCE_DIR" ]]; then
  echo "Source frontend-custom directory not found: $SOURCE_DIR" >&2
  exit 1
fi

rm -rf "$OVERLAY_DIR"
mkdir -p "$OVERLAY_DIR"

# Snapshot custom frontend as overlay without generated/vendor artifacts.
rsync -a --delete \
  --exclude '.DS_Store' \
  --exclude 'node_modules/' \
  --exclude '.nuxt/' \
  --exclude '.output/' \
  --exclude '.data/' \
  --exclude '.cache/' \
  --exclude 'dist/' \
  "$SOURCE_DIR"/ "$OVERLAY_DIR"/

# Drop files that are identical to upstream baseline to keep overlay minimal.
while IFS= read -r -d '' file; do
  relative_path="${file#$OVERLAY_DIR/}"
  baseline_file="$BASELINE_DIR/$relative_path"
  if [[ -f "$baseline_file" ]] && cmp -s "$file" "$baseline_file"; then
    rm -f "$file"
  fi
done < <(find "$OVERLAY_DIR" -type f -print0)

# Track deletions explicitly so rebuild can remove them from baseline.
DELETE_LIST="$OVERLAY_DIR/.delete-list"
touch "$DELETE_LIST"
while IFS= read -r -d '' baseline_file; do
  relative_path="${baseline_file#$BASELINE_DIR/}"
  if [[ ! -e "$SOURCE_DIR/$relative_path" ]]; then
    echo "$relative_path" >> "$DELETE_LIST"
  fi
done < <(
  find "$BASELINE_DIR" \
    -path "$BASELINE_DIR/node_modules" -prune -o \
    -path "$BASELINE_DIR/.nuxt" -prune -o \
    -path "$BASELINE_DIR/.output" -prune -o \
    -path "$BASELINE_DIR/.data" -prune -o \
    -path "$BASELINE_DIR/.cache" -prune -o \
    -path "$BASELINE_DIR/dist" -prune -o \
    -name '.DS_Store' -prune -o \
    -type f -print0
)

if [[ ! -s "$DELETE_LIST" ]]; then
  rm -f "$DELETE_LIST"
fi

find "$OVERLAY_DIR" -mindepth 1 -type d -empty -delete

echo "Overlay generated at: $OVERLAY_DIR"
