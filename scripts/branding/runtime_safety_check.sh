#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
failures=0

check_or_fail() {
  local message="$1"
  local command="$2"
  if ! eval "$command"; then
    echo "[FAIL] $message"
    failures=$((failures + 1))
  fi
}

extract_enabled_value() {
  local file="$1"
  local section="$2"
  awk -v section="$section" '
    $0 ~ "^" section ":" { in_section=1; next }
    in_section && $0 ~ "^[^[:space:]]" { in_section=0 }
    in_section && $1 == "enabled:" { print $2; exit }
  ' "$file"
}

check_or_fail \
  "Intercom guard must use intercomConfig.enabled in default layout" \
  "rg -q \"intercomConfig.enabled === true\" \"$ROOT_DIR/frontend-custom/layouts/default.vue\""

check_or_fail \
  "Intercom guard must use intercomConfig.enabled in users layout" \
  "rg -q \"intercomConfig.enabled === true\" \"$ROOT_DIR/frontend-custom/layouts/users.vue\""

check_or_fail \
  "Legacy truthiness guard must not exist in default layout" \
  "! rg -q \"environment === 'production' && intercom\\)\" \"$ROOT_DIR/frontend-custom/layouts/default.vue\""

check_or_fail \
  "Legacy truthiness guard must not exist in users layout" \
  "! rg -q \"environment === 'production' && intercom\\)\" \"$ROOT_DIR/frontend-custom/layouts/users.vue\""

check_or_fail \
  "Telemetry must not contain hardcoded PostHog API keys" \
  "! rg -q \"phc_[A-Za-z0-9]\" \"$ROOT_DIR/backend/app/core/telemetry.py\""

for env_var in BOW_TELEMETRY_ENABLED BOW_TELEMETRY_PROVIDER BOW_POSTHOG_API_KEY BOW_POSTHOG_HOST; do
  check_or_fail \
    "Telemetry must reference env contract variable $env_var" \
    "rg -q \"$env_var\" \"$ROOT_DIR/backend/app/core/telemetry.py\""
done

root_intercom_enabled="$(extract_enabled_value "$ROOT_DIR/bow-config.yaml" "intercom")"
root_telemetry_enabled="$(extract_enabled_value "$ROOT_DIR/bow-config.yaml" "telemetry")"

if [[ "$root_intercom_enabled" != "false" ]]; then
  echo "[FAIL] bow-config.yaml intercom.enabled must default to false"
  failures=$((failures + 1))
fi

if [[ "$root_telemetry_enabled" != "false" ]]; then
  echo "[FAIL] bow-config.yaml telemetry.enabled must default to false"
  failures=$((failures + 1))
fi

if [[ "$failures" -gt 0 ]]; then
  echo "Runtime safety checks failed with $failures issue(s)."
  exit 1
fi

echo "Runtime safety checks passed."
