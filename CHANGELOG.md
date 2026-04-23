# Changelog

## [0.15.2] - 2026-04-23

### Changed — region_code in resource names uses AWS-official format

Resource names derived from `base_name` previously stripped dashes
from the AWS region (`us-east-1` → `useast1`) for visual parity with
the Azure provider's `eastus2` format. Every AWS CLI, tag, and AWS
doc refers to the region with dashes, so the compact form created
cognitive overhead without benefit.

Now the region is inserted verbatim:

```
cluster_name: eks-cortex-platform-prd-us-east-1   (was: eks-cortex-platform-prd-useast1)
```

All derivatives (S3 buckets, IAM roles, KMS aliases, DynamoDB) follow.
Dashes inside the region are safe in every AWS resource name we create.

**Breaking**: existing AWS deployments on v0.15.1 produce different
resource names on v0.15.2. Since v0.15.1 had only one deployment
(cortex test, being destroyed) and no production use, no migration is
needed beyond re-applying the test.

- `providers/aws/main.tf`: `locals.region_code = var.region` (dropped
  the `replace()` call).

### Fixed — tfstate resources are destroyable; Karpenter roles are per-cluster

Two blockers discovered after the first successful `terraform apply`:

#### Fix 1 — `prevent_destroy = true` blocked `terraform destroy` even on
empty buckets and lock tables

`aws_s3_bucket.tfstate` and `aws_dynamodb_table.tfstate_lock` shipped
with `lifecycle { prevent_destroy = true }`, which cannot be disabled
via a variable (Terraform does not support variable-driven
`prevent_destroy`). Operators rebuilding an HML/test deployment hit:

```
Error: Instance cannot be destroyed
  Resource ... has lifecycle.prevent_destroy set, but the plan calls
  for this resource to be destroyed.
```

The only workarounds were editing the module cache by hand or running
a targeted destroy excluding those two resources — both bad UX.

Removed the `lifecycle.prevent_destroy` block from both resources.
The safety net that still applies:

- `s3_force_destroy = false` (default) — Terraform refuses to delete
  a bucket that has objects (including the real tfstate file).
- `s3_tfstate_protect_critical = true` (opt-in, default false) —
  enables Object Lock (governance mode) on the tfstate bucket for
  production deployments that need WORM semantics.

DynamoDB lock table holds only active terraform lock records
(ephemeral) so no equivalent guard is needed.

- `providers/aws/tfstate.tf`: remove `lifecycle { prevent_destroy }`
  from `aws_s3_bucket.tfstate` and `aws_dynamodb_table.tfstate_lock`,
  document the remaining safety guards in comments.

#### Fix 2 — Karpenter IAM role names are per-cluster

The `terraform-aws-modules/eks/aws//modules/karpenter` submodule
defaults `iam_role_name` to the hardcoded string `"KarpenterController"`
(not a function of the cluster name). The node role default does
include `Karpenter-<cluster>`, but the controller role did not. With
`iam_role_use_name_prefix = false` (required by v0.15.1 to avoid the
38-char name_prefix cap), the controller role lands in IAM as the
literal `"KarpenterController"`.

Consequence: two Estabilis deployments in the same AWS account would
both try to create `KarpenterController` → collision on the second
apply.

Pinned both role names explicitly to include the cluster name:

```
iam_role_name      = "Karpenter-${module.eks.cluster_name}"
node_iam_role_name = "KarpenterNode-${module.eks.cluster_name}"
```

Node role default already included the cluster name; we set it
explicitly too for consistency with the controller naming scheme.

- `providers/aws/karpenter.tf`: explicit `iam_role_name` and
  `node_iam_role_name` inputs to the module.

### Backward compatibility

v0.15.1 was only deployed once (cortex test, currently being torn
down for a rebuild with `name_prefix = "cortex"`). Next apply of the
cortex test pins v0.15.2 so the new Karpenter role names and the
destroyable tfstate land together. No other deployments exist.

## [0.15.1] - 2026-04-23

### Fixed — `terraform plan` regressions in the AWS provider

Two bugs surfaced when running `terraform plan` for real (both slipped
through `terraform validate` because the type/length checks are only
exercised at plan-time once module resource attributes resolve).

#### Fix 1 — `cluster_encryption_config` ternary type mismatch

```
Error: Inconsistent conditional result types
  The 'true' value includes object attribute "provider_key_arn",
  which is absent in the 'false' value.
```

Terraform 1.7+ enforces matching types on both ternary branches. The
`true` branch returned `{resources, provider_key_arn}`, the `false`
branch returned `{}`. Swapped the false branch to `null`, which
disables encryption cleanly without forcing the shape duplication.

- `providers/aws/eks.tf` — `cluster_encryption_config` now returns
  `null` when `cluster_secrets_encryption_enabled = false`.

#### Fix 2 — IAM role `name_prefix` overflow

```
Error: expected length of name_prefix to be in the range (1 - 38),
got eks-estabilis-cortex-platform-prd-useast1-cluster-
```

The EKS module defaults `iam_role_use_name_prefix = true`, which caps
role names at 38 chars (AWS IAM `name_prefix` limit — the module
leaves room for the 26-char Terraform-generated suffix inside the
64-char total IAM role name budget). Our CAF-style cluster names
(`eks-{prefix}-platform-{env}-{region}`) already consume 30–41 chars
before the module appends `-cluster-`, so any `name_prefix > 5 chars`
would overflow.

Flipped to `iam_role_use_name_prefix = false` on both `module.eks`
(cascades to Fargate profile IAM roles) and `module.karpenter`
(covers the controller IRSA + node IAM roles). The resulting role
names fit in the 64-char `name` budget without truncating any CAF
tag segment.

- `providers/aws/eks.tf` — `iam_role_use_name_prefix = false` on
  the EKS module call.
- `providers/aws/karpenter.tf` — `iam_role_use_name_prefix = false`
  + `node_iam_role_use_name_prefix = false` on the Karpenter module.

### Backward compatibility

Since v0.14.0 was the first AWS release and no deployment reached
`terraform apply` before this fix (both bugs blocked plan), flipping
`iam_role_use_name_prefix` has **no migration impact** — there are
no existing IAM roles with `name_prefix` random suffixes to rename.

## [0.15.0] - 2026-04-23

### Added — configurable Karpenter discovery tag-key

New variable `karpenter_discovery_tag_key` in `providers/aws/` (default
`"karpenter.sh/discovery"` — unchanged behavior for existing deployments).

### Motivation

AWS allows a single value per tag-key per resource. When two
Karpenter-managed clusters share a VPC, both tagging subnets with the
community-convention key `karpenter.sh/discovery` would silently
overwrite each other — one cluster's Karpenter would stop finding
its subnets. Before this change, the upstream hardcoded that key in
five places (subnet create-mode tags, `aws_ec2_tag` for existing-mode,
EKS module top-level `tags`, `node_security_group_tags`, and Karpenter
module `tags`), so the only safe option was `autoscaler =
"cluster_autoscaler"` or `"none"` when sharing a VPC.

### How it works

Every place that previously hardcoded the key now uses
`var.karpenter_discovery_tag_key`. The default is the community
convention, so single-cluster VPCs keep their tag untouched. When two
clusters share a VPC, each sets a unique key:

- Cluster A (existing): `karpenter.sh/discovery = cluster-a`
- Cluster B (new):      `estabilis.io/discovery = cluster-b`

Both keys coexist on the same subnets. Each cluster's EC2NodeClass
(installed via ArgoCD in Phase 2) configures `subnetSelectorTerms` to
match its own key.

### Platform outputs

`platform-outputs.tf` now emits `global.karpenterDiscoveryTagKey` in
the `platform-infrastructure` ConfigMap so the Phase 2 Karpenter Helm
chart can render its EC2NodeClass with the correct subnet/SG selector.

### Backward compatibility

The default matches the hardcoded value from v0.14.0. No Azure
deployment is affected (the variable is AWS-only). Existing AWS
deployments that do not override the variable produce an
identical Terraform plan.

### Changes

- `providers/aws/variables.tf`: new `karpenter_discovery_tag_key`
  variable with validation (non-empty).
- `providers/aws/eks.tf`: `module.eks.tags`,
  `node_security_group_tags`, and
  `aws_ec2_tag.existing_private_karpenter_discovery` all use the var.
- `providers/aws/vpc.tf`: private subnet tag (create mode) uses the var.
- `providers/aws/karpenter.tf`: module tag uses the var.
- `providers/aws/platform-outputs.tf`: new `global.karpenterDiscoveryTagKey`
  ConfigMap entry.

## [0.14.0] - 2026-04-23

### Added — AWS provider (Phase 1 — landing zone)

Introduces `providers/aws/` alongside `providers/azure/` so the upstream
platform can target EKS on AWS with the same contract (variable shape,
`platform-outputs` ConfigMap + Secret, CAF tags, exposures model, hub
cluster bridge) as AKS on Azure. Phase 1 is landing zone only: no
`helm_release` in Terraform — Helm charts continue to be installed by
ArgoCD via `bootstrap/platform-root/`, matching the Azure pattern.

**Scope (28 files, ~4560 lines of Terraform):**

- `eks.tf` — cluster via `terraform-aws-modules/eks/aws` v20.37+, Fargate
  profiles for `kube-system` + `karpenter` (so `coredns`/`kube-proxy`/
  Karpenter come up before any EC2 node exists), managed addons (CoreDNS,
  kube-proxy, VPC CNI with prefix delegation, EBS CSI, Pod Identity
  Agent), Access Entries as the default auth mode (no `aws-auth`
  ConfigMap), envelope encryption for Kubernetes Secrets.
- `vpc.tf` + `nat-gateway.tf` + `security-groups.tf` +
  `vpc-endpoints.tf` + `vpc-flow-logs.tf` — `vpc_mode = "create" |
  "existing"`, multi-AZ subnets, per-AZ private route tables, single vs
  per-AZ NAT toggle, revoked default SG (CIS 5.3), operator-controlled
  additional SG with HTTP(S) rules gated on `ingress_controller =
  "traefik"`, S3 + DynamoDB gateway endpoints on by default, interface
  endpoints opt-in, optional Flow Logs to S3 in Parquet with post-2023
  policy shape (`aws:SourceAccount` + `aws:SourceArn`).
- `iam.tf` + `karpenter.tf` + `cluster-autoscaler.tf` +
  `alb-controller.tf` — one IRSA role per platform component (external-
  secrets, external-dns, cert-manager, velero, ALB controller, cluster-
  autoscaler, EBS CSI, workload-operator, Loki, Mimir, CNPG, OpenCost),
  each trusted via the cluster OIDC provider and scoped to a specific
  `namespace:serviceaccount`. Karpenter provisions only IAM controller
  role + node role + SQS interruption queue; chart + CRDs live in
  ArgoCD.
- `secrets-manager.tf` + `kms.tf` + `s3.tf` — 1:1 mirror of
  `keyvault.tf` with same secret names, path-scoped to
  `estabilis/{deployment_id}/*`. Three KMS CMKs (cluster-secrets,
  platform-secrets, s3-data) with distinct blast radii + per-service
  `kms:ViaService` conditions. Every bucket gets SSE-KMS, versioning,
  `BucketOwnerEnforced` (ACLs disabled), Block Public Access, TLS-only
  resource policy, lifecycle rules; `tfstate` bucket has
  `prevent_destroy` + optional Object Lock + optional cross-region
  replication.
- `route53.tf` + `acm.tf` + `ecr.tf` + `cost-export.tf` +
  `diagnostics.tf` — Route53 create-or-lookup, optional wildcard ACM
  with DNS-01 validation, ECR with scan-on-push + immutable tags +
  pull-through cache, CUR pinned to `us-east-1` via provider alias
  (CUR v1 constraint), CloudWatch log groups.
- `platform-outputs.tf` + `outputs.tf` — ConfigMap + Secret in the
  `argocd` namespace feeding `bootstrap/platform-root/`, plus the
  ArgoCD hub-cluster Secret with AWS-flavored bridge annotations
  (`account-id`, `region`, `hub-secrets-path-prefix`,
  `workload-operator-role-arn`) per ADR 0010.
- `terraform.tfvars.example` + `secrets.auto.tfvars.example` — document
  required vs optional variables with inline guidance on risky toggles
  (NAT SPOF, EBS account-wide scope, CUR single-per-account,
  `allow_public_api_endpoint`).

**Hardening:**
- Public EKS endpoint with empty `authorized_ip_ranges` is gated behind
  an explicit `allow_public_api_endpoint = true` opt-in (Terraform
  `check` block fails plan otherwise).
- Cross-file locals centralized in `locals.tf` so renames don't
  silently break sibling files.
- No `Deny` statements on Secrets Manager resource policies (would
  break rotation and confused-deputy-safe services).

**Out of scope** (deferred, by design): GitHub OIDC CI roles, RDS /
managed databases, Azure DevOps automation, workload cluster AWS.
Downstream template rewrite tracked in
`estabilis-platform-tools#173`.

### Added — pre-commit framework, tflint, gitleaks

Replaces the opt-in bash hooks in `.githooks/` (which required each
contributor to run `git config core.hooksPath .githooks` manually and
silently did nothing otherwise) with the portable `pre-commit`
framework.

- `.pre-commit-config.yaml` — 12 pinned hooks: `terraform_fmt`,
  `terraform_validate` (retry-once-with-cleanup), `terraform_tflint`
  with AWS + Azure plugins on the `recommended` ruleset,
  `detect-private-key`, `detect-aws-credentials` (new — catches
  access keys that `detect-private-key` misses now that AWS is in
  scope), `gitleaks` (deep scan), `check-merge-conflict`,
  `check-added-large-files`, `check-yaml` (Helm templates excluded),
  `end-of-file-fixer`, `trailing-whitespace`, `mixed-line-ending`,
  and `conventional-pre-commit` on the `commit-msg` stage.
- `.tflint.hcl` — plugin pins (`aws` 0.44.0, `azurerm` 0.30.0) and
  rule overrides.
- `.gitleaks.toml` — extend default rules + allowlist for docs, ADRs,
  UUID-shaped placeholders.
- `README.md` documents the one-time setup
  (`pip install pre-commit && pre-commit install`).
- `CLAUDE.md` instructs agents to run `pre-commit run --files ...`
  before considering edits complete.
- `.githooks/commit-msg` and `.githooks/pre-commit` removed — the
  framework owns the hook path now.

### Changed — trailing newlines across `core/components/**`

Mechanical fix surfaced by the new `end-of-file-fixer` hook: 24 files
(Grafana dashboards, Alloy RBAC, CNPG templates, platform-secrets
ExternalSecret templates, a handful of Helm values files) were missing
the terminating newline. No behavioral change — the rendered Helm
output is byte-identical (YAML `|` literal block scalar applies "clip"
chomping regardless of source) so no ArgoCD drift.

## [0.13.1] - 2026-04-22

### Fixed — AKS `admissionsenforcer` namespaceSelector drift on webhooks

AKS clusters have a managed field manager named `admissionsenforcer`
that injects `namespaceSelector.matchExpressions` on every
`ValidatingWebhookConfiguration` and `MutatingWebhookConfiguration` to
exclude managed-plane namespaces (`kubernetes.azure.com/managedby=aks`,
`control-plane=true`). Any webhook declaring `namespaceSelector: {}`
in git shows perpetual cosmetic OutOfSync — the field is owned by the
AKS admission controller, not by git.

Adds `resource.customizations.ignoreDifferences` entries in `argocd-cm`
scoped to `admissionregistration.k8s.io/{Validating,Mutating}WebhookConfiguration`.

- `core/components/argocd/values.yaml`: two new customizations ignoring
  `.webhooks[]?.namespaceSelector`.

Safe on non-AKS clusters: the jqPathExpressions match no webhooks when
`admissionsenforcer` doesn't exist, so the rule is a no-op elsewhere.

First observed on keda-admission; affects any webhook deployed on AKS.

## [0.13.0] - 2026-04-22

### Added — `configRepoRevision` and `clientGitopsRepoRevision` values

Part of ADR 0020 (GitOps-native continuous reconciliation). Lets
consumers track a branch (e.g. `main`, `release/prod`) instead of
pinning a specific tag for **own-content repos** (config overrides
+ client gitops). Tag pinning for **external dependencies** (upstream
Estabilis versions, container images, external helm charts) is
unchanged.

Changes:

- `bootstrap/platform-root/values.yaml`: add `configRepoRevision`
  and `clientGitopsRepoRevision`. Legacy `configRepoVersion` and
  `clientGitopsRepoVersion` are **retained for backcompat** — when
  both are set, the `*Revision` wins.
- `bootstrap/platform-root/templates/_helpers.tpl`: new helpers
  `configRepoRef`, `configRepoRefRequired`, `clientGitopsRef`,
  `clientGitopsRefRequired`. Existing helpers `overrideEnabled` /
  `overrideSource` / `overrideValueFile` / `ignoreMissingValueFiles`
  / `gitopsSource` refactored to consume the new resolvers.
- `bootstrap/platform-root/templates/custom-apps.yaml`: Application
  `targetRevision` uses `configRepoRef`.
- `bootstrap/platform-root/templates/client-kyverno-exceptions.yaml`:
  Application `targetRevision` uses `clientGitopsRef`.
- `bootstrap/platform-root/templates/hub-client-apps.yaml`:
  ApplicationSet `generators.git.revision` and generated Application
  `targetRevision` use `clientGitopsRefRequired` (fail-loud when
  URL is set but ref missing).

### Migration path

- **No action required**: continue setting the legacy `*Version`
  values via Terraform / tfvars. Chart renders identically to v0.12.4.
- **Adopt branch tracking**: set `*Revision` in overrides to a branch
  name (`main`, `release/prod`), leave `*Version` empty. Enables
  continuous reconciliation per ADR 0020.

### Compatibility

100% backward-compatible. Verified via `helm template` in legacy
and revision modes — external chart pins unchanged, only own-content
targetRevision transitions between tag and branch based on values
provided.

### Companion bump

`estabilis-platform-gitops` v0.31.0 introduces matching values at
the workload-bootstrap chart level. Use both together when adopting
continuous reconciliation.

## [0.12.4] - 2026-04-22

### Added — `valueFiles` block on `acr-image-updater-credentials` Application

The platform-root Application template for `acr-image-updater-credentials`
previously supported overrides only via `helm.parameters`. Per-cluster
overrides of component values (e.g. `secretStoreName` added by
estabilis-platform-gitops v0.30.0 for multi-KV tenant separation) could
not be set from the downstream config repo or client-gitops repo.

Adds a `valueFiles:` block mirroring the pattern used by
`cluster-secret-store`:

```yaml
valueFiles:
  - $values/components/acr-image-updater-credentials/values.yaml
  - $values/values/platform/acr-image-updater-credentials.yaml
  {{- include "platform-root.overrideValueFile" ... }}
  {{- include "platform-root.gitopsValueFile" ... }}
```

Also adds a second source declaring the platform-gitops `ref: values`
so the `$values/...` paths resolve (the Application previously had no
explicit values ref).

### Impact

- Any consumer of `acr-image-updater-credentials` can now override its
  values via a standard override file, e.g.
  `<config-repo>/overrides/acr-image-updater-credentials/values.yaml`.
- Enables the planned Transfero shared-infra cutover
  (`secretStoreName: shared-infra-secret-store`) without per-cluster
  upstream bumps.
- Backcompat: `ignoreMissingValueFiles: true` included via helper, so
  deployments without override files continue to work unchanged.

## [0.12.3] - 2026-04-22

### Added — `external_secrets_principal_id` output

New `providers/azure/outputs.tf` output exposing the principal ID
(object ID) of the `external-secrets` managed identity. The existing
`external_secrets_client_id` output only carries the client ID (used
by workload-identity federation), but cross-module RBAC wiring
(`azurerm_role_assignment`) requires the principal ID.

Motivation: enables downstream Terraform repos (e.g. shared-infra
wrappers that own their own Key Vault) to grant `Key Vault Secrets
User` to the same MI that ESO uses on the cluster, without
duplicating the identity. Before this output, a shared-infra repo
had to either (a) write its secrets to the platform-owned KV (the
only one the MI could read), creating cross-module ownership
coupling, or (b) provision its own duplicate MI.

Additive, backward-compatible. Existing consumers unaffected.

## [0.12.2] - 2026-04-21

### Fixed — `argocd-image-updater` chart pinned to track v0.x (annotation-based)

`bootstrap/platform-root/templates/argocd-image-updater.yaml` pinned the
upstream chart to `1.1.5` (app v1.1.1). The v1.0.0 release
(2025-11-11) is a rewrite to CRD-only — the controller no longer
reads `argocd-image-updater.argoproj.io/*` annotations on ArgoCD
Applications. Our write-back design (ADR 0016 D3) stores the
image-list / update-strategy / write-back-target as Application
annotations, so the v1.x controller silently ignored them — 0
`ImageUpdater` CRs on cluster, 0 write-backs performed.

Downgrade to chart `0.14.0` (app v0.17.0) — the latest chart on the
annotation-based `master-annotation-based` upstream branch. Restores
the contract documented in ADR 0016. Do NOT bump past `0.14.x` without
migrating every consumer Application to the `ImageUpdater` CRD first.

See `docs/adr/0019-argocd-image-updater-v0x-correction.md` (estabilis-
platform-tools) for the full postmortem.

Post-upgrade cleanup on the cluster: the v1.x chart's Deployment
(`argocd-image-updater-controller`) has a different name than the
v0.x chart's (`argocd-image-updater`) and will be orphaned by the
Helm upgrade. Delete it after sync:

```
kubectl -n argocd delete deploy argocd-image-updater-controller
```

## [0.12.1] - 2026-04-21

### Fixed — `terraform validate` rejects `cost-export.tf`

`recurrence_period_end_date` used `formatdate("YYYY", plantimestamp()) + 10`.
During `terraform validate` (ahead of any plan), `plantimestamp()`
evaluates to `0001-01-01T00:00:00Z`; `formatdate("YYYY", ...)` returns
the string `"1"`, which arithmetic-added to `10` yields `11`, and the
final string becomes `"11-01-01T00:00:00Z"` — year `11`, rejected by
the `azurerm` provider as invalid RFC3339.

Replace with `formatdate("YYYY-MM-DD", timeadd(plantimestamp(),
"87600h"))` which always produces a zero-padded 4-digit year and
stays well-formed under both `validate` (zero-epoch → year 0011)
and real plan (current-time + 10y).

Unblocks PR validation pipelines on every downstream repo that
references this module (transfero-platform-azure-eastus2-hml, etc.).

## [0.12.0] - 2026-04-19

### Added

- **`clientHubAppExtraClusterResources` extension point on the
  `platform-client-infra` AppProject** (ADR 0017). The project's
  `clusterResourceWhitelist` now appends a client-declared list of
  additional `(group, kind)` pairs sourced from wrapper overrides.
  This lets the client authorize cluster-scoped resource kinds their
  own hub-apps need — for example KEDA's `APIService`
  (`apiregistration.k8s.io`) for the external-metrics adapter, or an
  Istio/Linkerd install's mesh-specific kinds — without opening a
  platform PR for every case.

  Default is an empty list. Upstream defines the governance classes
  permitted (Namespace, ClusterRole, ClusterRoleBinding, CRD,
  admissionregistration.k8s.io/*, networking.k8s.io/*,
  kyverno.io/PolicyException) and this value extends them. Matches
  the spirit of ADR 0017's "upstream proposes, client disposes".

  Files:

  - `bootstrap/platform-root/values.yaml` — adds
    `clientHubAppExtraClusterResources: []` default next to
    `clientHubAppNamespaces`.
  - `bootstrap/platform-root/templates/argocd-project.yaml` — range
    over that list appended to the `platform-client-infra`
    `clusterResourceWhitelist`.

## [0.11.0] - 2026-04-18

### Added

- **ADR 0017 — Hub-targeted client applications.** New structural tier
  for client-authored infrastructure Applications that must run on the
  platform hub (not on workload clusters). Two new pieces:

  - `bootstrap/platform-root/templates/hub-client-apps.yaml` — new
    ApplicationSet that discovers `platforms/{deploymentId}/hub-apps/*`
    in the client gitops repo and creates one Application per
    subdirectory on the hub. The ApplicationSet renders the Application
    spec directly from the path plus wrapper parameters — clients do
    NOT write an inner `application.yaml`. This eliminates the
    self-referential `targetRevision` drift that plagues the workload
    `apps/` path (issue #100).

  - `bootstrap/platform-root/templates/argocd-project.yaml` — new
    `platform-client-infra` AppProject authorizing client hub-apps
    against an **explicit** namespace allowlist (no wildcards). The
    allowlist is driven by the new `clientHubAppNamespaces` value,
    operator-managed in the client's wrapper
    `overrides/platform-root/values.yaml`.

  `ClusterRole` / `ClusterRoleBinding` / `CustomResourceDefinition` /
  `ValidatingWebhookConfiguration` / `MutatingWebhookConfiguration`
  are **intentionally** allowed in the project's resource whitelist,
  because legitimate hub-apps (admission webhooks, operators with
  cluster-wide reach, CRD providers) need them. Risk is audited by the
  upstream Kyverno catalog, not blocked by the project — per ADR 0017
  "upstream proposes, client disposes".

### Added (values)

- `clientHubAppNamespaces` (defaults to `[]`) in
  `bootstrap/platform-root/values.yaml`. Empty list = no hub-apps
  authorized (safe default).

### Documentation

- ADR 0017 (Draft) in estabilis-platform-tools/docs/adr/.
- Tracking issue Estabilis/estabilis-platform-tools#118.

### Notes

- Version metadata jumps from 0.8.2 → 0.11.0. Tags v0.9.0, v0.9.1,
  v0.9.2, v0.9.3, v0.10.0, v0.10.1, v0.10.2 were cut without
  CHANGELOG entries. Fix-forward: 0.11.0 is the first release with
  a documented changelog entry since 0.8.2. Backfill tracked
  separately if needed.

## [0.8.2] - 2026-04-16

### Fixed
- `core/components/trivy-operator/values.yaml`: trivy CLI scan job
  containers were OOMing on real-world image scans. The CLI does
  layer extraction client-side even in ClientServer mode, and the
  previous limit of 512 MiB was insufficient (`anon-rss ~520 MiB`
  observed on Transfero HML 2026-04-16). Bumped
  `trivy.resources.limits.memory` from `512Mi` to `1Gi` and
  `requests.memory` from `128Mi` to `256Mi` to keep the Burstable
  QoS ratio reasonable.
- `operator.scanJobBackoffLimit` reduced from `10` to `3`. With the
  previous setting an OOM produced 10 noisy events for the same
  failure (a scan that doesn't fit at attempt 4 won't fit at attempt
  10 either — the image is the problem, not transient pressure).

## [0.8.1] - 2026-04-16

### Changed
- Documentation polish for ADR 0015 — dropped the `(WIP)` markers in
  `providers/azure/acr-azdo.tf` and `providers/azure/main.tf`. The feature
  was validated end-to-end on Estabilis HML against
  `dev.azure.com/estabilis/Transfero` (5 resources created + destroyed
  clean, no PAT used) and is considered shipped.

## [0.8.0] - 2026-04-16

### Added
- **ADR 0015 — Terraform-managed Azure DevOps Service Connection for ACR push.**
  Opt-in via `azdo_push_automation_enabled = true`. When enabled,
  Terraform creates end-to-end (no manual portal clicks):
  1. AAD Application + Service Principal (no client secret)
  2. AcrPush role assignment scoped to the platform ACR
  3. Azure DevOps Service Connection in WorkloadIdentityFederation mode
  4. Federated Identity Credential linking the ADO SC ↔ AAD SP
  Pipelines reference the SC by name (`${name_prefix}-platform-${env}-${region}-acr-push`).
- New file: `providers/azure/acr-azdo.tf` (5 gated resources).
- New variables (all default off — feature is opt-in):
  - `azdo_push_automation_enabled` (bool, default `false`)
  - `azdo_organization_url` (string, default `""`, required when enabled)
  - `azdo_project` (string, default `""`, required when enabled)
- New provider `microsoft/azuredevops ~> 1.5` declared in `versions.tf`
  and `main.tf`. Authenticates via the active `az` CLI session
  (`AZURE_CONFIG_DIR`) — no PAT required. Provider block is always
  declared but is a no-op when the feature is off (resources gated by
  `count = enabled`).
- New outputs: `azdo_acr_push_service_connection_name`,
  `azdo_acr_push_sp_app_id`.

### Notes
- If both `acr_push_principal_ids` and `azdo_push_automation_enabled = true`
  are populated, two AcrPush role assignments are created against the same
  registry (one for the legacy SP list, one for the Terraform-managed SP).
  Functional but redundant — drop the manual list once the automation is in
  place.
- Validated empirically on 2026-04-16 against
  `dev.azure.com/estabilis/Transfero`: 5 resources created and destroyed
  cleanly without any auth secret.

## [0.7.1] - 2026-04-16

### Fixed
- Removed `--cloudflare-proxied=false` from
  `core/components/external-dns/values-cloudflare.yaml`. external-dns
  v0.20.0 crashes with `flag parsing error: unexpected false` when that
  flag carries an explicit `=false` value. Default is already unproxied,
  so the flag is unnecessary. To re-enable proxy mode in the future,
  set `extraArgs: [--cloudflare-proxied]` (bare form).

## [0.7.0] - 2026-04-16

### Added
- `dns_provider` variable (azure | cloudflare) selecting which DNS backend external-dns and cert-manager use. Defaults to azure to preserve existing behavior.
- `cloudflare_zone_id` + `cloudflare_api_token` (sensitive) variables — required when dns_provider = cloudflare, enforced by conditional validation blocks.
- `core/components/external-dns/values-cloudflare.yaml` — Cloudflare provider config with API token env-from Secret and DNS-only mode (no proxy).
- `core/components/external-dns-config/templates/cloudflare-config.yaml` — renders the `external-dns-cloudflare-config` Secret when dnsProvider=cloudflare.
- Auto-derivation of `host` in `*_exposures` from host_pattern + environment + domain when the field is empty. Explicit hosts still win. App names: grafana, argocd, loki, hubble.

### Changed
- `host` field in `grafana_exposures`, `loki_exposures`, `argocd_exposures`, `hubble_ui_exposures` is now optional (was required). Empty hosts resolve via the new derivation locals — backward compatible with existing tfvars.
- `azurerm_dns_zone.platform`, `azurerm_user_assigned_identity.external_dns`, `azurerm_federated_identity_credential.external_dns`, `azurerm_role_assignment.external_dns_dns_contributor`, and the cert-manager DNS role assignment now carry `count = var.dns_provider == "azure" ? 1 : 0`. Switching to cloudflare destroys these on next apply.
- `platform-root` external-dns and cert-manager templates now branch on `global.dnsProvider` (falling back to `global.provider` for backward compatibility) and pass the Cloudflare token / zone id when cloudflare is selected.
- `cluster-issuer-azure.yaml` in cert-manager-config now gates on dnsProvider (was provider).

### Migration
- Downstream clients that previously set `host = "<explicit>"` in exposures keep working unchanged. New deployments may omit `host` to take the auto-derived value.
- To switch an existing cluster from Azure DNS to Cloudflare: set `dns_provider = "cloudflare"` + `cloudflare_zone_id`, add `cloudflare_api_token` to secrets.auto.tfvars, delegate the domain's NS at the registrar to Cloudflare, then run terraform apply and `estabilis promote <deployment>` to refresh ArgoCD.

## [0.1.0-alpha] - 2026-03-11

### Added
- Initial platform structure with upstream/downstream model
- Azure provider: AKS, VNet, Storage, Key Vault, Workload Identity
- ArgoCD seed via Terraform (single helm_release)
- App of Apps bootstrap with platform-root Helm chart
- Core components: Kyverno, Grafana Stack (Loki, Mimir, Alloy, Grafana), External DNS, Cert-Manager, External Secrets
- Kyverno policies: require-labels, require-limits, no-latest-tag, no-privilege-escalation (Audit mode)
- Justfile as operational interface (bootstrap, verify, destroy)
- Example downstream configuration
