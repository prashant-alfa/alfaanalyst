#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

DATE_UTC="$(date +%F)"
RUN_ID_UTC="$(date -u +%Y%m%dT%H%M%SZ)"
REPORT_DIR="$ROOT_DIR/reports/daily-sync"
REPORT_PATH="$REPORT_DIR/$DATE_UTC.md"

MAIN_BRANCH="${MAIN_BRANCH:-main}"
DEV_BRANCH="${DEV_BRANCH:-development}"
SYNC_BRANCH="${SYNC_BRANCH:-alfaai/daily-sync-$DATE_UTC}"
UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
SYNC_MODE="${SYNC_MODE:-merge}"
CUSTOM_SOURCE_BRANCH="${CUSTOM_SOURCE_BRANCH:-$DEV_BRANCH}"
MANAGED_PATHS_FILE="${MANAGED_PATHS_FILE:-branding/managed-paths.txt}"
PIN_WORKFLOW_DIR_TO_SOURCE="${PIN_WORKFLOW_DIR_TO_SOURCE:-true}"

AUTO_PUSH="${AUTO_PUSH:-false}"
AUTO_PR="${AUTO_PR:-false}"
RUN_TESTS="${RUN_TESTS:-false}"
RUN_FRONTEND_BUILD="${RUN_FRONTEND_BUILD:-false}"
ALLOW_DIRTY_WORKTREE="${ALLOW_DIRTY_WORKTREE:-false}"
ALLOW_OFFLINE="${ALLOW_OFFLINE:-false}"
WORKTREE_REEXEC="${WORKTREE_REEXEC:-false}"
SOFT_FAIL="${SOFT_FAIL:-false}"

mkdir -p "$REPORT_DIR"

# Normalize to repo-relative so temp-clone re-exec and git tree lookups are stable.
if [[ "$MANAGED_PATHS_FILE" == /* ]]; then
  if [[ "$MANAGED_PATHS_FILE" == "$ROOT_DIR/"* ]]; then
    MANAGED_PATHS_FILE="${MANAGED_PATHS_FILE#$ROOT_DIR/}"
  else
    echo "MANAGED_PATHS_FILE must be repo-relative or inside repo root: $MANAGED_PATHS_FILE" >&2
    exit 1
  fi
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$ALLOW_DIRTY_WORKTREE" == "true" && "$WORKTREE_REEXEC" != "true" ]]; then
  temp_clone="$(mktemp -d /tmp/alfastack-sync-clone-XXXXXX)"
  origin_url="$(git remote get-url "$ORIGIN_REMOTE" 2>/dev/null || true)"
  upstream_url="$(git remote get-url "$UPSTREAM_REMOTE" 2>/dev/null || true)"
  context_dirty_in_source="$(git status --porcelain -- documents/alfastack-automation-context.md || true)"
  main_sha="$(git rev-parse "$MAIN_BRANCH" 2>/dev/null || true)"
  dev_sha="$(git rev-parse "$DEV_BRANCH" 2>/dev/null || true)"

  if ! git clone --quiet . "$temp_clone" >/dev/null 2>&1; then
    echo "Failed to create temporary clone for automation-safe run." >&2
    exit 1
  fi

  if [[ -n "$origin_url" ]]; then
    git -C "$temp_clone" remote set-url "$ORIGIN_REMOTE" "$origin_url" >/dev/null 2>&1 || true
  fi
  if [[ -n "$upstream_url" ]]; then
    if git -C "$temp_clone" remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
      git -C "$temp_clone" remote set-url "$UPSTREAM_REMOTE" "$upstream_url" >/dev/null 2>&1 || true
    else
      git -C "$temp_clone" remote add "$UPSTREAM_REMOTE" "$upstream_url" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "$main_sha" ]]; then
    git -C "$temp_clone" update-ref "refs/heads/$MAIN_BRANCH" "$main_sha" >/dev/null 2>&1 || true
  fi
  if [[ -n "$dev_sha" ]]; then
    git -C "$temp_clone" update-ref "refs/heads/$DEV_BRANCH" "$dev_sha" >/dev/null 2>&1 || true
  fi
  git -C "$temp_clone" checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true

  status=0
  if (
    cd "$temp_clone"
    AUTO_PUSH="$AUTO_PUSH" \
    AUTO_PR="$AUTO_PR" \
    RUN_TESTS="$RUN_TESTS" \
    RUN_FRONTEND_BUILD="$RUN_FRONTEND_BUILD" \
    MAIN_BRANCH="$MAIN_BRANCH" \
    DEV_BRANCH="$DEV_BRANCH" \
    SYNC_BRANCH="$SYNC_BRANCH" \
    UPSTREAM_REMOTE="$UPSTREAM_REMOTE" \
    ORIGIN_REMOTE="$ORIGIN_REMOTE" \
    SYNC_MODE="$SYNC_MODE" \
    CUSTOM_SOURCE_BRANCH="$CUSTOM_SOURCE_BRANCH" \
    MANAGED_PATHS_FILE="$MANAGED_PATHS_FILE" \
    PIN_WORKFLOW_DIR_TO_SOURCE="$PIN_WORKFLOW_DIR_TO_SOURCE" \
    ALLOW_OFFLINE="$ALLOW_OFFLINE" \
    ALLOW_DIRTY_WORKTREE="false" \
    WORKTREE_REEXEC="true" \
    SOFT_FAIL="$SOFT_FAIL" \
    ./scripts/sync/daily_upstream_sync.sh
  ); then
    status=0
  else
    status=$?
  fi

  if [[ -f "$temp_clone/reports/daily-sync/$DATE_UTC.md" ]]; then
    mkdir -p "$ROOT_DIR/reports/daily-sync"
    cp "$temp_clone/reports/daily-sync/$DATE_UTC.md" "$ROOT_DIR/reports/daily-sync/$DATE_UTC.md"
  fi

  if [[ -f "$temp_clone/documents/alfastack-automation-context.md" ]]; then
    if [[ -z "$context_dirty_in_source" ]]; then
      cp "$temp_clone/documents/alfastack-automation-context.md" "$ROOT_DIR/documents/alfastack-automation-context.md"
    else
      cp "$temp_clone/documents/alfastack-automation-context.md" "$ROOT_DIR/documents/alfastack-automation-context.latest.md"
    fi
  fi

  rm -rf "$temp_clone"
  exit "$status"
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is not clean. Commit/stash changes before running daily sync." >&2
  exit 1
fi

PR_LINKS="Not created"
TEST_RESULTS="Skipped"
BUILD_RESULTS="Skipped"
PROMOTION_RECOMMENDATION="Review required"
GATE_FAILED=false

WHITE_LABEL_GATE="NOT_RUN"
RUNTIME_GATE="NOT_RUN"
GENERATED_FILES_GATE="NOT_RUN"
INTERCOM_STATUS="unknown"
TELEMETRY_STATUS="unknown"

scan_output="Not run."
runtime_output="Not run."
generated_output="Not run."
test_output="Not run."
build_output="Not run."
FETCH_STATUS="online"
FETCH_NOTES="- Remotes fetched successfully."
SYNC_STRATEGY_NOTES="- Mode: \`$SYNC_MODE\`"
MANAGED_PATHS_REPORT="- Not applied (merge mode)."

cleanup() {
  git checkout "$CURRENT_BRANCH" >/dev/null 2>&1 || true
}
trap cleanup EXIT

count_changed_files() {
  local regex="$1"
  local files="$2"
  if [[ -z "$files" ]]; then
    echo "0"
    return
  fi
  # Avoid pipefail exits when there are zero matches.
  printf '%s\n' "$files" | awk -v re="$regex" '$0 ~ re { c++ } END { print c + 0 }'
}

build_commit_classification() {
  local range="$1"
  local subjects
  subjects="$(git log --pretty=format:'%s' "$range" || true)"
  if [[ -z "$subjects" ]]; then
    echo "- No upstream commits."
    return
  fi

  printf '%s\n' "$subjects" | awk '
    BEGIN {
      feat=fix=perf=refactor=docs=test=chore=other=0
    }
    {
      s=tolower($0)
      if (s ~ /^(feat|feature)(\(|:| )/) feat++
      else if (s ~ /^(fix|bugfix|hotfix)(\(|:| )/ || s ~ /\bfix\b/) fix++
      else if (s ~ /^(perf|optimi[sz]e)(\(|:| )/) perf++
      else if (s ~ /^(refactor)(\(|:| )/) refactor++
      else if (s ~ /^(docs|doc)(\(|:| )/) docs++
      else if (s ~ /^(test|tests)(\(|:| )/) test++
      else if (s ~ /^(chore|build|ci|style|revert)(\(|:| )/) chore++
      else other++
    }
    END {
      printf "- features: %d\n", feat
      printf "- bug_fixes: %d\n", fix
      printf "- performance: %d\n", perf
      printf "- refactors: %d\n", refactor
      printf "- docs: %d\n", docs
      printf "- tests: %d\n", test
      printf "- chores_ci_build: %d\n", chore
      printf "- uncategorized: %d\n", other
    }
  '
}

append_context() {
  RUN_ID="$RUN_ID_UTC" \
  RUN_TYPE="daily-sync" \
  RUN_TIMESTAMP_UTC="$(date -u +'%Y-%m-%d %H:%M:%SZ')" \
  MAIN_BEFORE="$main_before" \
  MAIN_AFTER="$main_after" \
  DEV_SHA="$(git rev-parse "$DEV_BRANCH" 2>/dev/null || echo unknown)" \
  SYNC_BRANCH="$SYNC_BRANCH" \
  UPSTREAM_COMMIT_COUNT="$upstream_commit_count" \
  UPSTREAM_FRONTEND_CHANGES="$upstream_frontend_changes" \
  UPSTREAM_BACKEND_CHANGES="$upstream_backend_changes" \
  WHITE_LABEL_GATE="$WHITE_LABEL_GATE" \
  RUNTIME_GATE="$RUNTIME_GATE" \
  GENERATED_FILES_GATE="$GENERATED_FILES_GATE" \
  TEST_RESULTS="$TEST_RESULTS" \
  BUILD_RESULTS="$BUILD_RESULTS" \
  PR_LINKS="$PR_LINKS" \
  PROMOTION_RECOMMENDATION="$PROMOTION_RECOMMENDATION" \
  REPORT_PATH="$REPORT_PATH" \
  ./scripts/sync/update_context_file.sh >/dev/null 2>&1 || true
}

fetch_failures=()
fetch_errors=()
if ! origin_fetch_error="$(git fetch "$ORIGIN_REMOTE" 2>&1)"; then
  fetch_failures+=("$ORIGIN_REMOTE")
  fetch_errors+=("$ORIGIN_REMOTE: ${origin_fetch_error//$'\n'/ | }")
fi
if ! upstream_fetch_error="$(git fetch "$UPSTREAM_REMOTE" 2>&1)"; then
  fetch_failures+=("$UPSTREAM_REMOTE")
  fetch_errors+=("$UPSTREAM_REMOTE: ${upstream_fetch_error//$'\n'/ | }")
fi

if [[ "${#fetch_failures[@]}" -gt 0 ]]; then
  if [[ "$ALLOW_OFFLINE" == "true" ]]; then
    FETCH_STATUS="offline-fallback"
    FETCH_NOTES="- Fetch failed for remotes: ${fetch_failures[*]}. Continuing with local refs."
    if [[ "${#fetch_errors[@]}" -gt 0 ]]; then
      FETCH_NOTES="$FETCH_NOTES"$'\n'"- Errors: ${fetch_errors[*]}"
    fi
    echo "$FETCH_NOTES"
  else
    if [[ "${#fetch_errors[@]}" -gt 0 ]]; then
      printf '%s\n' "${fetch_errors[@]}" >&2
    fi
    echo "Failed to fetch remotes: ${fetch_failures[*]}" >&2
    exit 1
  fi
fi

main_before="$(git rev-parse "$MAIN_BRANCH")"
git checkout "$MAIN_BRANCH"
if git show-ref --verify --quiet "refs/remotes/$UPSTREAM_REMOTE/$MAIN_BRANCH"; then
  git merge --ff-only "$UPSTREAM_REMOTE/$MAIN_BRANCH"
elif [[ "$FETCH_STATUS" == "offline-fallback" ]]; then
  echo "Upstream ref not available locally in offline mode; keeping $MAIN_BRANCH unchanged."
else
  echo "Missing ref refs/remotes/$UPSTREAM_REMOTE/$MAIN_BRANCH" >&2
  exit 1
fi
main_after="$(git rev-parse "$MAIN_BRANCH")"

upstream_commit_count="$(git rev-list --count "$main_before..$main_after")"
upstream_delta="$(git log --oneline "$main_before..$main_after" | sed 's/^/- /')"
if [[ -z "$upstream_delta" ]]; then
  upstream_delta="- No upstream changes."
fi

upstream_classification="$(build_commit_classification "$main_before..$main_after")"
changed_files="$(git diff --name-only "$main_before..$main_after" || true)"
upstream_frontend_changes="$(count_changed_files '^(frontend|frontend-custom)/' "$changed_files")"
upstream_backend_changes="$(count_changed_files '^backend/' "$changed_files")"

branding_surface_changes="$(printf '%s\n' "$changed_files" \
  | rg -e '^(frontend/|frontend-custom/|backend/|configs/|bow-config.yaml|docker-compose.yaml|Dockerfile|Dockerfile\.alfa)' \
  | head -n 80 \
  | sed 's/^/- /' || true)"
if [[ -z "$branding_surface_changes" ]]; then
  branding_surface_changes="- No branding-relevant file changes detected upstream."
fi

if [[ "$SYNC_MODE" == "rebuild" ]]; then
  if ! git rev-parse --verify "$CUSTOM_SOURCE_BRANCH" >/dev/null 2>&1; then
    echo "Custom source branch not found: $CUSTOM_SOURCE_BRANCH" >&2
    exit 1
  fi

  managed_paths_rel="$MANAGED_PATHS_FILE"
  if [[ "$managed_paths_rel" == "$ROOT_DIR/"* ]]; then
    managed_paths_rel="${managed_paths_rel#$ROOT_DIR/}"
  fi

  if ! git cat-file -e "$CUSTOM_SOURCE_BRANCH:$managed_paths_rel" 2>/dev/null; then
    echo "Managed paths file not found in source branch: $CUSTOM_SOURCE_BRANCH:$managed_paths_rel" >&2
    exit 1
  fi
  git checkout "$CUSTOM_SOURCE_BRANCH" -- "$managed_paths_rel"

  git checkout -B "$SYNC_BRANCH" "$MAIN_BRANCH"

  managed_paths=()
  while IFS= read -r line; do
    managed_paths+=("$line")
  done < <(awk '
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    { print }
  ' "$MANAGED_PATHS_FILE")

  if [[ "${#managed_paths[@]}" -eq 0 ]]; then
    echo "Managed paths file is empty: $MANAGED_PATHS_FILE" >&2
    exit 1
  fi

  existing_paths=()
  missing_paths=()
  for p in "${managed_paths[@]}"; do
    if git cat-file -e "$CUSTOM_SOURCE_BRANCH:$p" 2>/dev/null; then
      existing_paths+=("$p")
    else
      missing_paths+=("$p")
    fi
  done

  if [[ "${#existing_paths[@]}" -gt 0 ]]; then
    git checkout "$CUSTOM_SOURCE_BRANCH" -- "${existing_paths[@]}"
  fi

  workflow_dir_pin_status="disabled"
  if [[ "$PIN_WORKFLOW_DIR_TO_SOURCE" == "true" ]]; then
    if git cat-file -e "$CUSTOM_SOURCE_BRANCH:.github/workflows" 2>/dev/null; then
      # Keep workflow files identical to the source branch so GitHub Actions can
      # push sync branches with GITHUB_TOKEN even when upstream changes workflows.
      git checkout "$CUSTOM_SOURCE_BRANCH" -- .github/workflows
      workflow_dir_pin_status="source-branch"
    else
      workflow_dir_pin_status="source-missing"
    fi
  fi

  managed_paths_missing_preview="none"
  if [[ "${#missing_paths[@]}" -gt 0 ]]; then
    managed_paths_missing_preview="$(printf '%s\n' "${missing_paths[@]}" | head -n 20 | tr '\n' '; ' | sed 's/; $//')"
  fi

  SYNC_STRATEGY_NOTES="- Mode: \`rebuild\`"$'\n'"- Source branch: \`$CUSTOM_SOURCE_BRANCH\`"$'\n'"- Managed paths file: \`$MANAGED_PATHS_FILE\`"$'\n'"- Workflow dir pinned to source branch: \`$workflow_dir_pin_status\`"
  MANAGED_PATHS_REPORT="- Managed entries: \`${#managed_paths[@]}\`"$'\n'"- Applied from source branch: \`${#existing_paths[@]}\`"$'\n'"- Missing in source branch: \`${#missing_paths[@]}\`"$'\n'"- Missing preview: \`${managed_paths_missing_preview}\`"
else
  git checkout "$DEV_BRANCH"
  git checkout -B "$SYNC_BRANCH"

  if ! git merge --no-edit "$MAIN_BRANCH"; then
    WHITE_LABEL_GATE="BLOCKED_MERGE_CONFLICT"
    RUNTIME_GATE="BLOCKED_MERGE_CONFLICT"
    GENERATED_FILES_GATE="BLOCKED_MERGE_CONFLICT"
    TEST_RESULTS="Not run (merge conflict)"
    BUILD_RESULTS="Not run (merge conflict)"
    PROMOTION_RECOMMENDATION="Blocked: resolve merge conflicts before promotion."

    cat > "$REPORT_PATH" <<EOF
# Daily Sync Report ($DATE_UTC)

## Upstream Delta
$upstream_delta

## Remote Fetch
- Mode: \`$FETCH_STATUS\`
$FETCH_NOTES

## Sync Strategy
$SYNC_STRATEGY_NOTES
$MANAGED_PATHS_REPORT

## Upstream Commit Classification
$upstream_classification

## Branch State
- main(before): \`$main_before\`
- main(after): \`$main_after\`
- development: \`$(git rev-parse "$DEV_BRANCH")\`
- sync_branch: \`$SYNC_BRANCH\`

## White-Label Leak Scan
- Not run (merge conflict).

## Intercom Status
- Not evaluated (merge conflict).

## Telemetry Status
- Not evaluated (merge conflict).

## Test Results
- Not run (merge conflict).

## Build Results
- Not run (merge conflict).

## PR Links
- $PR_LINKS

## Promotion Recommendation
- $PROMOTION_RECOMMENDATION
EOF
    echo "Merge conflict detected. Report written to $REPORT_PATH"
    append_context
    if [[ "$SOFT_FAIL" == "true" ]]; then
      exit 0
    fi
    exit 1
  fi
fi

./scripts/branding/rebuild_frontend_custom.sh

if scan_output="$(./scripts/branding/whitelabel_scan.sh 2>&1)"; then
  WHITE_LABEL_GATE="PASS"
else
  WHITE_LABEL_GATE="FAIL"
  GATE_FAILED=true
fi

if runtime_output="$(./scripts/branding/runtime_safety_check.sh 2>&1)"; then
  RUNTIME_GATE="PASS"
else
  RUNTIME_GATE="FAIL"
  GATE_FAILED=true
fi

if generated_output="$(./scripts/branding/check_tracked_generated_files.sh 2>&1)"; then
  GENERATED_FILES_GATE="PASS"
else
  GENERATED_FILES_GATE="FAIL"
  GATE_FAILED=true
fi

INTERCOM_STATUS="$(awk '
  /^intercom:/ { in_section=1; next }
  in_section && /^[^[:space:]]/ { in_section=0 }
  in_section && $1 == "enabled:" { print $2; exit }
' bow-config.yaml | head -n1)"

TELEMETRY_STATUS="$(awk '
  /^telemetry:/ { in_section=1; next }
  in_section && /^[^[:space:]]/ { in_section=0 }
  in_section && $1 == "enabled:" { print $2; exit }
' bow-config.yaml | head -n1)"

if [[ "$RUN_TESTS" == "true" ]]; then
  if (cd backend && python -m pip install -r requirements_versioned.txt >/tmp/alfastack-daily-pytest-install.log 2>&1); then
    if (cd backend && TESTING=true ENVIRONMENT=production BOW_SMTP_PORT="${BOW_SMTP_PORT:-587}" python -m pytest -q tests/e2e/test_mcp.py >/tmp/alfastack-daily-pytest.log 2>&1); then
      TEST_RESULTS="PASS (backend/tests/e2e/test_mcp.py)"
      test_output="$(cat /tmp/alfastack-daily-pytest.log)"
    else
      GATE_FAILED=true
      TEST_RESULTS="FAIL (backend/tests/e2e/test_mcp.py)"
      test_output="$(cat /tmp/alfastack-daily-pytest.log)"
    fi
  else
    GATE_FAILED=true
    TEST_RESULTS="FAIL (backend dependency refresh)"
    test_output="$(cat /tmp/alfastack-daily-pytest-install.log)"
  fi
fi

if [[ "$RUN_FRONTEND_BUILD" == "true" ]]; then
  if (cd frontend-custom && yarn install --frozen-lockfile >/tmp/alfastack-daily-frontend-install.log 2>&1); then
    if (cd frontend-custom && yarn build >/tmp/alfastack-daily-frontend-build.log 2>&1); then
      BUILD_RESULTS="PASS (frontend-custom yarn build)"
      build_output="$(cat /tmp/alfastack-daily-frontend-build.log)"
    else
      GATE_FAILED=true
      BUILD_RESULTS="FAIL (frontend-custom yarn build)"
      build_output="$(cat /tmp/alfastack-daily-frontend-build.log)"
    fi
  else
    GATE_FAILED=true
    BUILD_RESULTS="FAIL (frontend-custom dependency refresh)"
    build_output="$(cat /tmp/alfastack-daily-frontend-install.log)"
  fi
fi

if [[ "$upstream_commit_count" -gt 0 || "$GATE_FAILED" == "true" ]]; then
  append_context
fi

if ! git diff --quiet; then
  git add -A
  git commit -m "chore: daily upstream sync ($DATE_UTC)" >/dev/null 2>&1
fi

sync_head="$(git rev-parse HEAD)"
dev_head="$(git rev-parse "$DEV_BRANCH")"
if [[ "$sync_head" != "$dev_head" ]]; then
  if [[ "$AUTO_PUSH" == "true" ]]; then
    git push -u "$ORIGIN_REMOTE" "$SYNC_BRANCH" --force-with-lease
    if [[ "$AUTO_PR" == "true" ]] && command -v gh >/dev/null 2>&1; then
      pr_create_output=""
      pr_create_success="false"
      for attempt in 1 2 3; do
        if pr_create_output="$(gh pr create --base "$DEV_BRANCH" --head "$SYNC_BRANCH" --title "Daily upstream sync ($DATE_UTC)" --body "Automated daily upstream sync and white-label checks." 2>&1)"; then
          pr_create_success="true"
          break
        fi
        sleep $((attempt * 3))
      done

      if [[ "$pr_create_success" == "true" ]]; then
        PR_LINKS="$pr_create_output"
      else
        existing_pr_url="$(gh pr list --base "$DEV_BRANCH" --head "$SYNC_BRANCH" --state open --json url --jq '.[0].url' 2>/dev/null || true)"
        if [[ -n "$existing_pr_url" ]]; then
          PR_LINKS="$existing_pr_url"
        else
          sanitized_error="${pr_create_output//$'\n'/ | }"
          PR_LINKS="PR creation failed: ${sanitized_error:-unknown error}"
        fi
      fi
    else
      PR_LINKS="Push complete. Create PR from $SYNC_BRANCH -> $DEV_BRANCH"
    fi
  else
    PR_LINKS="Not pushed. Local branch ready: $SYNC_BRANCH"
  fi
else
  PR_LINKS="No upstream delta to push"
fi

if [[ "$GATE_FAILED" == "true" ]]; then
  PROMOTION_RECOMMENDATION="Block promotion: one or more gates failed"
else
  PROMOTION_RECOMMENDATION="Eligible for review-required promotion"
fi

cat > "$REPORT_PATH" <<EOF
# Daily Sync Report ($DATE_UTC)

## Upstream Delta
$upstream_delta

## Remote Fetch
- Mode: \`$FETCH_STATUS\`
$FETCH_NOTES

## Sync Strategy
$SYNC_STRATEGY_NOTES
$MANAGED_PATHS_REPORT

## Upstream Commit Classification
$upstream_classification

## Surface Delta
- Upstream commit count: \`$upstream_commit_count\`
- Frontend file changes: \`$upstream_frontend_changes\`
- Backend file changes: \`$upstream_backend_changes\`

### Branding-Relevant Paths Changed
$branding_surface_changes

## Branch State
- main(before): \`$main_before\`
- main(after): \`$main_after\`
- development: \`$(git rev-parse "$DEV_BRANCH")\`
- sync_branch: \`$SYNC_BRANCH\`
- current_branch: \`$(git rev-parse --abbrev-ref HEAD)\`

## White-Label Leak Scan
- Gate status: \`$WHITE_LABEL_GATE\`
\`\`\`
$scan_output
\`\`\`

## Intercom Status
- bow-config intercom.enabled: \`${INTERCOM_STATUS:-unknown}\`

## Telemetry Status
- bow-config telemetry.enabled: \`${TELEMETRY_STATUS:-unknown}\`
- Runtime safety gate: \`$RUNTIME_GATE\`
\`\`\`
$runtime_output
\`\`\`

## Generated Files Guard
- Gate status: \`$GENERATED_FILES_GATE\`
\`\`\`
$generated_output
\`\`\`

## Test Results
- $TEST_RESULTS
\`\`\`
$test_output
\`\`\`

## Build Results
- $BUILD_RESULTS
\`\`\`
$build_output
\`\`\`

## PR Links
- $PR_LINKS

## Promotion Recommendation
- $PROMOTION_RECOMMENDATION
EOF

echo "Daily sync completed. Report: $REPORT_PATH"

if [[ "$GATE_FAILED" == "true" ]]; then
  if [[ "$SOFT_FAIL" == "true" ]]; then
    echo "One or more gates failed; SOFT_FAIL=true so exiting successfully."
    exit 0
  fi
  echo "One or more gates failed; failing daily sync run."
  exit 1
fi
