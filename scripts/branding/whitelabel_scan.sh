#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ALLOWLIST_FILE="${ALLOWLIST_FILE:-$ROOT_DIR/branding/whitelabel-allowlist.txt}"

TOKENS=(
  "Bag of words"
  "Bag of Words"
  "bagofwords.com"
  "docs.bagofwords.com"
  "ocwih86k"
  "\"bagofwords\""
)

SCAN_PATHS=(
  "$ROOT_DIR/frontend-custom"
  "$ROOT_DIR/backend/app"
  "$ROOT_DIR/backend/main.py"
  "$ROOT_DIR/bow-config.yaml"
  "$ROOT_DIR/configs"
)

tmp_all="$(mktemp)"
tmp_filtered="$(mktemp)"
trap 'rm -f "$tmp_all" "$tmp_filtered"' EXIT

for token in "${TOKENS[@]}"; do
  rg -n --fixed-strings \
    --glob '!frontend-custom/node_modules/**' \
    --glob '!frontend-custom/.nuxt/**' \
    --glob '!frontend-custom/.output/**' \
    --glob '!.git/**' \
    "$token" "${SCAN_PATHS[@]}" >> "$tmp_all" || true
done

sort -u "$tmp_all" > "$tmp_filtered"

if [[ -s "$tmp_filtered" && -f "$ALLOWLIST_FILE" ]]; then
  tmp_remaining="$(mktemp)"
  trap 'rm -f "$tmp_all" "$tmp_filtered" "$tmp_remaining"' EXIT
  while IFS= read -r finding; do
    allow=false
    while IFS= read -r rule; do
      [[ -z "$rule" || "$rule" =~ ^# ]] && continue
      if [[ "$finding" =~ $rule ]]; then
        allow=true
        break
      fi
    done < "$ALLOWLIST_FILE"

    if [[ "$allow" == false ]]; then
      echo "$finding" >> "$tmp_remaining"
    fi
  done < "$tmp_filtered"
  mv "$tmp_remaining" "$tmp_filtered"
fi

if [[ -s "$tmp_filtered" ]]; then
  echo "White-label scan failed. Forbidden tokens detected:"
  cat "$tmp_filtered"
  exit 1
fi

echo "White-label scan passed."
