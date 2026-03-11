#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTEXT_FILE="${CONTEXT_FILE:-$ROOT_DIR/documents/alfastack-automation-context.md}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
RUN_TYPE="${RUN_TYPE:-daily-sync}"
RUN_TIMESTAMP_UTC="${RUN_TIMESTAMP_UTC:-$(date -u +'%Y-%m-%d %H:%M:%SZ')}"

MAIN_BEFORE="${MAIN_BEFORE:-unknown}"
MAIN_AFTER="${MAIN_AFTER:-unknown}"
DEV_SHA="${DEV_SHA:-unknown}"
SYNC_BRANCH="${SYNC_BRANCH:-unknown}"
UPSTREAM_COMMIT_COUNT="${UPSTREAM_COMMIT_COUNT:-0}"
UPSTREAM_FRONTEND_CHANGES="${UPSTREAM_FRONTEND_CHANGES:-0}"
UPSTREAM_BACKEND_CHANGES="${UPSTREAM_BACKEND_CHANGES:-0}"
WHITE_LABEL_GATE="${WHITE_LABEL_GATE:-unknown}"
RUNTIME_GATE="${RUNTIME_GATE:-unknown}"
GENERATED_FILES_GATE="${GENERATED_FILES_GATE:-unknown}"
TEST_RESULTS="${TEST_RESULTS:-Skipped}"
BUILD_RESULTS="${BUILD_RESULTS:-Skipped}"
PR_LINKS="${PR_LINKS:-Not created}"
PROMOTION_RECOMMENDATION="${PROMOTION_RECOMMENDATION:-Review required}"
REPORT_PATH="${REPORT_PATH:-Not generated}"

mkdir -p "$(dirname "$CONTEXT_FILE")"

if [[ ! -f "$CONTEXT_FILE" ]]; then
  cat > "$CONTEXT_FILE" <<'EOF'
# Alfastack Automation Context

This file is append-only and stores automation run snapshots.

## Run Ledger
EOF
fi

report_display="$REPORT_PATH"
if [[ "$REPORT_PATH" == "$ROOT_DIR"* ]]; then
  report_display="${REPORT_PATH#$ROOT_DIR/}"
fi

cat >> "$CONTEXT_FILE" <<EOF

### Run $RUN_ID ($RUN_TYPE)

- Timestamp (UTC): \`$RUN_TIMESTAMP_UTC\`
- Branch heads:
  - \`main(before)\`: \`$MAIN_BEFORE\`
  - \`main(after)\`: \`$MAIN_AFTER\`
  - \`development\`: \`$DEV_SHA\`
  - \`sync\`: \`$SYNC_BRANCH\`
- Upstream analysis:
  - Commit count: \`$UPSTREAM_COMMIT_COUNT\`
  - Frontend file changes: \`$UPSTREAM_FRONTEND_CHANGES\`
  - Backend file changes: \`$UPSTREAM_BACKEND_CHANGES\`
- Gates:
  - White-label scan: \`$WHITE_LABEL_GATE\`
  - Runtime safety: \`$RUNTIME_GATE\`
  - Generated files: \`$GENERATED_FILES_GATE\`
  - Tests: \`$TEST_RESULTS\`
  - Build: \`$BUILD_RESULTS\`
- PR links: $PR_LINKS
- Promotion recommendation: \`$PROMOTION_RECOMMENDATION\`
- Report: \`$report_display\`
EOF

echo "Context updated: $CONTEXT_FILE"
