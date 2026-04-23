# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

Estabilis Platform — a self-hosted platform engineering framework using CNCF tools on Azure. This is the **public upstream** repository. Clients get private downstream repos that reference this upstream via ArgoCD.

Three-repo architecture:
- **estabilis-platform** (this repo) — public upstream, Terraform + ArgoCD manifests
- **estabilis-platform-downstream** — private template, cloned per client
- **estabilis-platform-tools** — private internal, justfiles + operational recipes

## Architecture

Terraform creates **only**: AKS cluster, VNet/subnets, Storage Account, Key Vault, Workload Identities, and a single ArgoCD Helm release (seed). Everything else deploys via **ArgoCD App of Apps** pattern — no other helm_release in Terraform.

ArgoCD sync waves: cert-manager(1) → cert-manager-config+kyverno+cnpg-operator(2) → external-secrets(3) → cluster-secret-store+platform-secrets+trivy(4) → cnpg-cluster+external-dns+traefik(5) → grafana-stack+opencost+velero(6) → loki-ingress(7)

All resource names use `var.name_prefix` for multi-client support. Product labels use `estabilis.io/` prefix (fixed convention, not client-configurable).

## Key Paths

- `providers/azure/` — Terraform for Azure (AKS, networking, storage, Key Vault, identities, ArgoCD seed, platform-root)
- `providers/aws/` — Terraform for AWS (EKS, VPC, S3, Secrets Manager, IRSA, ArgoCD seed, platform-root)
- `providers/<provider>/variables.tf` — Central variable definitions; all configurable values live here
- `bootstrap/platform-root/` — App of Apps Helm chart (ArgoCD Applications for each component)
- `core/components/<name>/` — Per-component values files referenced by ArgoCD Applications
- `core/values/defaults.yaml` — Platform-wide defaults (replicas, retention, namespaces)
- `core/values/azure.yaml` / `core/values/aws.yaml` — Provider-specific values

## Working With This Repo

This repo has no justfile (it's gitignored — justfiles live in estabilis-platform-tools). Operations are run from the client's downstream repo or the tools repo.

Pre-commit hooks are mandatory — install once per clone (see README.md "Development setup"). Before considering any edit complete, run the relevant subset of hooks against the changed files:

```bash
pre-commit run --files <changed-files>
# or, for a full sweep:
pre-commit run --all-files
```

The hooks enforce `terraform fmt`, `terraform validate`, `tflint`, secret scanning (`gitleaks`, `detect-private-key`, `detect-aws-credentials`), YAML syntax, line-ending normalization, and Conventional Commits. An edit that fails hooks is not done.

For Terraform work:
```bash
cd providers/azure   # or providers/aws
terraform init
terraform plan  -var-file=<provider>.tfvars
terraform apply -var-file=<provider>.tfvars
```

## Important Conventions

- ArgoCD tracks a **git tag** (e.g. `0.1.0-alpha`) as `targetRevision`. After commits, move the tag: `git tag -fa 0.1.0-alpha -m "..." && git push origin 0.1.0-alpha --force`
- Kyverno CRDs require `ServerSideApply=true` (exceeds 262KB annotation limit)
- cert-manager needs `kube-system` in AppProject destinations (leader election)
- `argocd-seed.tf` has `lifecycle { ignore_changes = [set, version] }` — ArgoCD manages itself after initial seed
- `.tfvars` files are gitignored — clients configure via their downstream repo's `azure.tfvars`
- No hardcoded credentials — use secrets.env (gitignored) or Azure Key Vault

## Pinned Versions

K8s 1.34, ArgoCD 9.4.7, Kyverno 3.7.1, cert-manager 1.20.0, external-secrets 2.1.0, external-dns 1.20.0, Grafana 10.5.15, Loki 6.54.0, Mimir (mimir-distributed) 6.1.0, Alloy 1.6.2, Traefik 39.1.0, Trivy 0.32.0, OpenCost 2.3.2, CNPG 0.23.0, Velero 11.4.0
