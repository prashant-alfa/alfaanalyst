# Alfastack White-Label Operations

## Branch Roles

- `main`: upstream mirror (`upstream/main`, fast-forward only).
- `development`: Alfastack integration branch.
- `production`: release branch in this repo, promoted from tested `development`.
- `private production repo`: deployment repo (private) receiving mirrored `production` branch only.

## Daily Sync Workflow

Run:

```bash
./scripts/sync/daily_upstream_sync.sh
```

Context append helper:

```bash
./scripts/sync/update_context_file.sh
```

Optional environment flags:

- `AUTO_PUSH=true`: push sync branch to origin.
- `AUTO_PR=true`: create PR (requires `gh` auth).
- `RUN_TESTS=true`: run targeted backend MCP tests in the script.
- `RUN_FRONTEND_BUILD=true`: run `frontend-custom` production build gate.

Report output:

- `reports/daily-sync/YYYY-MM-DD.md`
- Context ledger (append-only):
  - `documents/alfastack-automation-context.md`

## Runtime Env Contract

- `BOW_INTERCOM_ENABLED`
- `BOW_INTERCOM_APP_ID`
- `BOW_TELEMETRY_ENABLED`
- `BOW_TELEMETRY_PROVIDER`
- `BOW_POSTHOG_API_KEY`
- `BOW_POSTHOG_HOST`

## Frontend White-Label Model

- Upstream baseline: `frontend/`
- Overlay source of truth: `branding/overlay/frontend`
- Generated target: `frontend-custom/`

Commands:

```bash
./scripts/branding/generate_frontend_overlay.sh
./scripts/branding/rebuild_frontend_custom.sh
```

## Release Gates

Run locally:

```bash
./scripts/branding/whitelabel_scan.sh
./scripts/branding/runtime_safety_check.sh
./scripts/branding/check_tracked_generated_files.sh
```

CI workflow:

- `.github/workflows/alfastack-whitelabel-gates.yml`
- `.github/workflows/alfastack-ci.yml`

CI coverage in `Alfastack CI`:

- White-label scan.
- Runtime safety checks.
- Generated files guard.
- Targeted backend test gate.
- `frontend-custom` production build.
- `Dockerfile.alfa` validation on push events.

## Production Promotion + Deploy

Manual workflow:

- `.github/workflows/alfastack-promote-deploy.yml`
- Auto trigger workflow:
  - `.github/workflows/alfastack-auto-promote-on-green.yml`
- Production mirror workflow:
  - `.github/workflows/alfastack-sync-to-private-production.yml`

What it does:

- Promotes tested `development` head to `production`.
- Runs white-label/runtime/generated-file gates.
- Optionally validates `Dockerfile.alfa` build.
- Auto trigger dispatches only when `Alfastack CI` succeeded on a `development` push.
- Promotion job uses GitHub Environment `production-approval` for explicit manual approval before any production branch update.
- Private production repo can deploy without any public-repo secrets by polling the public `production` branch on a schedule.
- The public mirror workflow is optional; keep it disabled if you do not want cross-repo credentials in this repo.

Recommended approach (no public repo secrets):

- Configure a scheduled workflow in the private repo to pull the public `production` branch on the server and deploy only when SHA changes.
- Private workflow lives in private repo at `.github/workflows/deploy-on-production-sync.yml`.

Optional approach (enables public -> private mirroring/dispatch):

Required GitHub secrets in this public repo:

- `PRIVATE_PROD_REPO_OWNER`
- `PRIVATE_PROD_REPO_NAME`
- `PRIVATE_PROD_REPO_PAT`
- Optional: `PRIVATE_PROD_REPO_DEPLOY_EVENT` (default event type: `production-sync`)

Required GitHub secrets in private production repo:

- `PROD_SSH_HOST`
- `PROD_SSH_USER`
- `PROD_SSH_KEY`
- `PROD_APP_DIR`
- Optional: `PROD_SSH_PORT`

Required GitHub repository setup:

- Create environment `production-approval`.
- Configure required reviewers (you/team) on `production-approval`.
- Keep `Wait timer` optional; use it only if you want delayed deploy windows.
- Configure branch protection:
  - `development`: require status check `Alfastack CI`.
  - `production`: require status checks `Alfastack CI` and `Alfastack White-Label Gates`.
  - Restrict direct pushes to `production` except workflow/bot paths you approve.
- Create private repo (example: `alfaanlyst-production`) with only branch `production`.
- Add deploy workflow in private repo that reacts to `repository_dispatch` event from public repo.

## Compliance Note

This project remains AGPL-licensed. White-labeling UI and runtime branding does not remove AGPL distribution/network-use obligations.
