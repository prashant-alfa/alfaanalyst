# Branding Workflow

This directory is the canonical white-label source for Alfastack.

- `brand.config.yaml`: Runtime brand contract consumed by backend and frontend.
- `overlay/frontend`: White-label overlay applied on top of upstream `frontend/`.
- `whitelabel-allowlist.txt`: Scanner allowlist for intentional technical references.

## Commands

- Rebuild custom frontend from upstream baseline + overlay:
  - `./scripts/branding/rebuild_frontend_custom.sh`
- Snapshot current `frontend-custom` into deterministic overlay:
  - `./scripts/branding/generate_frontend_overlay.sh`
- Run brand leak scanner:
  - `./scripts/branding/whitelabel_scan.sh`
