# Repository Guidelines

## Project Structure & Module Organization
- Terraform root: this directory contains the working tree.
- Key files: `main.tf` (entry), `variables.tf`, `outputs.tf`.
- Templates: `templates/` (e.g., `Caddyfile.tmpl`, `docker-compose.yml.tmpl`, `frps.toml.tmpl`).
- Cloud-init and ancillary files: `files/cloud-init.yaml`.
- Variables: `terraform.tfvars.example` (copy to `terraform.tfvars` for real values), `tftest.tfvars` for local test plans.
- Lock/state: `.terraform.lock.hcl` should be tracked; do not edit state files (`terraform.tfstate*`) manually.

## Build, Test, and Development Commands
- Init providers/modules: `terraform init`
- Format HCL consistently: `terraform fmt -recursive`
- Static checks: `terraform validate`
- Dry-run with test vars: `terraform plan -var-file=tftest.tfvars`
- Apply after review: `terraform apply -var-file=terraform.tfvars`
- Clean-up (be careful): `terraform destroy -var-file=terraform.tfvars`

## Coding Style & Naming Conventions
- Use `terraform fmt`; 2-space indentation; wrap long lines thoughtfully.
- Use `snake_case` for variables and resource names. Prefer clear prefixes per component (e.g., `frp_`, `caddy_`, `vps_`).
- Keep templates minimal and idempotent; placeholder names in `snake_case`.

## Testing Guidelines
- Required: `terraform validate` must pass; `terraform plan -var-file=tftest.tfvars` should be clean and show intended changes only.
- Include a brief plan excerpt in PRs (first ~100 lines) to illustrate changes.
- No Terratest is wired; if you add it, place code under `test/` and document how to run it.

## Commit & Pull Request Guidelines
- Commits: imperative mood and concise (e.g., `feat: add frps template`, `fix: correct SG egress`).
- PRs must include: purpose, notable diffs (affected resources), plan excerpt, rollback notes (`destroy`/revert steps), and linked issue.
- Avoid committing secrets or local state. Commit only `terraform.tfvars.example` with placeholders.

## Security & Configuration Tips
- Provide sensitive values via `terraform.tfvars` (untracked) or `TF_VAR_...` env vars (e.g., `export TF_VAR_sakuravps_api_token=...`).
- Never hardcode secrets in `.tf` files or `templates/`; prefer variables and file inputs.
- Do not edit or review `terraform.tfstate*` in PRs; treat it as ephemeral.

