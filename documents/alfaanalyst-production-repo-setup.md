# Alfastack Private Production Repo Setup

This runbook sets up the split-repo model:

- Public repo (`bagofwords` fork): upstream sync, white-label checks, promotion to `production`, mirror to private repo.
- Private repo (example: `alfaanlyst-production`): deployment workflows and infra secrets.

## 1. Create Private Repo

Create private repository:

- Name: `alfaanlyst-production` (or your preferred private repo name).
- Default branch: `production`.
- Do not fork publicly.

## 2. Add Public Repo Secrets (for mirror workflow)

In public repo settings, add:

- `PRIVATE_PROD_REPO_OWNER`
- `PRIVATE_PROD_REPO_NAME`
- `PRIVATE_PROD_REPO_PAT`
- Optional: `PRIVATE_PROD_REPO_DEPLOY_EVENT` (defaults to `production-sync`)

PAT requirements:

- Fine-grained PAT scoped to target private repo.
- Permissions: `contents:write`, `actions:write` (for dispatch).

## 3. Add Private Repo Secrets (for deploy workflow)

In private repo settings, add:

- `PROD_SSH_HOST`
- `PROD_SSH_USER`
- `PROD_SSH_KEY`
- `PROD_APP_DIR`
- Optional: `PROD_SSH_PORT`

## 4. Add Private Repo Deploy Workflow

Use template file:

- `documents/templates/private-production-deploy-on-sync.yml`

Copy it to private repo path:

- `.github/workflows/deploy-on-production-sync.yml`

## 5. Initial Branch Bootstrap

In public repo, run manual workflow:

- `Alfastack Sync To Private Production Repo`

This mirrors current public `production` branch to private `production`.

## Alternative: No Public Repo Secrets (Recommended)

If you do not want any cross-repo credentials in the public repo, you can skip section 2 entirely.

Instead:

- Keep private repo deploy secrets (section 3).
- Configure the private repo workflow to poll the public `production` branch on a schedule and deploy only when SHA changes.
- The workflow runs `git fetch` on the server against the public repo, so the server never needs private-repo credentials.

## 6. End-to-End Flow

1. Upstream sync and branding checks land on `development`.
2. `Alfastack CI` passes on `development`.
3. `Alfastack Auto Promote On Green Development` dispatches promotion.
4. `Alfastack Promote Production` waits for `production-approval`.
5. After approval, public `production` is updated.
6. Private repo scheduled workflow deploys by pulling public `production` on the server (no public repo secrets).
7. (Optional) Mirror workflow can be used if you decide to add public secrets later.

## 7. Guardrails

- Keep branch protection on public `development` and `production`.
- Restrict direct pushes to public `production`.
- Keep deploy credentials only in private repo.
