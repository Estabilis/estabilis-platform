# Changelog

## [0.29.1] - 2026-04-26

### Fixed — VPC CNI cold-start race during node bootstrap

Observed on cortex during the v0.29.0 rolling MNG replacement: new
`m6a.xlarge` nodes registered as `Ready` before the `aws-node` DaemonSet
finished allocating its first `/28` prefix on the secondary ENI. The
scheduler placed pods on the new nodes immediately (especially the
AZ-bound stateful workloads like CNPG and Vault, pulled by PVC
affinity). For ~30 seconds, those pods hit:

```
Failed to create pod sandbox: rpc error: code = Unknown desc =
failed to setup network for sandbox: plugin type="aws-cni" failed (add):
add cmd: failed to assign an IP address to container
```

kubelet retried every 5-10s and pods recovered with zero restarts once
the CNI finished warming up. **Workloads were never impacted** — but
the `FailedCreatePodSandBox` event noise on every node bootstrap is
avoidable, and Karpenter spot churn would replay the same race on
every interruption.

#### Fix

`vpc-cni` addon `configuration_values` now sets:

```hcl
env = {
  ENABLE_PREFIX_DELEGATION = "true"   # unchanged
  WARM_PREFIX_TARGET       = "2"      # NEW (default 1)
  MINIMUM_IP_TARGET        = "10"     # NEW (default unset)
}
```

`WARM_PREFIX_TARGET=2` keeps two `/28` prefixes (32 IPs) pre-allocated
on each node — bootstrap window for IP allocation drops to <5s.
`MINIMUM_IP_TARGET=10` guarantees at least 10 free IPs at all times,
defending against bursty pod creation (e.g., DaemonSet rollouts).

Cost: 16-32 IPs reserved per node. Subnets in the platform default
template are `/23` (512 IPs each), so the impact is negligible.

#### Migration

No tfvars changes needed. The vpc-cni addon is updated in-place by EKS
on the next `terraform apply` — no node replacement, no workload
disruption.

## [0.29.0] - 2026-04-26

### Added — Replacement-safety rails for force_new resources

Audit triggered by a real `409 ResourceInUseException` hit on cortex when
bumping `mng_instance_types` + `mng_capacity_type`. Root cause: the
`terraform-aws-modules/eks` submodule hardcodes
`lifecycle { create_before_destroy = true }` on `aws_eks_node_group`, and
the explicit NG name (forced by IAM 38-char prefix budget) collides with
itself on any force_new field.

Audit found 3 other recurrence-prone spots: vault backup S3 bucket
(global namespace + 60-90 day retention), cluster encryption flip
(one-way at AWS API), Karpenter IAM roles (collision risk for short
cluster names in shared accounts).

This release ships **flexibility-first** rails: defaults preserve current
behavior, opt-ins enable safer modes, plan-time preconditions catch
foot-guns before apply.

#### New variables

- **`mng_replacement_strategy`** — `"static"` (default) | `"rolling"`.
  - `static`: NG name `<cluster>-default` (backward-compat). Force_new
    changes (instance_types/capacity_type/ami_type/disk_size) require
    `terraform destroy -target` before `terraform apply`.
  - `rolling`: NG name `<cluster>-default-gen<mng_generation>`.
    Force_new changes are made by bumping `mng_generation` in the same
    apply — `create_before_destroy` provisions the new NG before
    draining the old. Zero-downtime when other compute (Karpenter,
    additional NGs) is present to absorb workloads.

- **`mng_generation`** — integer >= 1 (default `1`). Suffix bumped to
  trigger zero-downtime rollover when `mng_replacement_strategy='rolling'`.
  Ignored on `static`.

- **`vault_backup_bucket_naming`** — `"static"` (default) | `"random_suffix"`.
  - `static`: bucket `<cluster>-vault-backup` (backward-compat).
  - `random_suffix`: bucket `<cluster>-vault-<suffix>`, consistent with
    the other 6 platform buckets, avoiding S3 global-namespace 60-90 day
    retention conflicts on teardown+recreate.

#### New plan-time preconditions

- `terraform_data.mng_size_guard` — fails plan when
  `mng_min_size > mng_desired_size` or `mng_desired_size > mng_max_size`.
  Caught at plan, not apply.
- `terraform_data.karpenter_naming_guard` — fails plan when
  `length(cluster_name) < 8` and Karpenter is enabled, preventing IAM
  role name collisions across deployments in the same AWS account.

#### New variable validations

- `mng_min_size >= 0`, `mng_desired_size >= 0`, `mng_max_size >= 1`.

#### Documentation hardening

- `cluster_secrets_encryption_enabled` description now flags the
  one-way nature of EKS encryption_config: flipping `true → false` on a
  running cluster forces full cluster destroy/recreate at the AWS API
  level. Treat as immutable once enabled.
- All MNG variables that force NG recreation
  (`mng_instance_types`, `mng_capacity_type`, `mng_disk_size_gb`,
  `mng_ami_type`) now have `REPLACEMENT NOTE` blocks pointing at
  `mng_replacement_strategy`.

#### Migration

All changes are backward-compatible. Existing deployments behave
identically with no tfvars changes:

- MNG keeps name `<cluster>-default` (because `mng_replacement_strategy`
  defaults to `"static"`).
- Vault backup bucket keeps name `<cluster>-vault-backup` (because
  `vault_backup_bucket_naming` defaults to `"static"`).
- Encryption variable description is doc-only.

To opt into safer behavior on an existing cluster:

- Switching `mng_replacement_strategy` `static → rolling` IS a force_new
  event on the NG `name` (it gains `-gen1` suffix). The module's
  `create_before_destroy` makes this safe (zero-downtime), but it IS a
  real replacement window. Plan accordingly.
- Switching `vault_backup_bucket_naming` `static → random_suffix` forces
  destroy+create of the bucket. Snapshot history is lost. Only do this
  on clusters where vault backup history is acceptable to lose, or
  manually copy snapshots first.

## [0.28.3] - 2026-04-26

### Changed — Move `vault-ingress` chart to `estabilis-platform-gitops` (ADR 0002 Phase 2)

ADR 0002 (gitops chart consolidation) target state: all platform
component charts live in `estabilis-platform-gitops`; this repo carries
only Terraform IaC + the bootstrap Application templates that reference
those charts.

The `vault-ingress` chart was created in `core/components/vault-ingress/`
in v0.28.2 — wrong location per the ADR. This release moves it to
`estabilis-platform-gitops/components/vault-ingress/` (released as
gitops v0.38.2, paired) before any client takes a hard dependency on
the legacy path.

#### Changes

- **REMOVED**: `core/components/vault-ingress/` (Chart.yaml, values.yaml,
  templates/_helpers.tpl, templates/middleware.yaml). Migrated
  byte-identical to `estabilis-platform-gitops v0.38.2`.
- **CHANGED**: `bootstrap/platform-root/templates/vault-ingress.yaml`
  now sources the chart from the gitops repo:
  - `repoURL: .Values.platformGitopsRepoUrl` (was `platformRepoUrl`)
  - `targetRevision: .Values.platformGitopsVersion` (was `platformVersion`)
  - `path: components/vault-ingress` (was `core/components/vault-ingress`)
  - `valueFiles[0]: $values/components/vault-ingress/values.yaml`
    (was `$values/core/components/vault-ingress/values.yaml`)

ArgoCD treats a `repoURL` change on a multi-source App as a transparent
diff — same chart content, same rendered manifests, no pod restart, no
Ingress recreation.

### Fixed — Permanent OutOfSync on Vault `StatefulSet` (volumeClaimTemplates drift)

ArgoCD reported persistent drift on `apps/StatefulSet/vault/vault` even
on a fresh deploy where Vault was Healthy and Running. Root cause:
known ArgoCD diff quirk with StatefulSet `volumeClaimTemplates`.

Kubernetes API server **normalizes** templates on creation by adding
`apiVersion: v1` and `kind: PersistentVolumeClaim` (the default for
embedded resources without explicit version/kind). The Vault helm
chart renders the templates without these (they're inherited from
the PodSpec context). ArgoCD's diff then sees the api-server-added
fields as drift — every reconcile reports OutOfSync.

#### Fix

`bootstrap/platform-root/templates/vault.yaml` gains an
`ignoreDifferences` block scoped to the StatefulSet:

```yaml
ignoreDifferences:
  - group: apps
    kind: StatefulSet
    name: vault
    namespace: vault
    jqPathExpressions:
      - .spec.volumeClaimTemplates[]?.apiVersion
      - .spec.volumeClaimTemplates[]?.kind
```

Cosmetic-only — does not affect PVC binding, Raft data persistence,
or auto-unseal. Eliminates a permanent OutOfSync that operators
otherwise had to chase down on every cluster.

### Migration

For all v0.28.0+ clusters with Vault enabled:

1. Bump `ref` and `platform_revision` to `v0.28.3`.
2. `terraform init -upgrade && terraform apply` — no infrastructure
   changes (template-only).
3. `estabilis promote <client> -d <deployment> --force-refresh` —
   re-renders the Vault Application with the new `ignoreDifferences`.
4. The Vault Application transitions from `OutOfSync (cosmetic)` to
   `Synced` without any pod restart or data movement.

For deployments without Vault (`vault_enabled = false`): no-op.

## [0.28.2] - 2026-04-25

### Added — `vault-ingress` chart (consumes `vault_exposures` dynamically)

Closes the gap from v0.28.0/v0.28.1 where `vault_exposures` flowed into
the Secret but had no chart consuming it. Clients had to hardcode an
Ingress in their `overrides/vault/values.yaml` referencing literal
ACM ARNs, hostnames, and ALB groups. v0.28.2 ships a proper
`vault-ingress` chart following the existing `grafana-ingress` /
`argocd-ingress` pattern.

#### `core/components/vault-ingress/` (NEW)

Mirror of `grafana-ingress`, vault-specific:
- Backend: `vault-ui` Service, port 8200 (NOT the chart's own ingress)
- Default healthcheck path: `/v1/sys/health?standbyok=true&sealedcode=200&uninitcode=200`
  — keeps the LB routing traffic to standby pods (default is 429), to
  sealed pods (so the operator can reach the API to unseal), and to
  uninitialized pods (so `vault operator init` works via the LB).
- Branches on `$exp.ingress_class`:
  - `alb` → AWS Load Balancer Controller annotations (cert ARN, group,
    scheme, ssl-policy, healthcheck path) — all consumed from the
    profile + `global.acmCertificateArn` from the platform Secret.
  - `traefik` / `traefik-internal` → Traefik IngressRoute with
    Middlewares for `ipAllowList`.
- Vault has its own UI auth — `basic_auth = true` is unsupported and
  the chart fails loud regardless of ingress class (would double-auth).

#### `bootstrap/platform-root/templates/vault-ingress.yaml` (NEW)

ArgoCD Application gated on (`provider in (aws | azure)`) AND
`components.vault != false` AND at least one enabled exposure profile
in `global.vaultExposures`. Forwards `exposuresJson` +
`global.acmCertificateArn` + `global.dnsProvider` to the chart via
`helm.parameters`. Sync-wave 9 (after the Vault chart at wave 5).

#### `providers/{aws,azure}/platform-outputs.tf` — exposures move

`vault.exposuresJson` (in `platform-infrastructure-sensitive` Secret)
→ `global.vaultExposures` (in `platform-infrastructure` ConfigMap),
matching the ADR 0014 convention used by every other `*Exposures`
field. Exposures are non-sensitive (just hostnames + CIDR allowlists);
the Secret keeps only the identity and KMS/KV key ID.

### Added — Three tunable variables

`providers/aws/variables.tf`:
- `vault_kms_deletion_window_days` (default `7`, range 7-30) — AWS
  KMS deletion window for the dedicated unseal key. Lower = faster
  destroy on toggle off; higher = bigger window to recover an
  accidentally-disabled deployment.

`providers/azure/variables.tf`:
- `vault_kv_soft_delete_days` (default `7`, range 7-90) — Soft-delete
  retention on the dedicated Vault Key Vault. NO purge_protection
  (toggle false must remove cleanly).
- `vault_storage_replication_type` (default `"LRS"`, validated against
  LRS/ZRS/GRS/RAGRS/GZRS/RAGZRS) — Replication type for the Vault
  snapshot Storage Account. LRS=cheapest single-region; clients with
  HA backup needs override to ZRS or GRS.

### Migration

For `vault_enabled = true` deployments running v0.28.0 or v0.28.1:

1. Bump `ref` and `platform_revision` to `v0.28.2`.
2. `terraform init -upgrade && terraform apply` — `platform-infrastructure`
   ConfigMap gains `global.vaultExposures`; `platform-infrastructure-sensitive`
   loses `vault.exposuresJson` (was non-sensitive, ADR 0014 alignment).
3. `estabilis promote <client> -d <deployment> --force-refresh` — the
   parameter forwarding picks up the new ConfigMap key; vault-ingress
   Application renders.
4. **Drop hardcoded ingress override** in client repo's
   `overrides/vault/values.yaml` (only the genuine cluster-specific
   bits like `dataStorage.storageClass` should remain).

For deployments NOT yet using Vault: no-op (`vault_enabled = false`
default).

## [0.28.1] - 2026-04-25

### Fixed — `vault.yaml` template nil-pointer on first render

The Vault Application template (introduced in v0.28.0) referenced
`.Values.identity.vault.roleArn`, `.Values.vault.kmsKeyId`, etc.
without these keys having defaults in the chart's `values.yaml`. On
the first render after a v0.28.0 bump (before terraform helm.parameters
have flowed through to the Application's spec.parameters), the chart
crashed with:

```
template: platform-root/templates/vault.yaml:57:30: executing
"platform-root/templates/vault.yaml" at <.Values.identity.vault.roleArn>:
nil pointer evaluating interface {}.roleArn
```

#### Fix

Added empty-string defaults in `bootstrap/platform-root/values.yaml`:
- `identity.vault.{clientId,roleArn}`
- `vault.{kmsKeyId,kmsRegion,backupBucketName,keyVaultName,unsealKeyName,backupStorageAccount,backupContainer}`

Pattern matches the existing `identity.externalSecrets.*` and similar
defaults — the chart can render with empty values, and terraform's
helm.parameters override them at sync time.

No platform code changes; values-only patch.

## [0.28.0] - 2026-04-25

### Added — HashiCorp Vault as a multi-provider opt-in component (foundation)

First pass of HashiCorp Vault as a platform component on both AWS and
Azure. Foundation scope only: chart deployment + cloud auto-unseal
infrastructure. Bootstrap (auth methods, policies, KV mount,
ClusterSecretStore wiring) is intentionally deferred to client-specific
overlays / operational follow-ups.

#### Toggle semantics

`vault_enabled` Terraform variable defaults to `false`. When toggled
to `true`, the AWS / Azure side provisions infrastructure; when toggled
back to `false`, **all** resources are removed cleanly — no orphans,
no `prevent_destroy` blockers, no purge protection on the dedicated
Azure KV (would block teardown). Verified via `terraform plan` with
`vault_enabled=false` after a prior enable: `0 to add, 0 to change,
N to destroy`.

#### AWS — `providers/aws/vault.tf`

- `aws_kms_key.vault[count]` + alias — dedicated unseal key (NOT the
  cluster envelope encryption key; scope isolation). 7-day deletion
  window keeps teardown clean.
- `aws_s3_bucket.vault_backup[count]` — versioned, KMS-encrypted via
  `s3_data`, lifecycle expires snapshots after `vault_backup_retention_days`,
  `force_destroy = true` so `terraform destroy` works even with content.
  Snapshot CronJob deferred to a follow-up; bucket provisioned now so
  future enablement needs no IAM change.
- `module.vault_irsa[count]` + `aws_iam_role_policy.vault[count]` —
  least-privilege IRSA: `kms:Encrypt/Decrypt/DescribeKey` on the unseal
  key, `s3:PutObject/GetObject` on the bucket, `s3:ListBucket` on the
  bucket.

#### Azure — `providers/azure/vault.tf`

- `azurerm_key_vault.vault_unseal[count]` — dedicated KV (`kv-vault-{cluster}-{suffix}`),
  separate from the platform KV. **`purge_protection_enabled = false`**
  so toggle false truly removes the resource.
- `azurerm_key_vault_key.vault_unseal[count]` — RSA-2048 unseal key.
- `azurerm_storage_account.vault_backup[count]` + container
  `raft-snapshots` — backup destination (versioned, soft-delete
  retention configurable). CronJob deferred; container provisioned now.
- `azurerm_user_assigned_identity.vault[count]` + federated credential
  — Workload Identity for the `vault:vault` ServiceAccount.
- Role assignments: `Key Vault Crypto User` on the dedicated KV +
  `Storage Blob Data Contributor` on the storage account.

#### Bootstrap template — `bootstrap/platform-root/templates/vault.yaml`

ArgoCD Application gated on `provider in (aws | azure)` AND
`components.vault != false`. Multi-source (chart + values + override
+ gitops). Helm parameters inject:

- AWS: `server.serviceAccount.annotations.eks.amazonaws.com/role-arn`,
  full Raft+seal HCL config (with KMS region + key id substituted).
- Azure: `server.serviceAccount.annotations.azure.workload.identity/client-id`,
  `server.extraLabels.azure.workload.identity/use=true`,
  full Raft+seal HCL config (with tenant_id, vault_name, key_name).

#### AppProject — `bootstrap/platform-root/templates/argocd-project.yaml`

- Add `vault` namespace destination to the `platform` project.
- Add `https://helm.releases.hashicorp.com` to `sourceRepos`.

#### `vault` is multi-provider — NOT in `awsOnly` filter

`platform-root.componentsForwarding` (helper introduced in v0.27.0)
filters AWS-only entries when `provider != aws`. Vault is intentionally
NOT in that list — it's gated separately on
`provider in (aws | azure)` in the vault.yaml template. The component
toggle propagates to both providers.

### Bumped — `platformGitopsVersion: v0.37.2 → v0.38.0`

`estabilis-platform-gitops v0.38.0` ships the chart values overlays
(`values/platform/vault.yaml`, `vault-aws.yaml`, `vault-azure.yaml`)
and the triple-belt coverage (network-policies, resource-quotas,
kyverno-policies excluded list).

### Migration

For all v0.27.x clusters where Vault should NOT be enabled:
- No-op. `vault_enabled` defaults to `false`; existing tfvars carry
  forward unchanged.

For clusters opting into Vault:
- Set `vault_enabled = true` in `terraform.tfvars`.
- Set `vault_exposures` (e.g. `{ internal = { enabled = true,
  ingress_class = "alb" } }`).
- `terraform init -upgrade && terraform apply` — provisions cloud
  infrastructure (KMS or KV, S3 or Storage, IRSA or WI).
- Add `components.vault: true` to `overrides/platform-root/values.yaml`.
- `estabilis promote <client> -d <deployment> --force-refresh` — renders
  the Vault Application; the chart deploys 3-replica Raft HA.
- **Manual step**: `kubectl exec -n vault vault-0 -- vault operator init`
  produces unseal keys + root token. Save them (out-of-band — these are
  NOT in scope for the foundation; downstream / runbook covers
  authoritative storage). Vault stays `Sealed: false` thereafter via
  cloud auto-unseal across pod restarts.

## [0.27.2] - 2026-04-25

### Bumped — `platformGitopsVersion: v0.37.1 → v0.37.2`

Patch-only release. `estabilis-platform-gitops v0.37.2` adds
`metrics-server` namespace to the three policy/quota coverage layers
(same pattern as ALB/karpenter in v0.37.0). The `awsOnly` list in
`platform-root.componentsForwarding` (introduced v0.27.0) already
covers `metrics-server`, so no platform code change is needed beyond
the upstream default bump.

No platform code changes.

## [0.27.1] - 2026-04-25

### Bumped — `platformGitopsVersion: v0.37.0 → v0.37.1`

Patch-only release. `estabilis-platform-gitops v0.37.1` ships a
karpenter ResourceQuota fix (the v0.37.0 quota was undersized for
the chart's actual defaults — 2 replicas × 500m/1Gi each exceeded
the 500m/1Gi quota). This release updates the upstream default so
new deployments and existing clusters consuming the chart default
pick up the corrected quota automatically.

No platform code changes.

## [0.27.0] - 2026-04-25

### Fixed — `network-policies` and `resource-quotas` forward AWS-only components on Azure

`bootstrap/platform-root/templates/network-policies.yaml` and
`resource-quotas.yaml` (introduced in v0.26.0 to fix phantom drift on
disabled components) forwarded **all** entries of `.Values.components`
to the gitops-side child charts via `valuesObject.components`,
regardless of the active provider.

This is correct for components that are always potentially active on
either provider (`opencost`, `traefik`, etc.) but creates a latent
drift on Azure for AWS-only components — `aws-load-balancer-controller`,
`karpenter`, `karpenter-resources`, `metrics-server`. The Application
templates that install these components are gated on
`global.provider == "aws"`, so the namespaces never come into
existence on Azure. But the `components.{ns}: true` defaults in
`bootstrap/platform-root/values.yaml` still propagated to the
`network-policies` and `resource-quotas` charts, which would render
NetworkPolicies and ResourceQuotas for non-existent namespaces →
permanent OutOfSync.

Today no Azure cluster is using these charts to cover ALB / karpenter
namespaces (the gitops `components/network-policies/values.yaml`
historically didn't list them), so the bug was inert. Pairs with
`estabilis-platform-gitops v0.37.0` which DOES add coverage —
without this filter, that gitops bump would generate Azure regression.

#### Fix

New helper `platform-root.componentsForwarding` in
`bootstrap/platform-root/templates/_helpers.tpl` filters the AWS-only
set out of the forwarded map when `global.provider != "aws"`. Used
identically by both `network-policies.yaml` and `resource-quotas.yaml`
templates (replacing the previous inline `range $k, $v` loop).

The AWS-only set:
```
- aws-load-balancer-controller
- karpenter
- karpenter-resources
- metrics-server
```
must stay synchronized with the `global.provider == "aws"` gating
clauses in the corresponding `bootstrap/platform-root/templates/*.yaml`
Application templates.

### Bumped — `platformGitopsVersion: v0.33.0 → v0.37.0`

`estabilis-platform-gitops v0.37.0` lands the corresponding ALB +
karpenter coverage in `components/network-policies` and
`components/resource-quotas`. The two releases pair: v0.27.0
introduces the provider filter, v0.37.0 introduces the new
allow-* policies and quotas. Either alone is correct (no regression);
both together close the gap fully.

### Migration

For all v0.26.x clusters:
1. Bump `ref=` and `platform_revision` to `v0.27.0` in client
   `providers/<cloud>/main.tf` + `terraform.tfvars`.
2. `terraform init -upgrade && terraform apply`.
3. `estabilis promote <client> -d <deployment> --force-refresh`
   (re-renders the `network-policies` and `resource-quotas`
   Applications with the filtered components map).

Behaviour unchanged on existing AWS clusters; no-op on existing Azure
clusters until the gitops chart starts declaring ALB / karpenter
coverage (v0.37.0).

## [0.26.2] - 2026-04-25

### Fixed — Persistent OutOfSync exposed by `platform-root` recovery on AWS

Two upstream gaps surfaced after the `application-controller` was
restored on a v0.26.1 AWS cluster (cortex-eks postmortem). Both were
present since v0.26.0 but were masked by a stuck controller cache that
prevented fresh diffs against the v0.26.1 manifest set.

#### `aws-load-balancer-controller` — `IngressClassParams alb` rejected by AppProject

`bootstrap/platform-root/templates/aws-load-balancer-controller.yaml`
ships an `ignoreDifferences` entry for the `IngressClassParams alb`
spec (added in v0.26.0), but the platform AppProject's
`clusterResourceWhitelist` never permitted the `elbv2.k8s.aws` API
group. Sync failed with:

```
resource elbv2.k8s.aws:IngressClassParams is not permitted in project platform
```

The fix: add `elbv2.k8s.aws/*` to the platform project's
`clusterResourceWhitelist` in
`bootstrap/platform-root/templates/argocd-project.yaml`. Pattern
matches the existing `karpenter.sh/*` and `karpenter.k8s.aws/*`
entries — wildcard because the AWS Load Balancer Controller may
introduce additional kinds (e.g. `TargetGroupBinding`) in future
chart versions.

#### `external-secrets` — caBundle drift on `ValidatingWebhookConfiguration`

`externalsecret-validate` and `secretstore-validate` are populated
with a `caBundle` after install (chart-rendered manifest leaves it
empty). Same pattern that `argocd`, `aws-load-balancer-controller`,
and `cert-manager` already address with `ignoreDifferences`.

The fix: add scoped `ignoreDifferences` entries on the
`external-secrets` Application
(`bootstrap/platform-root/templates/external-secrets.yaml`):
- `ValidatingWebhookConfiguration .webhooks[]?.clientConfig.caBundle`
- `MutatingWebhookConfiguration .webhooks[]?.clientConfig.caBundle`

The `MutatingWebhookConfiguration` entry is defensive — current
chart only registers a `ValidatingWebhookConfiguration`, but the
upstream pattern across the platform always covers both kinds.

### Migration

For all clusters running v0.26.x:

1. Bump platform `ref=` to `v0.26.2` in client `providers/<cloud>/main.tf`
2. Bump `platform_version = "v0.26.2"` in client `terraform.tfvars`
3. `terraform init -upgrade && terraform plan && terraform apply`
4. `estabilis promote <client> -d <deployment> --force-refresh`
5. Force-sync `aws-load-balancer-controller` and `external-secrets` (manual sync apps)

Behaviour identical, no resource recreate, no data path impact.

## [0.26.1] - 2026-04-25

### Fixed — `cloudflare_record.value` deprecation warning

Cloudflare Terraform provider v4 deprecated the `value` argument in
favor of `content`. Every `terraform plan/apply` against an
`acm_enabled = true` cluster on the Cloudflare path emitted:

```
Warning: Argument is deprecated
  with module.estabilis_platform.cloudflare_record.acm_validation[...]:
  98:   value   = trimsuffix(each.value.record, ".")
  `value` is deprecated in favour of `content` and will be removed in
  the next major release.
```

The argument was added in v0.25.0 as part of the Cloudflare-validated
ACM path. Fixed: `value` → `content` in
`providers/aws/acm.tf:cloudflare_record.acm_validation`.

Behaviour identical, no resource recreate.

## [0.26.0] - 2026-04-25

### Fixed — Persistent OutOfSync on `network-policies`, `resource-quotas`, `aws-load-balancer-controller`

Cortex post-mortem (validated with `argocd-ingress`, `external-secrets`,
`platform-root`):

#### `network-policies` and `resource-quotas` — phantom drift on disabled components

Both charts have a `components.<ns>` map that defaults every entry to
`true`, so they unconditionally rendered `NetworkPolicy` /
`ResourceQuota` / `LimitRange` resources for namespaces of components
that an operator had disabled (e.g. `components.opencost = false`,
`components.traefik = false` on AWS clusters). The target namespaces
never exist, so the resources stay in `OutOfSync` forever.

The fix: `bootstrap/platform-root/templates/network-policies.yaml` and
`resource-quotas.yaml` now forward `.Values.components` into the child
Application via `valuesObject.components`. The chart-level gating
(`if hasKey $.Values.components $ns`) immediately starts honoring the
operator's intent.

Also added `policy-reporter: false` to platform-root `values.yaml`
defaults — every cluster carried this in `components` only via the
chart's default-true behaviour, even though policy-reporter is opt-in.

Mismatches between platform-root key naming and chart key naming
(e.g. platform's `cnpg` vs `resource-quotas` chart's `cnpg-system`,
platform's `trivy` vs `trivy-system`) are tolerated: the chart's
`hasKey` check falls through to default-true, which is correct for the
clusters that DO deploy those components. A follow-up PR will rename
the chart keys for full consistency.

#### `aws-load-balancer-controller` — phantom drift on webhook caBundle and TLS

The chart's webhook-self-signing init container patches the
`MutatingWebhookConfiguration` / `ValidatingWebhookConfiguration`
caBundle and the `aws-load-balancer-tls` Secret data at install time.
ArgoCD then sees the resulting in-cluster fields as drift against the
unpopulated chart manifest and reports `OutOfSync` permanently. Same
issue on the `IngressClassParams alb` body which the chart leaves empty
for the operator to fill in.

The fix: scoped `ignoreDifferences` entries on the `aws-load-balancer-
controller` Application:
- caBundle in both webhook configurations (jqPathExpression
  `.webhooks[]?.clientConfig.caBundle`)
- entire `data` of the TLS Secret
- entire `spec` of the `IngressClassParams alb` (body is not chart-managed)

The pattern follows the AKS `admissionsenforcer` precedent (Estabilis
memory `reference_aks_admissionsenforcer_webhook_drift`).

### Migration

For all clusters running v0.25.x:

1. `terraform apply` after pulling v0.26.0 — only the platform-root
   Application's `targetRevision` bumps; no infrastructure change.
2. `estabilis promote <client>` (or sync `platform-root` then
   downstream Apps directly) — the new `valuesObject` and
   `ignoreDifferences` propagate; existing OutOfSync states clear
   within the next reconcile loop.
3. NetworkPolicies / Quotas for disabled components are pruned
   automatically (their parent App auto-syncs with `prune: true`).

Zero impact on Azure-only clusters that have all components enabled.

## [0.25.2] - 2026-04-25

### Fixed — Properly delete node SG cluster-membership tag (v0.25.1 was a no-op)

The v0.25.1 fix was based on a wrong assumption about ALB Controller's
filter logic. We thought the controller filtered SGs by tag VALUE
(matching `["owned", "shared"]` only); empirically it filters by tag
KEY only. Setting `node_security_group_tags = { ... = "" }` produced a
tag with empty value but the same key — controller still found two
cluster-tagged SGs per ENI and continued to reject target rule
injection. Validated end-to-end on cortex by enabling
`grafana_exposures` after v0.25.1 apply: `Target.Timeout` returned
immediately.

Real fix: a `null_resource` with `provisioner "local-exec"` that calls
`aws ec2 delete-tags` on the node SG, with `triggers = { always =
timestamp() }` so it re-runs on every apply. The EKS module will
re-assert the tag every plan/apply (its tags map is hardcoded — see
node_groups.tf in terraform-aws-modules/eks), but this resource
re-deletes it immediately afterward. The cluster steady state has the
tag absent from the node SG, satisfying ALB Controller's "exactly one"
constraint.

Trade-off: terraform plan will show a small recurring drift in the
node SG's `tags` attribute (the cluster-membership key being added
back). This is expected; the apply restores the deleted state via the
null_resource. We deliberately did NOT use a provider-level
`ignore_tags` to suppress this drift, because it would also disable
drift detection on the `aws_ec2_tag.existing_subnets_cluster_membership`
resources from v0.25.0 (same key) — silently breaking subnet
auto-discovery if the tag were ever removed externally. Tracking
upstream: terraform-aws-modules/terraform-aws-eks#2997.

### Migration

For clusters that applied v0.25.1:

1. `terraform apply` after pulling v0.25.2 — the null_resource runs
   the delete-tags call. The empty-value `node_security_group_tags`
   override is removed automatically.
2. The `aws-load-balancer-controller` reconcile loop picks up within
   ~30 s; no restart needed (the SG state changes invalidate its
   filter result).

For Azure clients: zero impact.

### Removed (was never useful)

- `node_security_group_tags = { "kubernetes.io/cluster/<name>" = "" }`
  pseudo-fix from v0.25.1.

## [0.25.1] - 2026-04-25

### Fixed — Empty `kubernetes.io/cluster/<name>` tag on node SG (NO-OP, see v0.25.2)

> **Superseded by v0.25.2.** This release's approach (override the tag
> value to `""`) does not actually fix the ALB Controller bug because
> the controller filters by tag KEY, not value. Upgrade directly from
> v0.25.0 → v0.25.2.

Postmortem (immediate follow-on to v0.25.0): once the ACM cert + subnet
tags landed and the ALB front-door provisioned, ALB Controller still
refused to register pod targets — every reconcile loop emitted
`expected exactly one securityGroup tagged with
kubernetes.io/cluster/<cluster-name> for eni <eni-id>, got:
[<node-sg> <cluster-sg>]`.

Root cause: `terraform-aws-modules/eks` v20.37 hardcodes
`kubernetes.io/cluster/<cluster-name> = "owned"` in the node SG's tags
map (see node_groups.tf). The EKS service ALSO auto-tags the cluster
primary SG with the same key. The result is two SGs claiming cluster
membership — ALB Controller's algorithm requires exactly one to know
where to inject the rule that lets the load balancer reach pod IPs.
See terraform-aws-modules/terraform-aws-eks#2997.

Fix: pass `node_security_group_tags = { "kubernetes.io/cluster/<name>"
= "" }` to the EKS module. The module's merge order means our value
wins; the tag still exists (we can't delete via merge) but its empty
value falls outside ALB Controller's `["owned", "shared"]` filter, so
the controller correctly identifies the cluster primary SG as the
sole cluster-tagged SG and injects the rule there. Standard EKS+ALB
contract is preserved.

### Migration

For existing AWS clusters bootstrapped at < v0.25.1:

1. `terraform apply` after pulling v0.25.1 — the module re-tags the
   node SG with empty value.
2. Restart `aws-load-balancer-controller` deployment to clear its SG
   cache (the controller polls but a restart skips the wait).
3. Existing Ingresses with stuck `Target.Timeout` health checks
   reconcile automatically (~30s) once the SG rule is injected.

Zero impact on Azure clients.

## [0.25.0] - 2026-04-25

### Fixed — Close the AWS ALB cert + subnet-discovery gap

Postmortem from cortex E2E validation: v0.24.0's chart support for
`ingress_class = "alb"` rendered the right Ingress, but two missing
pieces of glue prevented ALB Controller from actually provisioning the
load balancer. Both pieces were operator-side workarounds in legacy
deployments — v0.25.0 closes both inside the platform module.

#### Cloudflare-validated ACM cert (was Route53-only)

`providers/aws/acm.tf` now creates the validation CNAME records via
the `cloudflare/cloudflare` provider when `dns_provider =
"cloudflare"`, using the same Cloudflare API token already required
for external-dns + cert-manager DNS-01 issuance. Previously the
module only auto-validated for Route53; Cloudflare clients had to
place CNAMEs by hand and the apply hung indefinitely on
`aws_acm_certificate_validation`.

- New: `cloudflare_record.acm_validation` (one per validation entry)
- Updated: `aws_acm_certificate_validation.wildcard` count gate +
  validation_record_fqdns now branches on dns_provider
- New required provider: `cloudflare/cloudflare ~> 4.0` in `versions.tf`

#### Subnet cluster-membership tag (vpc_mode = existing)

`providers/aws/eks.tf` now tags each subnet (public + private) with
`kubernetes.io/cluster/<cluster-name> = shared` when the platform
runs against a pre-existing VPC. Without this, ALB Controller fails
with "couldn't auto-discover subnets: tagged for other clusters" any
time the same VPC hosts more than one EKS cluster (typical during
legacy → new migration). `shared` (vs `owned`) is correct because the
platform module does NOT own the subnet lifecycle in this mode.

- New: `aws_ec2_tag.existing_subnets_cluster_membership` (one tag per
  subnet — `for_each = concat(public, private)`)

#### `alb_certificate_source` default flipped to `"acm"`

The v0.24.0 default of `"cert-manager"` was unworkable: AWS Load
Balancer Controller only consumes ACM certificates — it cannot read
k8s Secrets directly (no built-in `Secret → ALB cert` path). All five
AWS `*_exposures` variables now default to `"acm"`. Azure provider
defaults are unchanged (Azure path doesn't use ALB).

The `"cert-manager"` value is still accepted for forward compatibility
with future cert-manager → ACM syncer integrations, but rendering an
ALB Ingress with `alb_certificate_source = "cert-manager"` and no
syncer in place will produce a non-functional Ingress.

#### Cross-variable validation guards (fail fast at plan time)

Three new guards prevent silent footguns:

- `null_resource.alb_requires_acm_validation`: `ingress_controller =
  "alb"` requires `acm_enabled = true` (the chart cannot render an
  ALB without an ACM ARN).
- `null_resource.acm_requires_managed_dns`: `acm_enabled = true`
  requires `dns_provider = "route53"` or `"cloudflare"` (with
  `"none"` the validation CNAME never appears and apply hangs).
- Chart-level `fail` blocks: each `*-ingress` template now hard-fails
  if `alb_certificate_source = "acm"` but `global.acmCertificateArn`
  is empty, OR if `alb_certificate_source` is an unrecognized value.
  The error message points the operator at exactly which knob to
  flip.

### Migration

For existing AWS-on-ALB clusters provisioned with v0.24.0:

1. `terraform init -upgrade` (picks up the new `cloudflare/cloudflare`
   provider).
2. Set `acm_enabled = true` in the platform downstream `tfvars` (and
   verify `dns_provider = "cloudflare"` or `"route53"`).
3. `terraform apply` — provisions the ACM cert + validation CNAMEs +
   subnet cluster-membership tags. The cert ARN flows automatically to
   ingress charts via `global.acmCertificateArn`.
4. `estabilis promote` to refresh platform-root with the new ARN.
5. Existing ALB Ingresses that were stuck on "no certificate found"
   will reconcile automatically once the ACM cert is ISSUED. No
   manual `kubectl annotate` needed.

For Azure clients: zero impact (all changes are AWS-only).

## [0.24.0] - 2026-04-25

### Added — ALB ingress support across all 5 `*-ingress` charts

Closes the Traefik-only limitation flagged in ADR 0014. The five
`*-ingress` charts (`argocd`, `grafana`, `loki`, `mimir`, `hubble-ui`)
now branch on `ingress_class` per exposure profile:

- `traefik` / `traefik-internal` → existing IngressRoute pattern with
  Middlewares (ipAllowList, basicAuth via ESO).
- `alb` → AWS Load Balancer Controller pattern. Renders an Ingress
  with `alb.ingress.kubernetes.io/*` annotations + cert-manager
  Certificate (DNS-01) OR ACM cert reference.

#### Per-exposure new fields (provider-agnostic shape)

Added to every `*_exposures` variable in BOTH `providers/aws/variables.tf`
and `providers/azure/variables.tf` (Azure inert). All optional with
sensible defaults derived from the legacy `cortex-eks-prod` config:

| Field | Default | Purpose |
|---|---|---|
| `alb_group` | `"platform"` | `alb.ingress.kubernetes.io/group.name` — share ONE ALB across multiple Ingresses (cost optimization, ~$22/mo savings per shared group) |
| `alb_scheme` | `"internet-facing"` | `internet-facing` or `internal` |
| `alb_target_type` | `"ip"` | `ip` (Fargate-compatible) or `instance` |
| `alb_ssl_policy` | `"ELBSecurityPolicy-TLS13-1-2-2021-06"` | TLS 1.3 with min 1.2 |
| `alb_healthcheck_path` | `""` (chart default per-app) | argocd `/healthz`, grafana `/api/health`, loki/mimir `/ready`, hubble `/` |
| `alb_certificate_source` | `"cert-manager"` | `"acm"` uses `global.acmCertificateArn`; `"cert-manager"` issues via DNS-01 |
| `alb_cloudflare_proxied` | `false` | Sets `external-dns.alpha.kubernetes.io/cloudflare-proxied`. Always `false` recommended (orange cloud OFF) for source-IP allowlists to work |

#### Source-IP allowlist on ALB

Per-exposure `allowed_cidrs` now generates an
`alb.ingress.kubernetes.io/conditions.<service-name>` annotation with
the listener-rule condition (different mechanism from Traefik
`Middleware.ipAllowList` but equivalent semantics).

#### Basic auth limitation

`basic_auth: true` + `ingress_class: "alb"` is **not supported** —
ALB does not implement HTTP Basic Authentication natively (would
require Cognito or Lambda integration). The chart `fail`s loud with a
clear message explaining the limitation. Use Traefik for basic-auth
exposures.

#### Platform-root template gate

The Traefik gate (`components.traefik != false`) is now relaxed: only
required when at least one exposure targets a Traefik-style class.
ALB-only exposures render even with Traefik disabled.

#### `global.dnsProvider` + `global.acmCertificateArn` propagation

Both values are now passed as helm parameters to the 5 `*-ingress`
Applications, so the ALB chart branch can read them from
`$.Values.global.*`. Previously inaccessible to the chart context.

### Migration

Operators on `v0.23.0` adopting ALB ingress for any platform app:

1. Bump platform module ref to `v0.24.0`.
2. In `terraform.tfvars`, add `ingress_class = "alb"` (and any of the
   new `alb_*` fields) to the desired exposure profile, e.g.:
   ```hcl
   argocd_exposures = {
     external = {
       enabled                = true
       host                   = "argocd.example.com"
       ingress_class          = "alb"
       allowed_cidrs          = "203.0.113.0/24"
       alb_group              = "shared-apps"
       alb_certificate_source = "cert-manager"
     }
   }
   ```
3. `terraform apply` — refresh ConfigMap data.
4. Sync `argocd-ingress` (or whichever) Application. ALB provisions in
   ~1-2min; external-dns publishes the record; cert-manager issues
   the cert.

### Azure impact

Zero functional impact. Azure deployments never set
`ingress_class = "alb"`; the new ALB fields on the exposure type are
inert noise. The Traefik path is byte-identical to v0.23.0.

## [0.23.0] - 2026-04-25

### Added — AWS Load Balancer Controller Application + AppProject hardening

Closes the last AWS-only Application gap that was missing from
estabilis-platform vs the legacy cortex-eks-prod configuration. The
controller chart was deferred from Phase 2 (TF was provisioning the
IRSA role since v0.16.0 but no ArgoCD Application existed). This
release ships it on the same chart version (1.17.1, controller v2.17.1)
that legacy runs in production.

#### `bootstrap/platform-root/templates/aws-load-balancer-controller.yaml`

New Application gated on:
- `provider == "aws"`
- `components.aws-load-balancer-controller != false`
- `ingress_controller == "alb"`

Helm parameters:
- `clusterName` ← `global.clusterName`
- `vpcId` ← `global.vpcId`
- `serviceAccount.annotations.eks.amazonaws.com/role-arn` ←
  `identity.albController.roleArn`

Values from `estabilis-platform-gitops v0.36.0`:
`values/platform/aws-load-balancer-controller.yaml` (resources, SA,
PDB — mirrors legacy).

#### `bootstrap/platform-root/templates/argocd-project.yaml`

- `sourceRepos`: added `https://aws.github.io/eks-charts`.
- `destinations`: added `aws-load-balancer-controller` namespace.
- `clusterResourceWhitelist`: added `apiregistration.k8s.io/APIService`
  (bake of an in-place patch from v0.21.0 — required by metrics-server
  and historically missing).

#### `bootstrap/platform-root/values.yaml`

`components.aws-load-balancer-controller: true` default.

### Dependency

Requires `estabilis-platform-gitops >= v0.36.0`.

### Migration

Operators on AWS at `v0.22.0` adopting `alb` ingress:

1. Bump `platformGitopsVersion` to `v0.36.0` in
   `overrides/platform-root/values.yaml`.
2. Bump platform module ref to `v0.23.0`.
3. Set in `terraform.tfvars`:
   ```hcl
   ingress_controller = "alb"
   ```
4. `terraform apply` — provisions:
   - `module.alb_controller_irsa` (IAM role + AWS-managed policy)
   - ConfigMap data update (`global.ingressController = alb`,
     `identity.albController.roleArn`)
5. Refresh + sync `platform-root`. Three new Applications appear
   automatically when `ingress_controller = "alb"`:
   - `aws-load-balancer-controller`
6. Test by creating an Ingress with `ingressClassName: alb` and a
   host under the configured domain — external-dns should publish the
   record to Cloudflare (or Route53), cert-manager should issue a
   certificate, ALB should provision.

### Azure impact

Zero. All gates require `provider == "aws"`.

## [0.22.0] - 2026-04-25

### Added — `modules/cloudflare-credentials/` (cloud-agnostic) + AWS caller

Mirrors the `modules/github-app-credentials/` shape introduced in v0.18.0.
A cloud-agnostic Terraform module that creates a Kubernetes Secret with
the Cloudflare API token + zone ID it scopes to, plus per-provider AWS
Secrets Manager (or future Azure Key Vault) mirrors for audit / rotation.

#### `modules/cloudflare-credentials/`

- `main.tf` — `kubernetes_secret/cloudflare-credentials` in caller-provided
  namespace (default `external-dns`; AWS caller overrides to `argocd` to
  align with the Terraform-managed namespace).
- `variables.tf` — `cloudflare_zone_id` (32-char hex), `cloudflare_api_token`
  (sensitive, ≥20 chars), `domain` (lowercase DNS string), `namespace`,
  `secret_name`. All fields validated.
- `outputs.tf` — `secret_name`, `namespace`, `zone_id`, `domain`.
- `versions.tf` — `kubernetes >= 2.30.0`.

The module touches ONLY the Kubernetes cluster — zone management,
firewall rules, etc. are out of scope. The Cloudflare zone must already
exist; the token's permissions must include `Zone:DNS:Edit` and
`Zone:Zone:Read`.

#### AWS caller — `providers/aws/cloudflare.tf`

- Calls `module.cloudflare_credentials` when
  `var.dns_provider == "cloudflare"`.
- Mirrors the API token in `aws_secretsmanager_secret.cloudflare_api_token`
  under `<secrets_path_prefix>/platform-cloudflare-api-token`, encrypted
  with `aws_kms_key.platform_secrets`. ExternalSecrets Operator can read
  this entry post-bootstrap to reconcile the in-cluster Secret without a
  Terraform apply on token rotation.
- Resource policy applied when `secretsmanager_resource_policy_enabled`.

The existing helm.parameter passthrough (`global.cloudflareApiToken`,
`global.cloudflareZoneId` in the platform-infrastructure ConfigMap)
**remains** — chart consumers (external-dns, cert-manager DNS-01
ClusterIssuer) continue to consume that path. The new K8s Secret is the
source-of-truth artifact for a future migration to ESO-based reconciliation.

#### Azure caller — follow-up

This release ships the AWS caller only. The Azure caller
(`providers/azure/cloudflare.tf`) is a follow-up — the module's
cloud-agnostic shape unblocks it without further changes. Existing
Azure deployments using Cloudflare DNS (transfero HML) continue
unaffected on the passthrough path.

### Migration

Operators on AWS at `v0.21.0` adopting Cloudflare DNS:

1. Bump platform module ref to `v0.22.0`.
2. Set in `terraform.tfvars`:
   ```hcl
   dns_provider       = "cloudflare"
   cloudflare_zone_id = "<32-char zone id from Dashboard>"
   ```
3. In `secrets.auto.tfvars` (gitignored):
   ```hcl
   cloudflare_api_token = "<token with Zone:DNS:Edit + Zone:Zone:Read>"
   ```
4. `terraform apply` — provisions the K8s Secret + AWS SM mirror, sets
   ConfigMap fields. external-dns + cert-manager continue working on the
   passthrough; the new Secret is in place for a later migration PR.

### Azure impact

Zero. Module not yet called from Azure provider; existing Azure
deployments unchanged.

## [0.21.0] - 2026-04-24

### Added — metrics-server (AWS) + Karpenter v1.12.0 (AWS) + ArgoCD AppProject whitelists

Two cluster-autoscaling and observability primitives that EKS does NOT
ship by default but the legacy `cortex-eks-prod` cluster has run in
production for months. AKS provides metrics-server natively and uses
its own cluster-autoscaler — both Applications are gated on
`provider == "aws"`.

#### 1. metrics-server

EKS doesn't include metrics-server in its managed addon set; without
it, `kubectl top`, HPA, and any controller that reads the Resource
Metrics API stay broken. New Application:

- `bootstrap/platform-root/templates/metrics-server.yaml` — chart
  pinned to 3.12.2 (image v0.7.x), gated on
  `provider == "aws"` AND `components.metrics-server != false`.
- Values live in
  `estabilis-platform-gitops/values/platform/metrics-server.yaml`
  (ADR 0002 Phase 3 layout — values in gitops, Application in platform).
- Defaults mirror the legacy cortex configuration: 2 replicas,
  podAntiAffinity by hostname, `--kubelet-insecure-tls`, tight
  resource ask + limit.

#### 2. Karpenter v1.12.0

Despite Terraform provisioning the IAM controller role, IAM node role,
SQS interruption queue, and instance-profile-gc policy since Phase 1,
the Karpenter Helm chart was never installed on AWS clusters. Result:
`autoscaler = "karpenter"` and `autoscaler = "hybrid"` resolved to
"only the static MNG scales" — no spot capacity, no consolidation, no
elastic ceiling.

Three Applications added (`bootstrap/platform-root/templates/karpenter.yaml`):

1. **`karpenter-crds`** (sync-wave -1) — chart
   `oci://public.ecr.aws/karpenter/karpenter-crd` v1.12.0. Installs
   `NodePool`, `EC2NodeClass`, `NodeClaim`. `SkipDryRunOnMissingResource=true`
   prevents the next wave from blocking on Establishment timing.

2. **`karpenter`** (sync-wave 0) — chart
   `oci://public.ecr.aws/karpenter/karpenter` v1.12.0. Controller +
   webhook. Helm parameters wired from `platform-infrastructure`
   ConfigMap: `settings.clusterName`, `settings.interruptionQueue`,
   IRSA `serviceAccount.annotations.eks.amazonaws.com/role-arn`. Values
   in `gitops/values/platform/karpenter.yaml` mirror the legacy cortex
   release (controller resources, fargate toleration, `featureGates.spotToSpotConsolidation: true`).

3. **`karpenter-resources`** (sync-wave 1) — Estabilis-authored chart at
   `gitops/components/karpenter-resources/` with `NodePool` +
   `EC2NodeClass` templates. Defaults match legacy production:
   - NodePool: limits cpu=32 mem=64Gi, disruption
     `WhenEmptyOrUnderutilized` after 1m, requirements amd64 + spot/on-demand,
     instance categories c/m/r/t, generation > 4, sizes medium/large/xlarge,
     `expireAfter: 720h`.
   - EC2NodeClass: AMI alias `al2023@latest`, BDM `/dev/xvda` 30Gi gp3
     encrypted, **IMDSv2 enforcement** (`httpTokens: required`,
     `httpPutResponseHopLimit: 1`, `httpProtocolIPv6: disabled`) — same
     security baseline as the legacy cluster.
   - Subnet/SG selection via Terraform-applied
     `<global.karpenterDiscoveryTagKey>=<clusterName>` tags (default
     `estabilis.io/discovery=<cluster>`, allows multiple Estabilis
     deployments to coexist in one VPC).

Activation gate: `provider == "aws"` AND
`components.karpenter != false` AND `autoscaler in [karpenter, hybrid]`.
Provider asymmetry (Azure NAP / `karpenter-provider-azure`) tracked
in `Estabilis/estabilis-platform-tools#197`.

#### 3. AppProject `platform` — sourceRepos, destinations, clusterResourceWhitelist

`bootstrap/platform-root/templates/argocd-project.yaml` updated so
new Applications validate cleanly:

- `sourceRepos`: added `https://kubernetes-sigs.github.io/metrics-server/`
  and `public.ecr.aws/karpenter`.
- `destinations`: added `metrics-server` and `karpenter` namespaces.
- `clusterResourceWhitelist`: added `karpenter.sh/*` (NodePool, NodeClaim
  are cluster-scoped) and `karpenter.k8s.aws/*` (EC2NodeClass).

Without these, ArgoCD rejects the Applications at sync time with
`InvalidSpecError: application repo X is not permitted in project 'platform'`
or `Resource X is not allowed in project`.

### Components map

`bootstrap/platform-root/values.yaml` `components:` map gains
`metrics-server: true`, `karpenter: true`, `karpenter-resources: true`
defaults so downstream can disable individually via overrides.

### Provenance

Both new Applications include the standard
`platform-root.provenanceParameters` /
`platform-root.provenanceParametersBlock` helpers so ADR 0005 L1
supply-chain annotations flow onto every rendered resource.

### Dependency

**Requires `estabilis-platform-gitops >= v0.35.0`** — the new
`karpenter-resources` chart and the `values/platform/{metrics-server,karpenter}.yaml`
overlays are published from that release.

### Migration

Operators on AWS at `v0.20.1` → `v0.21.0`:

1. Bump `estabilis-platform-gitops` to v0.35.0+ first
   (`platformGitopsVersion` in `overrides/platform-root/values.yaml`).
2. Bump `estabilis-platform` to v0.21.0
   (`main.tf ref=v0.21.0`, `terraform.tfvars platform_revision`).
3. `terraform apply` — no infra-side changes, only the platform-root
   ConfigMap data refresh.
4. Refresh + sync `platform-root`. Three new Applications appear:
   `metrics-server`, `karpenter-crds`, `karpenter`, `karpenter-resources`.
5. After Karpenter controller is Healthy, scale the static MNG down
   (Karpenter handles burst capacity from there).

### Azure impact

Zero. All new Applications are `provider == "aws"` gated.

## [0.20.1] - 2026-04-24

### Fixed — Repo-creds collision when GitHub App is configured

The `platform-secrets` chart emits two `ExternalSecret` resources
(`repo-config-client`, `repo-client-gitops`) that produce argocd
`type: repository` Secrets with per-repo URL + token. When a GitHub
App is ALSO configured (via `modules/github-app-credentials/`, new
in v0.18.0), the resulting `repo-creds` Secret covers the whole org
by prefix match.

ArgoCD's repo matching prefers `type: repository` (exact URL) over
`type: repo-creds` (prefix). If the per-repo `password` field is
empty/placeholder — which happens on AWS when the `configRepoToken`
and `clientGitopsRepoToken` secrets have not been populated in AWS
Secrets Manager (the default, since TF does not provision them) —
ArgoCD authenticates with the empty/placeholder value and fails:

```
level=error msg="Failed to get git client for repo
  https://github.com/<org>/<repo>.git: failed to list refs:
  authentication required: Invalid username or token.
  Password authentication is not supported for Git operations."
```

This blocks platform-root `$overrides` source resolution and every
child Application goes `ComparisonError` until the placeholders are
replaced with real tokens — defeating the purpose of having the
GitHub App in the first place.

### Fix

- `core/components/platform-secrets/templates/argocd.yaml`: both
  ExternalSecrets now gated on
  `and .Values.<url> (not .Values.githubAppEnabled)` — so they only
  render on deployments that lack a GitHub App (legacy PAT path).
- `core/components/platform-secrets/values.yaml`:
  `githubAppEnabled: false` default.
- `bootstrap/platform-root/templates/platform-secrets.yaml` passes
  `githubAppEnabled = (ne global.githubAppID "")` as helm parameter.

### Azure impact

Neutral. Existing Azure deployments that do not set
`github_app_id` (most or all of them today) get
`githubAppEnabled=false` → gate behaves identically to pre-0.20.1 →
the per-repo ExternalSecrets still render exactly as before. Azure
deployments that later adopt the GitHub App module
(cloud-agnostic since v0.18.0) benefit from the same collision fix.

### Migration

v0.20.0 → v0.20.1 on AWS with GitHub App: pure chart update, no TF.
After bump + sync, manually delete the stale
`repo-config-client` and `repo-client-gitops` Secrets in the `argocd`
namespace (they are no longer managed by the ExternalSecrets) so that
ArgoCD falls back to the `github-app-<org>` repo-creds Secret for
repo auth.

## [0.20.0] - 2026-04-24

### Added — CNPG Postgres Cluster on AWS (Barman Cloud → S3 via IRSA)

Closes the "cnpg backup on AWS" gap tracked in
Estabilis/estabilis-platform-tools#186 (explicitly deferred on Phase 1).

The `cnpg-cluster` Application was gated azure-only in
`bootstrap/platform-root/templates/cnpg.yaml`, so AWS clusters ran the
cnpg operator but never got a `Cluster` CR. Grafana (and any other
component that talks to `platform-postgres-rw.cnpg-system`) could not
come up.

### Changes

#### 1. Chart: `core/components/cnpg-cluster/`

- `templates/cluster-azure.yaml` now wrapped in
  `{{- if eq .Values.global.provider "azure" }}` (was unconditional).
- **NEW** `templates/cluster-aws.yaml`: emits the same 3 resources as
  Azure (`Cluster`, `ScheduledBackup`, `ServiceAccount`) with:
  - `backup.barmanObjectStore.destinationPath: s3://<bucket>/platform-postgres`
  - `endpointURL: https://s3.<region>.amazonaws.com`
  - `s3Credentials.inheritFromIAMRole: true` (no static keys)
  - `ServiceAccount.annotations.eks.amazonaws.com/role-arn` (IRSA)
  - Generic EKS tolerations (no `kubernetes.azure.com/scalesetpriority`).
- `values.yaml` grows provider-neutral fields with AWS (bucket, region,
  roleArn) alongside the Azure (storageAccount, containerName, clientId)
  originals. Both coexist safely since only one branch renders.

#### 2. platform-root: `bootstrap/platform-root/templates/cnpg.yaml`

- Gate widened from `azure-only` to `azure OR aws`.
- AWS `{{- else if }}` helm.parameters branch passes:
  - `global.cnpgBackupBucketName` → `aws_s3_bucket.cnpg_backup.id`
  - `global.region` → `var.region`
  - `identity.cnpg.roleArn` → `aws_iam_role.cnpg.arn`
- Provider-agnostic parameters (retention days, schedule) hoisted
  outside the provider conditional.
- Added `global.provider` parameter so the chart templates can gate
  themselves.

### Terraform: already provisioned

`providers/aws/` already had everything in place since Phase 1:
- `aws_s3_bucket.cnpg_backup` + encryption/versioning/public-block
- `aws_iam_role.cnpg` + `aws_iam_role_policy.cnpg_s3` (trust scoped to
  SA `cnpg-system:platform-postgres`; policy grants S3 CRUD on the
  cnpg_backup bucket + KMS ops on `aws_kms_key.s3_data`).
- ConfigMap writes `global.cnpgBackupBucketName` + `identity.cnpg.roleArn`.

### Azure impact

Zero. The azure branch of `cnpg.yaml` carries identical parameter
names and the `cluster-azure.yaml` template is untouched beyond the
outer `{{- if azure }}` guard — which never evaluates false on Azure.
The values.yaml additions are ignored (no template references them
on Azure).

### Migration

v0.19.4 → v0.20.0 on AWS: pure chart update, no TF churn. Re-seed
`platform-root`, hard-refresh + sync `cnpg-cluster`. Expect a new
`Cluster/platform-postgres` CR in `cnpg-system`, followed by
`platform-postgres-{1,2,3}` Pods and the `platform-postgres-rw`
Service that `grafana-db` is waiting on.

## [0.19.4] - 2026-04-24

### Fixed — AWS ExternalSecret remoteRef.key path prefix

Cortex seed after v0.19.3 observed all 7 platform-secrets ExternalSecrets
failing with `AccessDeniedException: secretsmanager:GetSecretValue`.
Root cause: the platform-secrets chart's `kvSecrets.*` default values
use flat Key-Vault-style names (`platform-argocd-redis-password`),
but AWS SM secrets under Estabilis convention live at full paths
(`estabilis/<deploymentId>/platform-argocd-redis-password`). The
external-secrets IRSA role (`module.external_secrets_irsa`) explicitly
scopes its Secrets Manager access to that ARN pattern, so the flat
names get denied.

### Fix

`bootstrap/platform-root/templates/platform-secrets.yaml` gains an AWS
branch that passes each `kvSecrets.*` override as a helm parameter
with the prefix prepended. Azure retains the flat default values.

Secrets handled (6): argocdRedisPassword, grafanaAdminPassword,
grafanaDbPassword, configRepoToken, clientGitopsRepoToken, openaiApiKey.
Opencost secrets are already gated via `opencostEnabled` (v0.19.3)
and not re-keyed here.

### Operator caveat

Secrets that Terraform does not auto-provision on AWS (configRepoToken,
clientGitopsRepoToken, openaiApiKey) must be populated in AWS Secrets
Manager by the operator before the corresponding ExternalSecret can
reach `SecretSynced=True`. Same discipline as Azure Key Vault.

### Azure impact

Zero — the `{{- if eq .Values.global.provider "aws" }}` branch does
not execute on Azure. Existing kvSecrets flat defaults continue to
address Azure Key Vault secrets by name.

## [0.19.3] - 2026-04-24

### Fixed — Mimir S3 endpoint missing + platform-secrets opencost gate

Two issues surfaced by the cortex seed after v0.19.2 unblocked the
storage_prefix collision:

#### 1. Mimir: `no s3 endpoint in config file`

Mimir's thanos-io/objstore library requires an explicit `s3.endpoint`
config entry even on AWS-native S3 (unlike Loki which auto-derives
from region). The v0.19.0 mimir-values-aws.yaml + helm.parameters
didn't set it, so mimir-ingester/querier/ruler/alertmanager
CrashLoopBackOff with:

```
level=error msg="error running application"
  err="no s3 endpoint in config file"
```

Fix: `bootstrap/platform-root/templates/grafana-stack.yaml` grafana-mimir
AWS branch now injects
`mimir.structuredConfig.common.storage.s3.endpoint = s3.<region>.amazonaws.com`.

#### 2. platform-secrets: opencost ExternalSecrets fail on opencost-disabled clusters

`core/components/platform-secrets/templates/opencost.yaml` emitted
two ExternalSecrets targeting `namespace: opencost` unconditionally.
When a downstream sets `components.opencost: false` (cortex does —
AWS CUR integration is deferred), the opencost Application is never
created, the namespace doesn't exist, and platform-secrets sync
fails:

```
one or more objects failed to apply, reason: namespaces "opencost"
not found
```

Fix:
- Wrap opencost.yaml in `{{- if .Values.opencostEnabled }}`.
- Add `opencostEnabled: true` default in platform-secrets values.yaml
  (keeps existing Azure deployments unchanged).
- platform-root's platform-secrets.yaml passes
  `opencostEnabled = (ne components.opencost false)` as helm parameter.

### Migration

v0.19.2 → v0.19.3: pure Helm template update, no TF churn.

### Azure impact

Zero on mimir side (Azure uses container_name, different code path).
Zero on opencost side (Azure clients ship with opencost enabled; the
new gate defaults true).

## [0.19.2] - 2026-04-24

### Fixed — Mimir AWS S3 storage collision (blocks/ruler/alertmanager same bucket+prefix)

v0.19.0 shipped `mimir-values-aws.yaml` with `blocks_storage`,
`ruler_storage`, and `alertmanager_storage` all backed by the shared
observability S3 bucket without differentiating prefixes. Mimir's chart
validator rejects this:

```
error validating config: invalid bucket config:
  ruler storage: S3 bucket name and storage prefix cannot be the same as
  the one used in blocks storage config
```

The grafana-mimir-ruler and grafana-mimir-querier pods CrashLoopBackOff;
`grafana-mimir-alertmanager` fails to start too.

### Fix

Add `storage_prefix` to each storage class in `mimir-values-aws.yaml`:

```yaml
blocks_storage:       { storage_prefix: "blocks",       ... }
ruler_storage:        { storage_prefix: "ruler",        ... }
alertmanager_storage: { storage_prefix: "alertmanager", ... }
```

Single bucket, three prefixes — no IAM changes, no new infra.

### Azure impact

Zero. Azure mimir uses `container_name: mimir-blocks` at blocks_storage
only; ruler + alertmanager inherit common config. Pattern works because
Azure Blob Storage distinguishes by container_name natively in the
mimir chart. This is an AWS-specific file edit.

## [0.19.1] - 2026-04-24

### Fixed — AWS `platformVersion` ConfigMap key writes stale `var.platform_version` instead of the effective revision

v0.19.0 shipped AWS provider parity (loki/mimir/velero S3 values +
ClusterSecretStore AWS). After merge + cortex bump + `terraform apply`
the live velero and grafana-loki Applications failed to load their
`*-values-aws.yaml` files. Root cause: a latent ADR 0020 migration
gap in the AWS `platform-outputs.tf` ConfigMap writer.

#### The bug

Child Application templates in `bootstrap/platform-root/templates/*.yaml`
reference the platform repo via `targetRevision: {{ .Values.platformVersion }}`.
Their `$values` multi-source ref uses the same `platformVersion` to
check out the platform repo at the right tag, and `helm.valueFiles`
resolves files inside that checkout (e.g. `$values/core/components/velero/values-aws.yaml`).

`providers/aws/platform-outputs.tf` wrote the ConfigMap as:

```hcl
"platformVersion"  = var.platform_version      # literal legacy var
"platformRevision" = local.platform_revision_effective  # derived
```

A downstream client that bumps only `platform_revision` in tfvars
(the documented path since v0.13.0 / ADR 0020) leaves
`var.platform_version` at its stale default. The ConfigMap's
`platformVersion` key keeps pointing at the old tag; the `$values`
source resolves against that old tag; the new `*-values-aws.yaml`
files added in v0.19.0 are not present in the old ref; and
`ignoreMissingValueFiles: true` silently skips them.

Observed on cortex 2026-04-24:
- `platformRevision` in ConfigMap = `v0.19.0` ✓
- `platformVersion` in ConfigMap = `v0.18.0` (stale) ✗
- `kubectl -n argocd get application velero -o yaml` → `source[1].targetRevision = v0.18.0`
- Helm rendered with only `values.yaml` (not `values-aws.yaml`)
- Velero schema failed: `missing property 'provider' at /configuration/{backup,volumeSnapshot}StorageLocation/0`
- Loki failed: `You must provide a schema_config for Loki`

Both errors collapsed to "values-aws.yaml didn't load".

### Fix

Write `platformVersion = local.platform_revision_effective` in the
AWS `platform-outputs.tf` ConfigMap data. Both keys now carry the
effective git ref. Child templates that read `.Values.platformVersion`
always see the current platform tag without requiring the client to
maintain two tfvars in lockstep.

Azure is unaffected — `providers/azure/platform-outputs.tf` was not
touched (Azure doesn't write `platformRevision` at all, and Azure's
seed path populates `platformVersion` via CLI tfvars loading where
operators set both fields historically).

### Migration

Operators on `v0.19.0` on AWS: bump to `v0.19.1`, `terraform apply`
(ConfigMap data-only change; 1 in-place update). Child Applications
re-render on next platform-root sync and `*-values-aws.yaml` files
load correctly.

### Follow-up (not blocking)

Consider a `platform-root.platformRef` helper in `_helpers.tpl` that
mirrors `clientGitopsRef` (prefer `platformRevision` over
`platformVersion`) and migrate all `targetRevision: {{ .Values.platformVersion }}`
call sites to it. That's a larger sweep (~30 files). This PR is the
minimum to unblock cortex and ship AWS parity.

## [0.19.0] - 2026-04-24

### Added — AWS provider parity: Loki/Mimir S3, Velero S3, ClusterSecretStore via Secrets Manager

v0.18.1 → v0.18.3 fixed the AWS seed path enough to get platform-root
to finish its first sync (rename ConfigMap key, fix AppProject gate,
gate null `parameters:` in velero/grafana-loki/grafana-mimir). The
cortex seed then advanced past those and surfaced the deeper gap: AWS
provider was **not feature-complete** — several components had Azure
wiring only and no AWS equivalent.

This release ships the missing AWS values + template wiring for three
stacks: observability (loki, mimir), backup (velero), and secrets
(ClusterSecretStore). Net effect: an AWS cluster can now reach Healthy
for the same component set Azure has been shipping since v0.1.x.

#### 1. Loki AWS S3 backend

New `core/components/grafana-stack/loki-values-aws.yaml`:
- `loki.storage.type: s3`
- `loki.storage.s3.region` (injected)
- `loki.storage.bucketNames.{chunks,ruler,admin}` (injected, all point
  to the shared observability bucket)
- `schemaConfig.configs[0].object_store: s3`
- `serviceAccount.annotations.eks.amazonaws.com/role-arn` (injected)

`bootstrap/platform-root/templates/grafana-stack.yaml` `grafana-loki`
gains a `{{- else if aws }}` helm.parameters branch emitting:
- `loki.storage.bucketNames.{chunks,ruler,admin}` → `global.observabilityBucketName`
- `loki.storage.s3.region` → `global.region`
- `serviceAccount.annotations.eks\.amazonaws\.com/role-arn` → `identity.loki.roleArn`

#### 2. Mimir AWS S3 backend

New `core/components/grafana-stack/mimir-values-aws.yaml`:
- `mimir.structuredConfig.common.storage.backend: s3`
- `mimir.structuredConfig.{common,blocks_storage,ruler_storage,alertmanager_storage}.s3.bucket_name` (all injected)
- `serviceAccount.annotations.eks.amazonaws.com/role-arn` (injected)
- `global.podLabels: {}` — removes Azure Workload Identity label (IRSA
  uses annotations, not labels)

`bootstrap/platform-root/templates/grafana-stack.yaml` `grafana-mimir`
gains the equivalent `{{- else if aws }}` branch.

#### 3. Velero AWS S3 backend

New `core/components/velero/values-aws.yaml`:
- `configuration.backupStorageLocation[0].provider: aws` (+ bucket/region injected)
- `configuration.volumeSnapshotLocation[0].provider: aws` (+ region injected)
- `initContainers[0].image: velero/velero-plugin-for-aws:v1.12.0`
- `serviceAccount.server.annotations.eks.amazonaws.com/role-arn` (injected)

`bootstrap/platform-root/templates/velero.yaml` gains `{{- else if aws }}`
helm.parameters:
- `configuration.backupStorageLocation[0].bucket` → `global.veleroBackupBucketName`
- `configuration.backupStorageLocation[0].config.region` → `global.region`
- `configuration.volumeSnapshotLocation[0].config.region` → `global.region`
- `serviceAccount.server.annotations.eks\.amazonaws\.com/role-arn` → `identity.velero.roleArn`
- `schedules.platform-daily.*` — shared with Azure path

#### 4. ClusterSecretStore AWS via Secrets Manager

`bootstrap/platform-root/templates/cluster-secret-store.yaml` gate
widened from `azure`-only to `azure OR aws`. The Application is now
emitted on both providers; the provider-specific helm parameters
differ:
- Azure: `vaultUrl` + `tenantId`
- AWS: `region`

The underlying chart lives in `estabilis-platform-gitops` at
`components/cluster-secret-store/`. That chart was updated in
`estabilis-platform-gitops` **v0.34.0** to support the `provider`
field and render an AWS ClusterSecretStore via IRSA (JWT
`serviceAccountRef`). See that repo's CHANGELOG for the chart-side
details.

**Requires `estabilis-platform-gitops >= v0.34.0`.** Older gitops
releases don't know the AWS template; platformGitopsVersion must be
bumped together with this platform release on AWS clusters. Azure
clusters can roll forward independently since the chart defaults to
Azure when no `provider` value is set.

#### 5. IAM — loki/mimir S3 scope broadened to bucket-wide

`providers/aws/iam.tf` `data.aws_iam_policy_document.{loki_s3,mimir_s3}`
previously restricted object access to `<bucket>/loki/*` and
`<bucket>/mimir/*` prefixes. The loki chart (6.54) and mimir chart
(6.0.5) do not support a global object-key prefix — objects land at
bucket root. Without bucket-wide access the components get
AccessDenied on every PutObject.

Fix: broaden `resources` to `<bucket>/*`. Loki + mimir share the
`observability` bucket and each has full access. Narrowing to a
per-component prefix would require provisioning separate buckets —
tracked as a follow-up if hard isolation between loki/mimir data
becomes a requirement. Azure is unaffected (separate blob containers
per component).

### Migration

1. Bump `estabilis-platform-gitops` to v0.34.0+ first.
2. Bump `estabilis-platform` to v0.19.0.
3. Update downstream:
   - `main.tf ref=v0.19.0`
   - `terraform.tfvars platform_revision = "v0.19.0"`
   - `overrides/platform-root/values.yaml platformGitopsVersion: "v0.34.0"`
   - downstream tag
4. `terraform apply` — expect:
   - `aws_iam_role_policy.loki_s3` in-place update (resource list)
   - `aws_iam_role_policy.mimir_s3` in-place update (resource list)
   - `kubernetes_config_map.platform_infrastructure` in-place update
     (platformRevision key flip to v0.19.0)
   - no infrastructure churn beyond those three
5. Hard refresh + sync `platform-root`. Expect grafana-loki +
   grafana-mimir + velero + cluster-secret-store + platform-secrets
   to reach Synced/Healthy.

### Azure impact

- Loki/Mimir/Velero template fixes include `{{- else if aws }}`
  branches — Azure branches render exactly as before.
- cluster-secret-store template gate widened; when
  `global.provider == "azure"` the emitted Application is byte-
  identical to before (same helm parameters, same values files, same
  path).
- IAM changes are in `providers/aws/iam.tf` — never evaluated on
  Azure.

## [0.18.3] - 2026-04-24

### Fixed — AWS null `helm.parameters` in `grafana-loki` and `grafana-mimir` (same anti-pattern as v0.18.2 velero fix)

v0.18.2 patched the `velero` Application in `platform-root` so the
`parameters:` block is gated behind `{{- if eq .Values.global.provider
"azure" }}`. The cortex AWS seed on 2026-04-24 then advanced past
velero, into sync-wave 8, and hit the SAME anti-pattern in two more
Applications rendered from `bootstrap/platform-root/templates/grafana-stack.yaml`:

```
Application.argoproj.io "grafana-loki" is invalid:
  spec.sources[0].helm.parameters: Invalid value: "null":
  spec.sources[0].helm.parameters in body must be of type array: "null"
Application.argoproj.io "grafana-mimir" is invalid:
  spec.sources[0].helm.parameters: Invalid value: "null":
  spec.sources[0].helm.parameters in body must be of type array: "null"
```

Same shape as the velero bug: `parameters:` emitted unconditionally,
Azure branch populated, AWS branch holding only a `# AWS — to be
implemented` comment. On AWS the block renders as empty → YAML parses
as `null` → CRD rejection → platform-root sync aborts mid-wave,
blocking all later Applications from reconciling.

### Fix

Move `parameters:` inside the `{{- if azure }}` branch for both
`grafana-loki` and `grafana-mimir`. AWS reads provider wiring from
`core/components/grafana-stack/loki-values-aws.yaml` /
`mimir-values-aws.yaml` — no helm parameter overrides needed (matches
what velero.yaml already does in v0.18.2).

### Audit — is the anti-pattern anywhere else?

Cataloged every template under `bootstrap/platform-root/templates/*.yaml`
with a `parameters:` block inside a provider conditional. Besides
velero (fixed in v0.18.2) and grafana-loki/grafana-mimir (fixed here):

- `cert-manager.yaml` — AWS branch IS populated (sets IRSA role-arn); safe.
- `external-secrets.yaml` — AWS branch IS populated + unconditional
  `installCRDs=false` always keeps the array non-empty; safe.
- `external-dns.yaml` — unconditional `domainFilters[0]` + `txtOwnerId`
  always keep the array non-empty; the AWS dnsProvider branch has a
  TODO comment but it's additive, not a leading `parameters: []`; safe.
- `cluster-secret-store.yaml` — whole Application is gated on
  `provider == azure`; on AWS, no Application is emitted (different
  gap — AWS ClusterSecretStore needs a separate implementation, tracked
  elsewhere). Not a null-params bug.

### Migration

Operators on `v0.18.2` on AWS: bump to `v0.18.3`, `terraform apply`
(no Terraform-tracked resources change — Helm template update only).
Trigger a fresh sync of `platform-root` (use the top-level `operation`
field on the Application, not `spec.operation`). Children on wave 8
should reconcile.

Azure is unaffected — Azure branches render their parameters as
before.

## [0.18.2] - 2026-04-24

### Fixed — AWS platform-root seed: `velero` Application rendering `helm.parameters: null` + AppProject gate still keyed on legacy `configRepoVersion`

Two AWS-seed bugs surfaced by the cortex EKS first-seed on 2026-04-24
after `v0.18.1` unblocked the `clientGitopsRepoRevision` key mismatch.

#### 1. `bootstrap/platform-root/templates/velero.yaml` — empty `parameters:` key on AWS

The `velero` Application template emitted `parameters:` unconditionally,
with an `azure` branch supplying parameters and an `aws` branch holding
only a `# AWS — to be implemented` comment. Rendered output on AWS:

```yaml
helm:
  valueFiles: [...]
  parameters:
```

which YAML parses as `parameters: null`. The ArgoCD Application CRD
rejects `null` for `spec.sources[].helm.parameters` (expects an array),
so `platform-root` sync aborted mid-flight:

```
Application.argoproj.io "velero" is invalid:
  spec.sources[0].helm.parameters: Invalid value: "null":
  spec.sources[0].helm.parameters in body must be of type array: "null"
```

Downstream Applications never reached Synced state because the apply
batch aborted before reconciling them.

**Fix:** move `parameters:` inside the Azure provider branch so AWS
simply omits the key. AWS velero reads its provider wiring from
`core/components/velero/values-aws.yaml` — no helm parameter overrides
needed.

#### 2. `bootstrap/platform-root/templates/argocd-project.yaml` — `sourceRepos` gate still requires legacy `configRepoVersion`

Three `AppProject.sourceRepos` blocks (the `platform`, `workload-baseline`,
and `applications` projects) gated inclusion of `configRepoUrl` on
`and .Values.configRepoUrl .Values.configRepoVersion`. After ADR 0020
(v0.13.0) migrated own-content repo refs to `*Revision` keys, clients
using only the new `configRepoRevision` (e.g. cortex) never added their
config repo to `sourceRepos`, producing:

```
InvalidSpecError:
  application repo <config-repo> is not permitted in project 'platform'
```

Every child Application with an `$overrides` source failed spec
validation. The sibling `clientGitopsRepoUrl` gate (lines 20 and 145)
already requires only the URL — the asymmetry with `configRepoUrl` was
pre-existing.

**Fix:** drop the version requirement on all three gates. Align with
the `clientGitopsRepoUrl` pattern — the URL alone is sufficient to
authorize the repo as a source. Legacy clients using `configRepoVersion`
are unaffected; new clients using `configRepoRevision` start working.

### Migration

Operators on `v0.18.1` on AWS: bump to `v0.18.2`, `terraform apply`
(no Terraform-tracked resources change — this only updates Helm
templates sourced by `platform-root` via `$values`). Trigger a sync /
hard refresh of `platform-root`; the helm template re-renders without
the `null` parameters error and the `platform` AppProject
`sourceRepos` now includes `configRepoUrl`.

Azure is unaffected by bug #1 (Azure branch of the template was already
correct). Azure is unaffected by bug #2 in practice because existing
Azure clients set the legacy `config_repo_version` tfvar — but the fix
is safe for them and future-proofs the Azure migration to
`configRepoRevision`.

## [0.18.1] - 2026-04-24

### Fixed — ConfigMap key mismatch: `clientGitopsRevision` → `clientGitopsRepoRevision`

The AWS `platform-outputs.tf` wrote the client-gitops ref to the
`platform-infrastructure` ConfigMap under the key `clientGitopsRevision`
(no `Repo` in the middle). The `platform-root` chart expects
`clientGitopsRepoRevision` (matching the pattern of
`clientGitopsRepoUrl` + `clientGitopsRepoVersion`). See
`bootstrap/platform-root/values.yaml:191` and
`bootstrap/platform-root/templates/_helpers.tpl:120`.

Result: when downstream operators pass the ConfigMap values through
as Helm parameters (as the estabilis CLI and manual seed scripts
both do), the key never lands on `.Values.clientGitopsRepoRevision`
inside the chart. Combined with `clientGitopsRepoUrl` being set, the
`platform-root.clientGitopsRefRequired` helper fires its `fail`:

```
execution error at (platform-root/templates/hub-client-apps.yaml:45:21):
  clientGitopsRepoRevision (or legacy clientGitopsRepoVersion) is required
  when clientGitopsRepoUrl is set
```

Observed 2026-04-24 on the cortex AWS seed: platform-root Application
stuck in `ComparisonError` with exactly this helm template failure.

### Fix

Rename the key in `providers/aws/platform-outputs.tf` from
`clientGitopsRevision` to `clientGitopsRepoRevision`. One-character-
semantic change; no schema breakage for consumers because the old key
was never consumed (nothing in the chart read it — that was the bug).

### Migration

Operators on `v0.18.0` on AWS: bump to `v0.18.1`, `terraform apply`
(ConfigMap data updates in place, no infra changes). Re-trigger the
platform-root Application (or the CLI re-runs the manifest generation)
and the helm template completes.

Azure is unaffected — `providers/azure/platform-outputs.tf` never
wrote this key at all, so no drift existed.

## [0.18.0] - 2026-04-24

### Added — `modules/github-app-credentials/` (cloud-agnostic) + AWS caller

Organization-scoped GitHub App authentication for ArgoCD git access,
managed by Terraform. Introduces a transversal module plus the AWS
provider wiring that makes it usable today. Azure/GCP callers will
follow the same shape in subsequent releases.

#### Why GitHub App (vs. PAT or deploy keys)

- Belongs to the GitHub organization — **not user-scoped**. When the
  user who set up the credential leaves the org, the App keeps working.
- One install covers N repos; **scales to multi-repo clients**.
- Fine-grained permissions: `Contents: Read-only` is enough.
- ArgoCD renews installation tokens (1h TTL) automatically — **no
  external rotation infrastructure needed**.

Deploy keys (per-repo) and per-user PATs are viable fallbacks but don't
scale or survive personnel changes. Pattern used by the legacy
`cortex-eks-prod` cluster pinned an SSH key to a specific user account,
which this release supersedes going forward.

#### Module: `modules/github-app-credentials/`

Cloud-agnostic. Creates one Kubernetes Secret with the
`argocd.argoproj.io/secret-type: repo-creds` label, carrying
`githubAppID`, `githubAppInstallationID`, `githubAppPrivateKey`, and a
normalized `url`. ArgoCD matches repos by URL prefix — one credential
template covers every repo under the org.

Inputs:
- `github_app_id`, `github_app_installation_id` (numeric IDs)
- `github_app_private_key` (PEM, sensitive, validated)
- `github_org_url` (e.g. `https://github.com/Cortex-Innovation`)
- `namespace` (default `argocd`), `secret_name` (default derived from org slug)

Outputs: `secret_name`, `namespace`, `org_slug`.

#### AWS wiring: `providers/aws/github-app.tf`

Composes the module call with AWS Secrets Manager mirror:

1. Module creates the in-cluster Kubernetes Secret ArgoCD reads.
2. `aws_secretsmanager_secret.github_app_private_key` stores the PEM
   under `${secrets_path_prefix}/platform-github-app-private-key` —
   becomes source of truth for rotation + the handoff path for
   ExternalSecrets once `platform-secrets` chart is reconciling.

Both are gated on `github_app_private_key != ""`; a deployment that
uses a different auth path (deploy keys, per-user PATs) can leave all
four `github_app_*` variables empty and nothing is created.

Cross-input validation via `null_resource` precondition: if any of the
four `github_app_*` variables is set, all four must be set. Leaving
all four empty disables the feature entirely.

#### ConfigMap: new non-sensitive identifiers

`providers/aws/platform-outputs.tf` exposes three new keys on the
`platform-infrastructure` ConfigMap:

- `global.githubAppID`
- `global.githubAppInstallationID`
- `global.githubOrgUrl`

These are public identifiers (not secrets) needed by downstream charts
(e.g. future `platform-secrets` ExternalSecret) to build the
credential template shape. The PEM stays **only** in AWS Secrets
Manager and the existing in-cluster Secret.

### Migration

- Operators who want to adopt GitHub App: create the App on the org
  (see `modules/github-app-credentials/README.md` for step-by-step),
  set the four `github_app_*` variables in `terraform.tfvars` (or
  `secrets.auto.tfvars` for the private key), `terraform apply`.
- Operators who stay on other auth paths: no change, no new resources.

### Follow-up (tracked separately)

- `providers/azure/` caller that mirrors to Key Vault — same shape.
- `core/components/platform-secrets/` chart adds an ExternalSecret that
  reconciles the K8s Secret from the SM/KV entry post-bootstrap,
  enabling key rotation in the secret store to propagate without a
  Terraform apply.

## [0.17.5] - 2026-04-24

### Fixed — MNG nodes lose DNS to Fargate pods (CoreDNS, ArgoCD)

The `terraform-aws-modules/eks/aws` module defaults
`attach_cluster_primary_security_group = false` on managed node
groups. Without that attachment, MNG ENIs receive only the module's
`-node` shared security group — a DIFFERENT SG from the `eks-cluster-sg-*`
that EKS auto-creates and attaches to Fargate pod ENIs.

Consequence: traffic between MNG pods and Fargate pods (including
CoreDNS which runs on Fargate by default) is not in the same intra-
cluster trust boundary. DNS queries from MNG pods time out because
the `kube-dns` service endpoints are Fargate ENIs on a different SG.
**Every service lookup by name breaks** when originated from an MNG
pod: Application Controller can't reach `argocd-redis` or
`argocd-repo-server`, platform-root stalls with "ComparisonError: dns:
A record lookup error".

Observed 2026-04-24 on the cortex seed: `nslookup
kubernetes.default.svc.cluster.local` from a debug pod on an MNG
node → "connection timed out; no servers could be reached". CoreDNS
itself was Ready and responsive — the path from MNG ENI to Fargate
ENI was blocked at the SG layer.

The legacy `cortex-eks-prod` cluster (provisioned outside this
module) works because its MNG nodes were attached to the EKS
cluster primary SG directly. Our module-provisioned MNGs were not.

### Fix

Set `attach_cluster_primary_security_group = true` on the `default`
MNG block in `eks.tf`. The next `terraform apply` updates the MNG
launch template; the MNG rolls nodes (brief ~2min drain/replace) so
new ENIs receive both the node SG and the cluster primary SG.

```hcl
eks_managed_node_groups = {
  default = {
    ...
    attach_cluster_primary_security_group = true
  }
}
```

### Migration

Operators on v0.17.4 on AWS with MNG (`autoscaler = "hybrid"` or
`"cluster_autoscaler"`): bump module `ref` to `v0.17.5`, run
`terraform plan`. Expected plan diff: the MNG launch template adds
the cluster primary SG to `vpc_security_group_ids`. Apply triggers a
rolling update of MNG nodes; brief pod reschedule across nodes but
no cluster-wide disruption because Fargate-hosted system workloads
(CoreDNS, ebs-csi-controller, etc.) stay up. Post-apply, DNS
resolution from MNG pods works.

### Related

- Estabilis/estabilis-platform#76 — v0.17.0, introduced `hybrid`
  autoscaler (MNG + Karpenter); this patch is the missing piece that
  lets MNG pods integrate with Fargate-hosted system services
- Cortex seed 2026-04-24 — real-world reproducer

## [0.17.4] - 2026-04-24

### Fixed — `argocd-repo-server` CrashLoopBackOff — disable liveness probe during bootstrap

Follow-up to v0.17.3. That release tried to override the liveness
probe `httpGet.path` from `/healthz?full=true` to `/healthz` via
values. Verification on the cortex seed today revealed the override
is **silently ignored by the chart**.

Root cause: the `argo-cd` chart v9.x values schema for repo-server
probes exposes only scalar fields (`enabled`, `timeoutSeconds`,
`failureThreshold`, `initialDelaySeconds`, `periodSeconds`,
`successThreshold`) and has NO `httpPath` or `httpGet` key. The probe
path is hardcoded in the Deployment template as
`/healthz?full=true` and cannot be customized via values. Our v0.17.3
override was syntactically valid YAML but semantically a no-op.

Confirmed by:

- `helm get values argocd -n argocd` → release has `httpGet.path=/healthz`
  in user-supplied values
- `kubectl get pod ... -o jsonpath` → pod still has
  `httpGet.path=/healthz?full=true`
- `helm template ... --values ...` dry-run → same result

The `?full=true` handler cascades through Redis + Git backends + repo
cache. On fresh clusters (bootstrap window, no Applications
configured) one sub-check hangs and the handler never returns. Every
kubelet poll times out and the container is SIGTERMed in a restart
loop.

Since the path cannot be customized, the only deterministic fix at
the values layer is to **disable the liveness probe during
bootstrap**:

```yaml
repoServer:
  livenessProbe:
    enabled: false
  readinessProbe:
    timeoutSeconds: 10
```

Readiness stays on and still gates Service inclusion; without
liveness, kubelet does not kill the pod on probe failures. When
platform-root reconciles and real Applications populate the cluster,
the `?full=true` handler completes normally and liveness can be
re-enabled via downstream overrides if desired.

### Migration

Operators on v0.17.3: bump module `ref` to `v0.17.4`. On the next
ArgoCD reconcile of the self-managed `argocd` Application, the probe
override is applied to the Deployment; a rolling update follows and
the restart loop stops.

### Related

- v0.17.3 attempted the same fix with `httpGet.path` — unsuccessful
  because the chart ignores that key. This patch takes the only
  working route (`enabled: false`).
- Upstream chart issue: exposing `httpPath` / `httpGet` on
  `repoServer.livenessProbe` would eliminate the need for this
  workaround. Worth proposing to `argoproj/argo-helm` later.

## [0.17.3] - 2026-04-24

### Fixed — `argocd-repo-server` CrashLoopBackOff on fresh clusters

The upstream `argo-cd` chart v9.x defaults the `repoServer.livenessProbe`
to `GET /healthz?full=true` on port `metrics` (8084). The `?full=true`
handler does cascading checks across Redis, Git backends, and the repo
cache. On a cluster where no Applications have been configured yet
(the very first seed window), one of those sub-checks hangs without
an internal timeout, and the handler simply never returns.

Consequence: every kubelet poll of the liveness probe times out,
kubelet kills the container, kubelet restarts it — CrashLoopBackOff
with exit code 0 ("Completed" / "clean shutdown"), confusing to read
because the process is not crashing, it is being SIGTERM'd for
health-check failure.

Observed on cortex EKS seed 2026-04-24 (MNG `t3a.medium` / `t3.medium`
nodes). On Azure AKS with `Standard_D2s_v5`-class nodes the symptom
does not appear — consistent CPU (no burst credits) + the
`replicas: 2` override mean probe noise is absorbed. AWS burstable
MNGs expose the latent bug.

### Fix

`core/components/argocd/values.yaml` overrides the `repoServer`
livenessProbe to use the plain `/healthz` endpoint (not `?full=true`),
with `timeoutSeconds: 5` and `initialDelaySeconds: 30`. The readiness
probe keeps the full check (where "subsystems ready" is the right
semantic) but with `timeoutSeconds: 10` to absorb slow cold-starts.

Semantic split:
- **Liveness** = "is the process responsive" → plain `/healthz`
- **Readiness** = "are all subsystems ready" → `/healthz?full=true`

This is how most ArgoCD deployments configure it in production; the
chart's default choice of `?full=true` for liveness is arguably a
chart bug, but overriding at the platform level keeps us unblocked.

### Where this fix applies

`core/components/argocd/values.yaml` is the file consumed by the
`argocd` Application rendered by `platform-root` (self-managed ArgoCD).
Once platform-root syncs the `argocd` Application after bootstrap, the
self-manage apply of these values fixes the probe for the steady
state.

The **bootstrap window** (helm install before ArgoCD takes over via
self-manage) still uses the CLI's inline `seed_values` in
`estabilis-platform-tools/src/estabilis/kubernetes.py:_helm_install_argocd`,
which does NOT carry this override. That window is the vulnerable
one on AWS — a complementary patch in the tools repo is tracked
separately.

### Files

- `core/components/argocd/values.yaml`: add `repoServer.livenessProbe`
  and `repoServer.readinessProbe` blocks.
- `CHANGELOG.md`: v0.17.3 entry.

### Migration

Existing clusters on v0.17.2 pick up the fix on the next
`estabilis promote` (or equivalent platform-root refresh) once bumped
to `v0.17.3`. No destroy of the repo-server Deployment — the
Deployment is patched in place with new probe config on the next
ArgoCD reconcile.

## [0.17.2] - 2026-04-24

### Fixed — MNG `node_group_name_prefix` overflow + Karpenter outputs under `hybrid` mode

Two additional issues surfaced when `terraform apply` was retried on
v0.17.1 against a CAF-style cluster name:

#### 1. `node_group_name_prefix` overflow

The EKS managed-node-group submodule has a second IAM-like name
construction beyond the role name — `aws_eks_node_group.this.node_group_name_prefix`
uses `"${var.name}-"` when `var.use_name_prefix = true` (default). Our
`var.name` for the default MNG is `"${cluster_name}-default"` → prefix
becomes `"${cluster_name}-default-"` (42 chars) → AWS caps at 37:

```
Error: expected length of node_group_name_prefix to be in the range
(0 - 37), got eks-cortex-platform-prd-us-east-1-default-
```

Fix: set `use_name_prefix = false` on the default MNG so the submodule
uses our explicit `name` directly. Complements the `iam_role_use_name_prefix`
fix from v0.17.1.

#### 2. Karpenter outputs go empty under `hybrid`

`outputs.tf` still gated three Karpenter outputs on the strict
`var.autoscaler == "karpenter"` check missed by the v0.17.0 rollout:

- `karpenter_queue_name`
- `karpenter_node_iam_role_name`
- `karpenter_controller_role_arn`

Consequence on a `hybrid` apply: `terraform plan` shows these outputs
flipping to `""` even though the Karpenter module is still provisioned.
Downstream consumers reading them see a false "Karpenter disabled"
signal.

Fix: switch all three to `contains(["karpenter", "hybrid"], var.autoscaler)`.
Matches the pattern already applied to `platform-outputs.tf` in v0.17.0.

### Migration

Operators hitting either error on v0.17.1 `terraform apply`: bump the
module `ref` from `v0.17.1` to `v0.17.2` and re-run `terraform plan`/`apply`.
No other change required.

## [0.17.1] - 2026-04-24

### Fixed — MNG default IAM role name_prefix overflow

The new `autoscaler = "hybrid"` / `autoscaler = "cluster_autoscaler"`
path (introduced in v0.17.0) uses the terraform-aws-modules EKS
managed-node-group submodule, which defaults to
`iam_role_use_name_prefix = true`. The submodule then builds the IAM
role as `"${cluster_name}-${node_group_name}-eks-node-group-"` before
AWS appends its 26-char random suffix. The AWS `name_prefix`
limit is 38 chars.

Our CAF-style cluster names (`eks-{prefix}-platform-{env}-{region}`)
routinely exceed that budget once combined with the submodule's
suffix. First `terraform apply` on AWS with `hybrid` mode fails:

```
Error: expected length of name_prefix to be in the range (1 - 38),
got eks-cortex-platform-prd-us-east-1-default-eks-node-group-
```

Same fix pattern as `module.eks` (v0.15.0) and `module.karpenter`
(v0.15.2): set `iam_role_use_name_prefix = false` to switch to name
mode (64-char budget), and pin `iam_role_name` explicitly so future
additional MNGs get distinct role names without fighting the default.

- `providers/aws/eks.tf`: the `default` MNG now sets
  `iam_role_use_name_prefix = false` and `iam_role_name = "${local.cluster_name}-default-node"`.

### Migration

Operators on v0.17.0 who hit the error during `terraform apply`: bump
the module `ref` from `v0.17.0` to `v0.17.1` and re-run
`terraform plan`/`apply`. No other change required.

Operators already on v0.17.0 who succeeded (unlikely — the MNG can't
exist yet on v0.17.0 without hitting this error unless their cluster
name is very short): the next apply will recreate the IAM role with
a stable name instead of the generated prefix. Acceptable in a fresh
deployment.

## [0.17.0] - 2026-04-24

### Added — `autoscaler = "hybrid"` mode (AWS provider)

Resolves a chicken-and-egg that blocks the ArgoCD seed on an AWS hub:
with `autoscaler = "karpenter"` (the previous default), the cluster
has only Fargate Profiles for `kube-system` + `karpenter` namespaces,
and Karpenter itself only provisions EC2 when its NodePool CR exists.
The NodePool is installed BY ArgoCD as part of platform-root. But
ArgoCD needs a node to run — so it can't start, which means Karpenter
can't be deployed, which means there are no nodes. Deadlock.

The new `hybrid` mode fixes this by provisioning a small always-on
Managed Node Group (MNG) alongside the Karpenter infrastructure:

- **MNG**: 2 permanent EC2 nodes (defaults: `t3a.medium`/`t3.medium`,
  `min_size=2`, `max_size=4`) — hosts platform control-plane
  (ArgoCD, cert-manager, external-secrets, kyverno, ...). Analogous
  to the AKS `platformrg` user pool.
- **Karpenter infra** (IRSA role + SQS queue + Fargate Profile for
  the karpenter namespace): ready to be wired up by platform-root,
  and provisions workload EC2 once NodePool lands.
- **Fargate Profile `kube-system`**: unchanged — still hosts coredns,
  ebs-csi-controller, pod-identity-agent, etc. Analogous to the AKS
  system pool.

The resulting topology mirrors AKS: system-level addons on one pool
(Fargate), platform control-plane on another (MNG), workloads
elastic via Karpenter.

**Default changed** from `autoscaler = "karpenter"` to
`autoscaler = "hybrid"`. Existing Azure clients are unaffected
(variable is AWS-only). The only AWS deployment today (cortex test)
is still in seed and was not moved to production; it will be
re-applied with `hybrid` to unblock the seed.

### Changed — file-level touches

- `variables.tf`: `autoscaler` now accepts `"hybrid"` in addition to
  `"karpenter"`, `"cluster_autoscaler"`, `"none"`. Description
  expanded with the full contract of each mode. Default flipped to
  `"hybrid"`.
- `eks.tf`: the MNG block fires on both `"cluster_autoscaler"` and
  `"hybrid"`; the Karpenter Fargate Profile + node SG Karpenter
  discovery tags fire on both `"karpenter"` and `"hybrid"`. VPC
  subnet Karpenter-discovery tags in existing-VPC mode follow the
  same rule.
- `karpenter.tf`: `module.karpenter` and the IAM `-instance-profile-gc`
  policy fire on both `"karpenter"` and `"hybrid"`.
- `platform-outputs.tf`: `global.karpenterQueueName` / `karpenterNodeRoleName`
  / `karpenterControllerRole` populated on both `"karpenter"` and
  `"hybrid"`.

### Migration guide

Operators on `autoscaler = "karpenter"` who want to adopt `hybrid`:

1. Update `terraform.tfvars`: `autoscaler = "hybrid"`.
2. `terraform plan` — expected: MNG `<cluster>-default` created with
   `min_size=2` nodes; no destroy of existing Karpenter IAM/SQS
   (both modes share those resources).
3. `terraform apply`.
4. No change required on the gitops or CLI side. ArgoCD + platform-root
   seed runs as if it were a fresh install.

Operators on `autoscaler = "karpenter"` who want to stay there: no
change required. Behaviour identical to before.

## [0.16.0] - 2026-04-24

### Added — AWS provider branches in core `platform-root` templates

Five core hub templates previously had `{{- if eq .Values.global.provider "azure" }}`
blocks without a matching AWS branch. When rendered on an AWS hub, the
resulting Applications showed `Synced` in ArgoCD but the underlying
controllers were missing the wiring that makes them functional (IRSA
annotations, provider-agnostic platform-secrets rendering, etc.).

This release closes the gaps so an AWS hub produces a functionally
correct render. The AWS-equivalent of Azure Workload Identity is
wired via IRSA — each ServiceAccount receives
`eks.amazonaws.com/role-arn` instead of
`azure.workload.identity/client-id`. IRSA role ARNs are already
exported by `providers/aws/platform-outputs.tf` as `identity.<component>.roleArn`.

#### `values.yaml` — per-cloud identity fields

`identity.<component>` now carries both `clientId` (Azure WI) and
`roleArn` (AWS IRSA). Templates select the right field via
`.Values.global.provider`. Empty defaults are safe: fields not relevant
to the active cloud are not rendered into parameters.

#### Template changes

- **`cert-manager.yaml`** — AWS branch adds
  `serviceAccount.annotations.eks.amazonaws.com/role-arn` parameter
  from `identity.certManager.roleArn`. Paired with
  `values/platform/cert-manager-aws.yaml` overlay (new in
  estabilis-platform-gitops v0.33.0).

- **`external-secrets.yaml`** — AWS branch adds the same IRSA
  annotation wiring using `identity.externalSecrets.roleArn`. Paired
  with the `external-secrets-aws.yaml` overlay in gitops v0.33.0.

- **`platform-secrets.yaml`** — outer `{{- if azure }}` wrapper
  relaxed to `{{- if or (eq provider azure) (eq provider aws) }}` so
  the chart renders on both clouds. Chart itself is provider-agnostic
  (uses the `ClusterSecretStore` already AWS-aware in
  `cluster-secret-store.yaml`). The Azure-only `acrLoginServer`
  parameter is now gated to Azure explicitly until a provider-neutral
  registry variable lands (Estabilis/estabilis-platform-tools#182).

- **`cnpg.yaml`** — `cnpg-operator` Application already rendered on
  both clouds. `cnpg-cluster` Application is now explicitly gated to
  Azure only on this release because its backup wiring targets Azure
  Blob via managed identity; the AWS equivalent (Barman Cloud against
  S3 via IRSA) is not implemented. Deferred to a follow-up issue under
  Estabilis/estabilis-platform-tools#186.

- **`opencost.yaml`** — no template change this release. The existing
  Azure-specific cost-export env vars are already gated to Azure; on
  AWS the chart renders opencost without cost-export integration
  (cluster-level cost tracking still works). AWS Athena/CUR integration
  is deferred to a dedicated follow-up.

### Changed — default `platformGitopsVersion`

`bootstrap/platform-root/values.yaml` default bumped from `v0.1.0`
(stale placeholder) to `v0.33.0` so standalone renders without
terraform injection pick up the AWS overlays added in
estabilis-platform-gitops v0.33.0.

### Breaking / compatibility

No breaking changes for Azure deployments — existing renders produce
identical manifests. AWS hubs that previously saw `Synced` but
dysfunctional Applications will, on the next ArgoCD refresh, receive
the corrected IRSA wiring and start authenticating against AWS APIs.

### Related

- Tracker: Estabilis/estabilis-platform-tools#186 — AWS provider
  branches in core templates (this release closes the main slice)
- Pair: Estabilis/estabilis-platform-gitops v0.33.0 — overlay files
- Follow-ups deferred: CNPG AWS backup (S3 + Barman Cloud), opencost
  AWS cost-export (Athena/CUR), `acrLoginServer` rename
  (Estabilis/estabilis-platform-tools#182)

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
