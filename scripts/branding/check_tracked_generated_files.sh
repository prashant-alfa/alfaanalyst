#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

tracked_generated="$(git ls-files | rg '^frontend-custom/(node_modules|\.nuxt|\.output)/' || true)"

if [[ -n "$tracked_generated" ]]; then
  echo "Tracked generated files detected under frontend-custom:"
  echo "$tracked_generated"
  exit 1
fi

echo "No tracked generated frontend-custom files detected."
