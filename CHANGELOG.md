# Changelog

## [0.61.6] - 2026-05-29

### Changed — `hub-egress-ip` Key Vault secret is conditional (no empty string)

`providers/azure/shared.tf` no longer writes `hub-egress-ip = ""`. The secret
is created **only** when a real hub egress IP exists:

- `nat_gateway_enabled = true` → the NAT Gateway public IP, **or**
- new `var.hub_egress_ip_override` (non-empty) → for NVA / FortiGate-VM egress.

In the private/peered topology (no NAT GW, no override) the secret is **absent**.
Workload clusters in that topology register with `apiServerAccess.mode=private`
(estabilis-workload >= v3.1.0 / operator >= v0.8.0) and never read it — which
removes the malformed `"/32"` that the empty value previously produced
downstream.

`allowlist`-topology workloads require this secret populated (NAT GW or override).

### Added

- **`var.hub_egress_ip_override`** — explicit hub egress IP for NVA/FortiGate
  egress (no Azure NAT Gateway).
- **`docs/operations/workload-operator-delivery.md`** — documents the no-CLI
  operator delivery (GitOps Bridge) and the operational prerequisite of
  publishing the operator image + chart to the client ACR (no `estabilis` CLI).

### Fixed

- Corrected the stale `shared.tf` note that claimed `hub-registrar-token` is
  written by the `estabilis` CLI — it is published at runtime by the
  workload operator via Workload Identity (ADR 0010).

## [0.61.5] - 2026-05-28

### Fixed — ingress `$traefikGate` reads `global.traefikInternal` bridge

All 6 ingress templates (argocd, grafana, loki, mimir, hubble-ui,
vault) now include `global.traefikInternal == "true"` in their
`$traefikGate` OR-chain. Previously, when `components.traefik = false`
and `components.traefik-internal` defaulted to `false`, the gate
evaluated to false even though the Terraform bridge correctly
injected `global.traefikInternal = true`. Result: no ingress apps
rendered.

After this fix, an ILB-only cluster (traefik disabled, traefik-internal
enabled via bridge) correctly renders all ingress apps without any
`overrides/platform-root/values.yaml`.

## [0.61.4] - 2026-05-28

### Fixed — complete toString in remaining templates

Applies `| toString` to ALL remaining component gates: opencost,
vault, vault-ingress, karpenter, platform-secrets, grafana-dashboards.
Completes the sweep started in v0.61.2/v0.61.3.

## [0.61.3] - 2026-05-28

### Fixed — ingress templates: toString + bridge gates

Same `toString` fix as v0.61.2 applied to all 5 ingress templates
(argocd, grafana, loki, mimir, hubble-ui). Also adds the
`networkDataplane == cilium-acns` bridge to `hubble-ui-ingress`
gate (was only in `hubble-ui`).

## [0.61.2] - 2026-05-28

### Fixed — `platform-root`: toString in component gate comparisons

Helm `--set` injects booleans but template `eq` fails with
"incompatible types for comparison" when comparing bool to string.
All three component gates now use `| toString` before comparison.

## [0.61.1] - 2026-05-28

### Fixed — `platform-root`: read bridge params for component gates

Three component gates relied on `overrides/platform-root/values.yaml`
instead of consuming Terraform-injected helm parameters:

- **traefik-internal**: now reads `global.traefikInternal` (bridge)
- **traefik**: auto-disables when `global.ingressController != "traefik"`
- **hubble-ui**: auto-enables when `global.networkDataplane == "cilium-acns"`

Eliminates the need for manual `overrides/platform-root/values.yaml` to
toggle these components — Terraform controls everything via the gitops bridge.

## [0.61.0] - 2026-05-28

### Added — `exposures`: auto-derive internal hosts from `internal_domain`

Exposure profiles keyed `internal` now auto-derive their host as
`{app}.{cluster_name}.{internal_domain}` when `var.internal_domain` is set.
All other profile keys (`external`, `push`, etc.) continue using `var.domain`.
Explicit `host` values always win over auto-derivation.

- **Azure**: uses existing `var.internal_domain` (no variable change)
- **AWS**: gains `var.internal_domain` (default `""`, no-op when unset)

Usage example in `terraform.tfvars`:

```hcl
domain          = "example.dev"
internal_domain = "azure.example.dev"

grafana_exposures = {
  external = { enabled = true, ingress_class = "traefik-internal" }
  internal = { enabled = true, ingress_class = "traefik-internal" }
}
# external → grafana.{cluster}.example.dev
# internal → grafana.{cluster}.azure.example.dev
```

## [0.60.2] - 2026-05-27

### Fixed — `azure`: ACR network_rule_set + SP tags perpetual drift

- **ACR `network_rule_set`**: replaced attribute assignment (`= []`) with `dynamic` block. When conditions are false (private endpoint enabled, firewall off, or non-Premium SKU), the block is omitted entirely. Azure API always returns a default `Allow` ruleset; setting `[]` caused perpetual plan diff.
- **ACR push SP tags**: added `local.base_name` to `azuread_service_principal.acr_push_azdo` tags, aligning with the `azuread_application` which already includes it. The missing tag caused Terraform to remove the deployment-specific identifier on every apply.

## [0.60.0] - 2026-05-27

### Added — `traefik`: migrate values to gitops + fix platform-root override + fix namespace

Three changes shipped together:

1. **platform-root override loading**: `upstart.yaml` now includes `$overrides/overrides/platform-root/values.yaml` in the platform-root Application's valueFiles. Downstream config repos can now toggle `components.*` (traefik, traefik-internal, etc.) via override — previously silently ignored.
2. **traefik-internal namespace fix**: destination namespace changed from `traefik-internal` to `traefik`. `releaseName: traefik-internal` already isolates k8s resources; the separate namespace broke AppProject destinations and was not pre-created by upstart.
3. **traefik values migrated to gitops**: `$values` ref in traefik.yaml and traefik-internal.yaml switched from `platformRepoUrl`/`platformVersion` to `platformGitopsRepoUrl`/`platformGitopsVersion`. Value files now at `values/platform/traefik*.yaml` in estabilis-platform-gitops (v0.40.0+). Old `core/components/traefik/` and `core/components/traefik-internal/` deleted. `ignoreMissingValueFiles: true` set unconditionally (vault pattern).

**Requires**: estabilis-platform-gitops v0.40.0 tagged first (values must exist before templates reference them).

## [0.59.2] - 2026-05-27

### Added — `azure`: ConfigMap missing keys

Adds 8 keys to the `platform-infrastructure` ConfigMap that Terraform already knows but were not published:

- `global.internalDomain` — internal DNS domain for dual-FQDN Ingress (VNet-scoped access)
- `global.privateFqdn` — AKS API server private FQDN (cross-cluster kubectl, ArgoCD cluster registration)
- `global.nodeResourceGroup` — MC_ RG for Velero disk snapshots and node troubleshooting
- `global.kubernetesVersion` — effective K8s version (may differ from requested during upgrade)
- `global.containerRegistryName` — provider-agnostic registry name (complements existing `acrLoginServer`)
- `global.tfstateStorageAccountName` — tfstate SA for downstream workload cluster data sources
- `global.logAnalyticsWorkspaceId` — ARM ID for workload diagnostic settings
- `global.logAnalyticsWorkspaceName` — LAW name for queries and troubleshooting

All keys are additive with proper conditional guards (`acr_enabled`, `diagnostics_enabled`).

## [0.59.1] - 2026-05-27

### Added — `azure`: hub-cluster bridge annotations (ADR 0023 Etapa B parity)

Adds 5 annotations to the `hub-cluster` Secret that the AWS provider already publishes, enabling client ApplicationSets to inject cluster-level metadata as helm parameters:

- `bridge.region` — Azure region (`var.location`)
- `bridge.cluster-name` — `{name_prefix}-{deployment_id}`, used to compose app FQDNs
- `bridge.domain` — DNS zone root, used to compose app FQDNs
- `bridge.tier` — normalized environment (`prd`/`prod` → `"production"`, others keep name)
- `bridge.secret-path-template` — Vault path template for ExternalSecret resolution (empty when `vault_enabled = false`, fail-loud)
- `bridge.hub-secrets-path-prefix` — shared hub secrets path in HashiCorp Vault for workload-operator (empty when `vault_enabled = false`)
- `bridge.internal-domain` — internal DNS domain for dual-FQDN Ingress

The `bridge_tier`, `bridge_secret_path_template`, and `shared_hub_secrets_prefix_effective` locals replicate the exact AWS logic — provider-agnostic, not Azure-specific.

New variables:
- `shared_hub_secrets_prefix` (string, default `""`) — customizable Vault path prefix, defaults to `estabilis/shared/{name_prefix}`
- `internal_domain` (string, default `""`) — internal DNS domain for VNet-scoped access

- `bridge.ingress-group-name` — empty string (ALB concept, no Azure equivalent; keeps interface symmetry with AWS)

## [0.59.0] - 2026-05-27

### Changed — `azure`: bump kubernetes provider v2 → v3

Upgrades `hashicorp/kubernetes` from `~> 2.37` to `~> 3.1`, renaming all resource types to the `_v1` suffix required by v3. Four `moved` blocks ensure zero-downtime migration (no destroy+recreate) for existing deployments:

- `kubernetes_namespace.argocd` → `kubernetes_namespace_v1.argocd`
- `kubernetes_config_map.platform_infrastructure` → `kubernetes_config_map_v1.platform_infrastructure`
- `kubernetes_secret.platform_infrastructure` → `kubernetes_secret_v1.platform_infrastructure`
- `kubernetes_secret.hub_cluster` → `kubernetes_secret_v1.hub_cluster`

The `moved` blocks can be removed after all deployments have applied at least once with v0.59.0+.

### Added — `azure`: ConfigMap parity with AWS (ADR 0020 revision tracking)

Brings the Azure `platform-infrastructure` ConfigMap to parity with AWS by adding revision tracking keys and infrastructure signals consumed by downstream GitOps:

**Revision tracking (ADR 0020):**
- `platformRevision` — enables branch tracking; falls back to `platformVersion` → VERSION file
- `configRepoRevision` — falls back to `configRepoVersion`
- `clientGitopsRepoVersion` / `clientGitopsRepoRevision` — client GitOps repo pinning

**Infrastructure signals:**
- `global.region` — Azure region (`var.location`)
- `global.oidcIssuerUrl` — AKS OIDC issuer URL for workload identity federation
- `global.ingressController` — derived from `traefik_enabled` / `traefik_internal_enabled` toggles
- `global.traefikInternal` — explicit flag for internal Traefik instance
- `global.slackAlertingEnabled` — Mimir Alertmanager Slack pipeline gate

**New variables (all with backwards-compatible defaults):**
- `platform_revision` (string, default `""`)
- `config_repo_revision` (string, default `""`)
- `client_gitops_repo_version` (string, default `""`)
- `client_gitops_repo_revision` (string, default `""`)
- `slack_alerting_enabled` (bool, default `false`)

## [0.58.1] - 2026-05-26

### Fixed — `azure/aks`: UAMI missing Network Contributor on VNet

The UAMI introduced in v0.58.0 had `Private DNS Zone Contributor` on the PDZ but lacked `Network Contributor` on the VNet. AKS needs `virtualNetworks/join/action` to create the vnet_link from VNet to external PDZ. Also adds `depends_on` for both UAMI role assignments to ensure propagation before cluster creation.

### Added — `azure/aks`: `outbound_type` variable

New variable `outbound_type` (string, default `""`) allows explicit control over AKS egress type. Supports `"userDefinedRouting"` for NVA/FortiGate deployments where egress is via UDR `0.0.0.0/0 → NVA`, avoiding the unnecessary PIP + Load Balancer that Azure creates in the MC_ RG with `loadBalancer` mode.

When empty (default): auto-detects from `nat_gateway_enabled` (current behavior preserved).

## [0.58.0] - 2026-05-26

### Added — `azure/aks`: auto-create UAMI when private_dns_zone_id is external

When `private_dns_zone_id` is an ARM resource ID (not `"System"` or `"None"`), AKS with `SystemAssigned` identity cannot write A records to Private DNS Zones outside the `MC_*` shadow RG. The module now automatically:

1. Creates a User Assigned Managed Identity (`mi-{base_name}-aks`)
2. Assigns `Private DNS Zone Contributor` on the target PDZ
3. Switches the AKS `identity` block from `SystemAssigned` to `UserAssigned`
4. Updates the `Network Contributor` role assignment to use the UAMI principal

**No new variables.** The trigger is implicit — `local.use_uami` evaluates to `true` when `enable_private_cluster = true` and `private_dns_zone_id` is not `"System"`, `"None"`, or empty.

**Backward compatibility.** All defaults preserve v0.57.0 behavior. `private_dns_zone_id = "System"` (default) keeps `SystemAssigned` identity.

**Migration note.** Switching an existing cluster from `SystemAssigned + "System"` to `UserAssigned + external PDZ` **recreates the AKS cluster** (identity type change is a force-new). Plan a maintenance window.

## [0.57.0] - 2026-05-26

### Added — `azure`: external Private DNS Zone support for hub-spoke topologies

Three new variables allow consumers to pass ARM IDs of centralized hub PDZs instead of the module creating local ones:

- `external_pdz_blob_id` — `privatelink.blob.core.windows.net`
- `external_pdz_acr_id` — `privatelink.azurecr.io`
- `external_pdz_vaultcore_id` — `privatelink.vaultcore.azure.net`

**Why.** Hub-spoke architectures (CAF) centralize Private DNS Zones in a connectivity subscription and link all spoke VNets to them. When the platform module also creates its own local PDZs for the same namespaces, Azure rejects the second `vnet_link` with _"A virtual network cannot be linked to multiple zones with overlapping namespaces."_ This was blocking PE adoption for any client already using hub canonical PDZs.

**Behavior.** When any `external_pdz_*_id` is set, the module skips creating the corresponding local PDZ + vnet_link and uses the external ID in all PE `dns_zone_groups`. When empty (default), behavior is identical to v0.56.0 — local PDZs are created as before.

**Migration note.** Existing deployments switching from local to external PDZs will see a destroy of local PDZ resources + in-place update of PE dns_zone_groups. Brief DNS resolution gap during apply — plan a maintenance window or pre-create hub vnet_links before flipping.

## [0.56.0] - 2026-05-26

### Added — `azure`: Private Endpoint toggles for Key Vaults and Storage Accounts

Two new opt-in variables gate PE creation, PDZ + vnet_link, and `public_network_access_enabled = false` on all firewalled resources:

- `keyvault_private_endpoint_enabled` (`bool`, default `false`) — covers KV platform + KV hub. Creates PDZ `privatelink.vaultcore.azure.net` shared between both KVs.
- `storage_private_endpoint_enabled` (`bool`, default `false`) — covers SA tfstate, cnpg, velero, observability, cost-exports. Reuses existing PDZ `privatelink.blob.core.windows.net`.

When enabled, firewall rules (`network_acls` / `network_rules`) are removed (mutually exclusive with PE-only). When disabled (default), behavior is identical to v0.55.0.

**SA observability** was previously hardcoded PE-only; now gated by the toggle — gets `network_rules { default_action = "Deny" }` when PE is off.

**SA cost-exports** was previously a PE + firewall hybrid (the Allow→Deny dance for Cost Management export creation); when PE is enabled, the SA goes PE-only — Cost Management uses trusted services bypass (`AzureServices`).

### Added — `azure`: diagnostic settings for Key Vaults, Storage Accounts, and ACR

Previously only AKS had a `azurerm_monitor_diagnostic_setting`. Now all firewalled resources send logs to the local LAW:

| Resource | Log categories | Metrics |
|---|---|---|
| KV platform, KV hub | `AuditEvent`, `AzurePolicyEvaluationDetails` | `AllMetrics` |
| SA tfstate, observability, cnpg, velero, cost-exports (blob service) | `StorageRead`, `StorageWrite`, `StorageDelete` | `Transaction` |
| ACR | `ContainerRegistryRepositoryEvents`, `ContainerRegistryLoginEvents` | — |

All gated by `diagnostics_enabled` (default `true`) + resource-specific toggles (`acr_enabled`, `shared_hub_kv_enabled`, `cost_export_enabled`).

### Added — `azure`: optional external Log Analytics Workspace

New variable `external_log_analytics_workspace_id` (string, default `""`) sends logs to an external LAW **in parallel** with the local LAW. Each resource gets a second `azurerm_monitor_diagnostic_setting` with `-external` suffix. The external diag settings are independent of `diagnostics_enabled` — setting only the external LAW ID (with `diagnostics_enabled = false`) creates external-only diagnostic settings without provisioning a local LAW.

### Added — outputs: `log_analytics_workspace_id`, `log_analytics_workspace_name`

Exposes the local LAW ARM ID and name (null when `diagnostics_enabled = false`).

## [0.55.0] - 2026-05-22

### Added — `azure/aks`: AKS Private Cluster support (opt-in)

Three new variables enable AKS private cluster mode where the API server is reachable only via a Private Endpoint inside the VNet:

- `enable_private_cluster` (`bool`, default `false`)
- `private_dns_zone_id` (`string`, default `"System"`)
- `private_cluster_public_fqdn_enabled` (`bool`, default `false`)

**Why.** Hub-spoke topologies with an external NVA (FortiGate, Palo Alto, etc.) cannot reliably whitelist the AKS egress SNAT IP in `authorized_ip_ranges` — the NVA's public IP can change on destroy/recreate, and on every change the operator has to update every downstream `authorized_ip_ranges`. Private cluster sidesteps the problem: `kubelet → API server` traverses the Private Endpoint intra-VNet, so the egress IP is irrelevant.

**Behavior matrix:**

| `enable_private_cluster` | API server | `authorized_ip_ranges` | `private_dns_zone_id` |
|---|---|---|---|
| `false` (default) | Public | Applied | Ignored |
| `true` | Private (PE only) | Ignored (Azure rejects both) | Applied |

When `enable_private_cluster = true`:
- `azurerm_kubernetes_cluster.platform` receives `private_cluster_enabled = true` plus `private_dns_zone_id` (either `"System"` for AKS-managed PDZ in the `MC_<rg>` shadow RG, or the ARM ID of an external canonical PDZ in a hub network).
- `api_server_access_profile` becomes a `dynamic` block that emits **zero blocks** (Azure rejects `authorized_ip_ranges` together with `private_cluster_enabled`).
- Optional `private_cluster_public_fqdn_enabled` exposes an additional DNS-only public FQDN (no traffic) for troubleshooting via Azure Portal.

**Backward compatibility.** All defaults preserve v0.54.x behavior (public cluster + `authorized_ip_ranges`). Existing downstreams (Cortex AWS, etc.) are unaffected — no plan diff on terraform apply.

**Outputs added:**
- `aks_private_fqdn` — private FQDN string, empty when `enable_private_cluster = false`.
- `aks_private_cluster_enabled` — bool flag mirroring the variable.

### Added — `platform-root`: parametrize external-secrets chart version + installCRDs

Two values previously hardcoded in `bootstrap/platform-root/templates/external-secrets.yaml` are now configurable via Helm values:

- `externalSecrets.chartVersion` (default `"2.1.0"`)
- `externalSecrets.installCRDs` (default `false`)

**Why.** When the upstream chart updates the manifest schema (e.g. `nullBytePolicy` field introduced in 2.2.x), downstream environments tied to the older 2.1.0 CRD enter `ComparisonError`. Operators previously had to fork the platform repo to bump the chart; now a single value override solves it. Symptom observed on cortex-prd 2026-05-20.

## [0.54.1] - 2026-05-20

### Fixed — `alloy`: enable clustering on `alloy_self` scrape job

The `prometheus.scrape "alloy_self"` block in `core/components/grafana-stack/alloy-values.yaml` was the only one of 27 `prometheus.scrape` jobs in the upstream Alloy config that did not carry a `clustering { enabled = true }` block. That gap predates the bulk clustering fix shipped in v0.37.0 (commit d0d2843, March 2026) — `alloy_self` was never included in the original migration.

**Symptom.** `discovery.relabel "alloy_self"` reads from `discovery.kubernetes.grafana_ns.targets` and keeps every pod with label `app.kubernetes.io/name=alloy`. On a multi-node cluster the DaemonSet has one Alloy pod per node; without clustering, every Alloy pod independently discovers and scrapes every other Alloy pod's `/metrics`. That produces N copies of each Alloy-internal series (`prometheus_target_interval_length_seconds`, `alloy_build_info`, etc.) with identical labels and very close timestamps. Mimir's distributor accepts the first sample and rejects the remaining N-1 with `err-mimir-sample-out-of-order` (HTTP 400).

Observed on a 4-node production deployment: ~2 000 samples/min rejected steadily, alloy logging `non-recoverable error` from `prometheus.remote_write.mimir` on every batch.

**Fix.** Add the standard clustering block to the scrape job. Alloy's built-in hash ring then assigns each discovered target to exactly one Alloy instance, eliminating the duplication.

```hcl
prometheus.scrape "alloy_self" {
  targets    = discovery.relabel.alloy_self.output
  forward_to = [prometheus.relabel.alloy_self.receiver]
  clustering {
    enabled = true
  }
}
```

No schema change, no breaking change. After the next ConfigMap roll, Alloy applies clustering automatically (no pod restart required — Alloy hot-reloads `config.alloy`).

**Verification post-deploy.** The Mimir distributor metric `cortex_distributor_samples_in_total{status="rejected", reason="sample-out-of-order"}` should drop. Alloy's `non-recoverable error` log lines from `prometheus.remote_write.mimir` should stop. Per-Alloy-pod `prometheus_target_sync_length_seconds` for `job="alloy_self"` will show only a SHARD of the discovered targets being scraped (instead of all of them).

## [0.54.0] - 2026-05-18

### Added — Terraform-managed ALB Controller webhook TLS (opt-in)

New tfvar `alb_controller_webhook_tls_managed_by` (default `"chart"`, opt-in `"terraform"`) controls how the aws-load-balancer-controller webhook TLS cert is provisioned.

**Why.** The `eks-charts/aws-load-balancer-controller` chart auto-generates the webhook TLS cert via the Helm `genSignedCert` helper. The helper is non-deterministic — each render produces a new cert. Combined with the chart's Deployment template lacking a `checksum/secret` annotation, this creates a race: after a re-sync, the chart updates the Secret + the MutatingWebhookConfiguration CABundle, but the ALB Controller pods keep serving the previous cert from memory. The API server validates the webhook against the new CABundle while the pod responds with the old cert, producing `x509: certificate signed by unknown authority` errors that block every Service creation in the cluster.

Observed in production during bootstrap of `eks-cortex-platform-hml-us-east-1` on 2026-05-15. Manual workaround: `kubectl rollout restart deployment/aws-load-balancer-controller -n aws-load-balancer-controller`.

**Fix.** When `alb_controller_webhook_tls_managed_by = "terraform"`, the module generates a stable CA (10-year validity) and webhook cert (5-year validity) via the `tls` provider, then passes them to the chart through `webhookTLS.{caCert,cert,key}` helm values. The chart's `webhookCerts` helper takes the operator-provided values branch and skips `genSignedCert` entirely — no regen on re-renders, no race.

**Backward compat.** Default remains `"chart"` (existing behavior). Existing deployments stay unchanged unless the operator explicitly opts in. Default render is byte-identical to v0.53.3 for any cluster that doesn't set the new tfvar.

### Migration path for existing deployments

> **Brief migration window — plan for ~30s of webhook errors.** Between step 4 (ArgoCD syncs the chart re-render that now carries the TF-provided cert) and step 5 (rollout restart loads the new cert into pod memory), the cluster has the new CABundle on the webhook config but the old cert in the running pods. Service creations in that window will fail with `x509: certificate signed by unknown authority` until the rollout completes. Run steps 4–5 back-to-back. After this one-time migration, the feature eliminates the race permanently.

Per-deployment, when ready:

1. Edit `terraform.tfvars`: add `alb_controller_webhook_tls_managed_by = "terraform"`.
2. `terraform apply` — creates 4 new TLS resources and populates 3 new keys (`albControllerWebhookTLS.{caCert,cert,key}`) on Secret `platform-infrastructure-sensitive`.
3. `estabilis promote` (or manual re-resolve+apply of platform-root) so ArgoCD picks up the new `helm.parameters`.
4. Watch ArgoCD reconcile the ALB Controller Application — when the chart re-renders, the rendered Secret `aws-load-balancer-tls` and webhook `caBundle` carry the new TF-provided values. With `webhookTLS` set, the Application drops the `ignoreDifferences` entries that previously blocked these fields, so ArgoCD pushes them to the cluster.
5. Immediately run `kubectl rollout restart deployment/aws-load-balancer-controller -n aws-load-balancer-controller` to load the new cert into the running pods.
6. Verify with `kubectl get pod -n aws-load-balancer-controller` (all `1/1 Ready`) and a sanity `kubectl create service clusterip dummy --tcp=80:80` in a temp namespace — should succeed without webhook errors.

For **fresh clusters** bootstrapped with `alb_controller_webhook_tls_managed_by = "terraform"` from the start, there is no migration window — the TF cert is in place before pods come up.

### Files changed

- `providers/aws/alb-controller-webhook-tls.tf` — NEW, conditional CA + webhook cert resources gated on the new tfvar.
- `providers/aws/variables.tf` — declared `alb_controller_webhook_tls_managed_by` with detailed description + validation.
- `providers/aws/platform-outputs.tf` — conditional injection of `albControllerWebhookTLS.*` keys into `platform-infrastructure-sensitive`.
- `bootstrap/platform-root/templates/aws-load-balancer-controller.yaml` — conditional `webhookTLS` block in `valuesObject` when keys are present.
- `providers/aws/terraform.tfvars.example` — documented opt-in syntax.

### Out-of-scope (future work — separate ADR)

Migration to `cert-manager.io/Certificate` with cert-manager CAInjector. That removes the manual rotation but requires wave reordering (cert-manager must run before ALB Controller; today it runs after).

## [0.53.12] - 2026-05-18

### Fixed

- `bootstrap/platform-root/templates/`: four Application templates were out of compliance with [ADR 0029 — Auto-prune policy](https://github.com/Estabilis/estabilis-platform-tools/blob/main/docs/adr/0029-auto-prune-policy.md). All four emit only CR instances or Kubernetes-native resources consumed by other operators — Safe class per ADR 0029. Added `automated.{prune,selfHeal}: true`:
  - `custom-apps.yaml` — generic AppSet that renders client custom Applications (`app-<name>`).
  - `grafana-dashboards.yaml` — ConfigMap dashboards consumed by Grafana sidecar.
  - `kube-state-metrics.yaml` — Deployment + Service emitting metrics scraped by Alloy.
  - `kyverno-exceptions.yaml` — PolicyException CRs + namespace labels.

  Behavioral impact: gate flips and template cleanups in these four Apps now reconcile orphan resources automatically. `selfHeal: true` reverts out-of-band `kubectl patch` operations — operators with active incident debugging should be aware.

- `bootstrap/platform-root/values.yaml`: advance default `platformGitopsVersion` from `v0.39.13` to `v0.39.14`. Carries the parallel ADR 0029 compliance fixes in `estabilis-platform-gitops/workload-bootstrap/templates/` (Estabilis/estabilis-platform-gitops#45): six ApplicationSet templates (`hubble-ui`, `kube-state-metrics`, `kyverno-exceptions`, `kyverno-policies`, `network-policies`, `resource-quotas`) now emit `automated.{prune,selfHeal}: true` for workload clusters.

## [0.53.11] - 2026-05-17

### Fixed

- `spec/upstart/upstart.yaml`: two bootstrap-spec fixes surfaced by the cortex hml audit 2026-05-17.
  - Wave 8 "Networking & Ingress": swap order so `external-dns-config` syncs **before** `external-dns`. The config app renders the `external-dns-cloudflare-config` Secret (hub path: direct from `cloudflareApiToken`; workload path: ExternalSecret from AWS SM) that the `external-dns` pod mounts as `CF_API_TOKEN` env var with `Optional: false`. In manual sequential bootstrap, syncing `external-dns` first leaves the pod in `CreateContainerConfigError` until `external-dns-config` catches up. Auto-sync clusters converge via retry (both Apps are sync-wave 7 in the chart) but manual runs hit the symptom every time.
  - Wave 10 "Post-Deploy": remove `loki-ingress` (kept only in the AWS overlay `Ingresses` wave). Was duplicated across base + overlay, causing a no-op double-sync.

## [0.53.10] - 2026-05-17

### Fixed

- `core/components/grafana-stack/mimir-values.yaml`: promote cortex prd ingester override into upstream defaults. The chart's stock `512Mi` memory limit was insufficient for the WAL replay on restart — with hundreds of segments accumulated, the ingester OOMKills mid-replay before `/ready` returns 200 and the Mimir Application stays at `Synced/Progressing` indefinitely. cortex prd documented this on 2026-05-01 (corrupted WAL → split-brain → forced node drain); cortex hml reproduced the same failure 2026-05-17. Promoted defaults: `replicas: 2`, `requests.memory: 384Mi`, `limits.cpu: 500m`, `limits.memory: 2Gi`, `topologySpreadConstraints` with `whenUnsatisfiable: DoNotSchedule` (prevents bin-pack of both replicas onto the same node, preserving HA). The grafana namespace ResourceQuota in `estabilis-platform-gitops` already accommodates this (`limits.memory: 32Gi`, 18.9Gi free on a typical cluster). Total ingester budget rises from 512Mi to 4Gi (2 replicas × 2Gi).

## [0.53.9] - 2026-05-17

### Fixed

- `core/components/argocd/values.yaml`: promote HML override values into the upstream defaults. Two-part change: (1) **resources** bumped to sizes that match a `~40-Application platform-root` deployment (avoids the chart's stock floors that OOMKill the controller/repo-server under that workload — observed live multiple times); (2) **HA baseline**: `replicas: 2` + `pdb.minAvailable: 1` on every multi-replica component (`server`, `controller`, `repoServer`, `applicationSet`). Single-replica chart components (`redis`, `dex`, `notifications`) intentionally remain without PDB to preserve drainability — a Deployment of 1 replica with `minAvailable: 1` makes the pod voluntarily-undisruptable (drain, Karpenter consolidation, and node upgrades block forever waiting for a second replica that never exists). Requires `estabilis-platform-gitops >= v0.39.13` for the argocd ResourceQuota `limits.memory: 32Gi`; default `platformGitopsVersion` is already at `v0.39.13` from v0.53.8. Total peak memory request with the new defaults is ~19Gi, well within the 32Gi cap.

## [0.53.8] - 2026-05-17

### Fixed

- `bootstrap/platform-root/values.yaml`: advance default `platformGitopsVersion` from `v0.39.12` to `v0.39.13`. Carries the argocd namespace ResourceQuota bump (Estabilis/estabilis-platform-gitops#44): `limits.memory: 16Gi → 32Gi`. The 16Gi cap was sized for a single-replica control plane; operators following the HA baseline (`controller.replicas: 2`) saw `application-controller-1` blocked indefinitely on `exceeded quota`, with sharding silently breaking reconcile (cluster assigned to a shard whose pod doesn't exist). Observed on cortex HML: 18h of `platform-root` `OutOfSync` with no actionable error anywhere. The 32Gi default now accommodates HA with headroom.

## [0.53.7] - 2026-05-15

### Fixed

- `bootstrap/platform-root/values.yaml`: advance default `platformGitopsVersion` from `v0.39.11` to `v0.39.12`. Carries the second Karpenter NodePool refinement (Estabilis/estabilis-platform-gitops#43): adds `karpenter.k8s.aws/instance-memory Gt 4096` (MiB) requirement. Combined with the `instance-cpu Gt 1` from v0.39.11, the default NodePool now guarantees any provisioned node has `≥ 2 vCPU AND > 4 GiB raw memory` (i.e., `xlarge+` minimum). Eliminates the "node slowly tightens as DaemonSets accumulate post-provisioning" failure mode observed on cortex HML 2026-05-15. Clusters consuming this release see Karpenter mark all `*.large` nodes as `Drifted` and replace them with `xlarge+` over the next disruption budget cycles.

## [0.53.6] - 2026-05-15

### Fixed

- `bootstrap/platform-root/values.yaml`: advance default `platformGitopsVersion` from `v0.39.3` to `v0.39.11`. The default had been pinned to a stale gitops release for 8 patch versions while every cluster operator wrote a downstream `overrides/platform-root/values.yaml` override to consume newer releases — duplicating the decision across clients and producing fragmentation. Most consequential improvement carried in: `components/karpenter-resources` NodePool defaults (Estabilis/estabilis-platform-gitops#42), which replaces the broken `instance-size: [medium, large, xlarge]` constraint with `instance-cpu Gt 1` (excludes mediums that have 8 max-pods under AWS VPC CNI without Prefix Delegation), sets `consolidationPolicy: WhenEmpty` and `consolidateAfter: 5m` (mitigates v1.3+ SpotToSpotConsolidation thrashing). Clients consuming this release of `estabilis-platform` can drop their redundant `platformGitopsVersion` override in `overrides/platform-root/values.yaml`.

## [0.53.5] - 2026-05-15

### Fixed

- `platform-secrets`: emit `nullBytePolicy: Ignore` explicitly in all 10 `remoteRef` blocks across 6 ExternalSecret templates (`acr.yaml`, `argocd.yaml`, `argocd-redis.yaml`, `cnpg.yaml`, `grafana.yaml`, `opencost.yaml`). The `externalsecrets.external-secrets.io/v1` CRD has `default: Ignore` on this field, which the API server materializes into the live state. Chart omitting the field produced permanent drift (`OutOfSync`) in every consumer.

## [0.53.4] - 2026-05-15

### Fixed — opencost default flipped to `false` (was producing Degraded state without CUR)

`bootstrap/platform-root/values.yaml` had `opencost: true` as default, but opencost **requires AWS CUR (Cost and Usage Reports) + Athena integration** to produce meaningful data. CUR is provisioned via terraform's `cost_export_enabled` tfvar (opt-in, default false). Clusters that didn't enable CUR were getting opencost deployed but with ExternalSecrets (`opencost-cloud-service-key`, `opencost-cloud-integration`) pointing to AWS Secrets Manager paths that terraform never created — resulting in permanent `Synced/Degraded` state.

Observed during HML bootstrap on 2026-05-15.

### Fix

Four coordinated changes:

1. **`bootstrap/platform-root/values.yaml`**: `opencost: true` → `opencost: false`. Updated comment to clarify the CUR dependency and the opt-in path.

2. **`bootstrap/platform-root/templates/opencost.yaml`**: gate on BOTH `components.opencost != false` AND `global.curBucketName != ""`. Even if the operator explicitly opts in, the chart skips opencost when CUR isn't provisioned — defense in depth against half-configured opencost. Azure naturally skips because `global.curBucketName` is AWS-only.

3. **`bootstrap/platform-root/templates/platform-secrets.yaml`**: updated `opencostEnabled` parameter to use the same precondition. Prevents the platform-secrets chart from creating opencost-related ExternalSecrets when the upstream AWS Secrets Manager entries don't exist.

4. **Grafana dashboards** (`bootstrap/platform-root/templates/grafana-dashboards.yaml` + `core/components/grafana-dashboards/{values.yaml,templates/dashboards.yaml}`): propagated the same precondition as an `opencostEnabled` helm parameter to the grafana-dashboards chart, and gated the `opencost-overview` and `opencost-namespace` dashboard ConfigMaps on that flag. Operator no longer sees empty OpenCost dashboards on clusters where the feature is off.

### Migration

For clusters that DO want opencost AND have CUR configured:

```yaml
# overrides/platform-root/values.yaml
components:
  opencost: true   # opt-in explicit
```

Plus ensure in `terraform.tfvars`:

```hcl
cost_export_enabled = true
```

For clusters that DON'T have CUR: no action needed. opencost was producing Degraded state before; now it cleanly doesn't render. Operator dashboards get cleaner.

### Risk + backward compat

This is a behavior change for clusters relying on the previous default. Specifically: clusters that had `cost_export_enabled = true` in terraform AND no explicit `components.opencost` in their override file will lose opencost after this bump. Such clusters must add `components.opencost: true` explicitly to their override file before bumping.

Estabilis-managed deployments audited (HML, cortex-prd): both have explicit `components.opencost: false` in their override files. Zero regression expected for these. Audit other clusters before bumping.

Refs: HML troubleshooting session 2026-05-15.

## [0.53.3] - 2026-05-15

### Fixed — remaining null emissions on node-exporter + trivy-operator

Follow-up to v0.53.2. The previous release wrapped `tolerations:` and `parameters:` emissions in the scheduling helpers + 3 templates, but a post-deploy audit on AWS caught two outer-level null cases the first pass missed:

- `bootstrap/platform-root/templates/node-exporter.yaml` emitted bare `valuesObject:` followed only by the now-guarded `schedulingTolerationsOnly` include. On AWS the include returns empty, so `valuesObject:` itself rendered as `null`. (Pre-v0.53.2 the same line rendered `valuesObject.tolerations: null` — the v0.53.2 fix collapsed the null one level up.)
- `bootstrap/platform-root/templates/trivy-operator.yaml` emitted bare `scanJobTolerations:` directly from `schedulingTolerations`, same pattern as the kyverno `crds.migration` / `webhooksCleanup` direct usages fixed in v0.53.2.

### Fix

- **node-exporter**: hoist the toleration include into `$nodeExporterTolerations`, then wrap the whole `valuesObject:` key in `{{- if $value | trim }}`. valuesObject is now only emitted when the provider actually contributes a toleration.
- **trivy-operator**: same `{{- if $trivyScanTolerations | trim }}` guard around `scanJobTolerations:`. `scanJobAffinity:` stays unguarded — `schedulingAffinity` always returns content.

### Validation

Full audit via `yaml.safe_load_all` after fix:

| Render | After v0.53.2 | After v0.53.3 |
|---|---|---|
| AWS — null-valued keys (any field) | 2 (valuesObject@node-exporter, scanJobTolerations@trivy-operator) | **0** |
| Azure — null-valued keys (any field) | 0 | 0 |
| Azure — `scalesetpriority` toleration occurrences | 48 | 48 (incl. `scanJobTolerations`) |

`helm lint` passes for both providers.

### Lessons

v0.53.2's audit grep was scoped to `tolerations:` / `parameters:` literal bare lines. That missed `valuesObject:` going null when the only content was an unconditional include that itself became conditional in the same release. The post-fix audit now scans ALL null-valued keys in the rendered YAML tree via `yaml.safe_load_all`, not literal-line patterns. Worth adopting as the standard check on any future Helm-template drift work.

Refs ADR 0012, v0.53.2 ([#167](https://github.com/Estabilis/estabilis-platform/pull/167)), [#168](https://github.com/Estabilis/estabilis-platform/pull/168).

## [0.53.2] - 2026-05-15

### Fixed — chart drift on platform-root (`tolerations`/`parameters` null)

Three helpers in `bootstrap/platform-root/templates/_helpers.tpl` (`schedulingValuesFor`, `schedulingValuesTopLevel`, `schedulingTolerationsOnly`) and two direct usages in `kyverno.yaml` (`crds.migration` + `webhooksCleanup`) emitted the `tolerations:` key unconditionally, relying on the include result. When the include returns empty (AWS provider — Azure spot toleration N/A), the rendered output became `tolerations:` with no value, parsed as `tolerations: null` by YAML.

The K8s API server normalizes `tolerations: null` to "field absent". ArgoCD then re-renders the chart from Git, sees `null`, compares to cluster state (absent), and reports OutOfSync **permanently**. Functionally harmless (no tolerations = scheduling everywhere allowed) but blocks auto-sync convergence (infinite drift loop) and pollutes audit dashboards.

Same pattern affected `parameters:` emission in three templates:

- `network-policies.yaml` + `resource-quotas.yaml` — unguarded `parameters:` followed by `provenanceParameters` include; emits `parameters: null` when `global.provenance.gitRevision` is empty (typical local-render and ad-hoc operator-run cases).
- `opencost.yaml` — bare `parameters:` followed by an `{{- if eq .Values.global.provider "azure" }}` block; on AWS the `if` returns empty, yielding `parameters: null`.

### Fix

- Helpers + kyverno direct usages: wrapped each emission in `{{- if $tolerations | trim }}` guard.
- `network-policies.yaml` / `resource-quotas.yaml`: replaced the unguarded `parameters:` + `provenanceParameters` include with the already-guarded `provenanceParametersBlock` helper.
- `opencost.yaml`: hoisted the existing `if eq provider azure` guard up one level so it also wraps the `parameters:` key.

### Validation

Helm template against minimum-required values for both providers:

| Render | Before | After |
|---|---|---|
| AWS, no provenance set | 53 `tolerations: null` + 3 `parameters: null` | **0 / 0** |
| Azure, no provenance set | n/a | 0 / 0 + 48 `kubernetes.azure.com/scalesetpriority` still emitted on the expected paths |
| AWS, with provenance set | n/a | 0 / 0 + 30 populated `parameters` lists, `gitRevision` emitted 23× |

- `helm lint` passes for both providers.
- YAML parses cleanly via `yaml.safe_load_all` (48 docs / 41 Applications on AWS; 42 / 35 on Azure).
- Diff vs `main` contains only the targeted removals — no functional change.

### Operational impact

After deploying `v0.53.2` via `estabilis promote` (Azure) or the manual platform-root patch (AWS, until the CLI grows AWS support), the ~17 chronically-OutOfSync child Applications converge on the next reconciliation cycle without operator intervention. No data-plane impact.

Refs ADR 0012 (scheduling modes and pool selection).

## [0.53.1] - 2026-05-15

### Fixed — expose `tempo_role_arn` terraform output

v0.53.0 added `aws_iam_role.tempo` and wired `identity.tempo.roleArn` into the platform-infrastructure Secret (so in-cluster consumers like the ArgoCD helm parameters bridge see the role ARN), AND added a `{{ .Values.identity.tempo.roleArn }}` reference to the platform-root grafana-stack template — but **forgot to expose the IAM role ARN as a terraform output**.

Downstream consumers that re-render the platform-root Application from terraform outputs (e.g. cortex's `scripts/platform-root-apply.sh` reading `tfout tempo_role_arn`) get an empty string. Their `--set identity.tempo.roleArn=...` flag is dropped from the `helm template` invocation, and the new template reference dereferences nil:

```
template: platform-root/templates/grafana-stack.yaml:328:30:
executing "..." at <.Values.identity.tempo.roleArn>:
nil pointer evaluating interface {}.roleArn
```

The platform-root Application then enters `ComparisonError` cluster-wide, blocking ALL ArgoCD reconciliation. Observed on `cortex-eks-prd` 2026-05-15 during the v0.50.0 → v0.53.0 bump.

### Files changed

- `providers/aws/outputs.tf` — `+5 / -0`. One block mirroring `loki_role_arn` / `mimir_role_arn`:
  ```hcl
  output "tempo_role_arn" {
    description = "IAM role ARN for Tempo ServiceAccount."
    value       = aws_iam_role.tempo.arn
  }
  ```

### Operational note for the next IRSA addition

When wiring a new IRSA role into `providers/aws/`, the canonical 4 places to touch are:

1. `iam.tf` — `aws_iam_role.<name>` + inline policy
2. `platform-outputs.tf` — `identity.<name>.roleArn` entry in the platform-infrastructure Secret (for in-cluster consumers)
3. **`outputs.tf` — `output "<name>_role_arn"`** (for terraform-output-based consumers — this was the missed slot in v0.53.0)
4. The component's `*-values-aws.yaml` + `bootstrap/platform-root/templates/<area>.yaml` — SA annotation reference

Worth promoting to a CONTRIBUTING.md note in a follow-up.

## [0.53.0] - 2026-05-15

### Added — Tempo S3 backend on AWS

Closes the last gap in the grafana-stack object-storage migration
started in v0.19.0 (loki + mimir): **Tempo now writes immutable trace
blocks to the shared observability bucket on AWS**, via IRSA. The local
PVC is reduced to a WAL holder only.

### Why

The Tempo chart 1.24.4 defaults to `storage.trace.backend: local`. With
the platform's default 4Gi PVC and 720h (30d) compactor retention, this
ratio inevitably trips the `PvcAlmostFull` alert on any cluster with
sustained ingest — observed on `cortex-eks-prd` 2026-05-14 with
`storage-grafana-tempo-0` at 88.86%. Mimir and Loki had been on S3
since v0.19.0; Tempo was the last component still relying on a local
PVC for retention.

### Files changed

- `core/components/grafana-stack/tempo-values-aws.yaml` — **new**.
  Mirrors `mimir-values-aws.yaml` / `loki-values-aws.yaml`:
  `tempo.storage.trace.backend: s3` with bucket / endpoint / region
  placeholders injected via `helm.parameters`, plus IRSA-annotated
  ServiceAccount.
- `bootstrap/platform-root/templates/grafana-stack.yaml` — adds the
  AWS `parameters:` block under the tempo Application, analogous to
  the loki and mimir blocks already there. Injects
  `tempo.storage.trace.s3.{bucket,endpoint,region}` from
  `global.observabilityBucketName` / `global.region`, and the
  `eks.amazonaws.com/role-arn` SA annotation from
  `identity.tempo.roleArn`.
- `providers/aws/iam.tf` — `aws_iam_role.tempo` + inline `tempo_s3`
  policy, modeled after `aws_iam_role.mimir`. Bucket-wide access on
  the observability bucket (matches the loki/mimir v0.19.0
  broadening). KMS permissions on `aws_kms_key.s3_data` included for
  parity. Inline role-scoped policy avoids the standalone-policy name
  collision that `CONTRIBUTING.md`'s IRSA-module-convention prevents
  for the upstream submodule path; Tempo does not use that submodule.
- `providers/aws/platform-outputs.tf` — exposes
  `identity.tempo.roleArn` to the helm parameters bridge.

### Credentials

Tempo 2.9's S3 backend uses the thanos-io/objstore client, which picks
up IRSA credentials via the AWS SDK default chain (`AWS_ROLE_ARN` +
`AWS_WEB_IDENTITY_TOKEN_FILE` injected by the EKS pod-identity webhook
when the SA carries the role-arn annotation). No static keys are
configured.

### Behavior on downstream consumers

- **AWS clusters**: after `terraform apply` bumps the source ref and
  ArgoCD syncs grafana-tempo, the Tempo pod restarts onto the s3
  backend. Existing blocks on the local PVC under `/var/tempo/traces`
  are stranded (the compactor no longer references them) — they
  persist until the PVC is recreated or the path is manually cleared.
  WAL stays local; PVC steady-state usage drops to <100Mi against the
  4Gi reservation.
- **Azure clusters**: unaffected. The new `parameters:` block is
  gated on `{{- if eq .Values.global.provider "aws" }}`. Equivalent
  Azure wiring (`tempo-values-azure.yaml` with the blob backend) is a
  separate follow-up.

### Operational notes

- The bucket lifecycle (`var.s3_observability_lifecycle_days`) should
  be `>= tempo.retention` (default 720h = 30d) to avoid S3 expiring
  blocks before Tempo's compactor does. The platform default is `0`
  (lifecycle disabled), which is safe.
- The 4Gi PVC defined in `tempo-values.yaml` is now conservative
  (was sized for traces; carries only WAL). Shrinking it is a clean
  follow-up that should land separately to keep this release
  cirurgical.

## [0.52.0] - 2026-05-14

### Added — `iam_policy_name_use_cluster_prefix` (multi-cluster-per-account safety)

New tfvar that opts-in to cluster-prefixed IAM policy names for the six
IRSA bundles wired by `providers/aws/`:

| Module                  | Canonical (default)            | Prefixed (`true`)                                      |
| ----------------------- | ------------------------------ | ------------------------------------------------------ |
| `external_secrets_irsa` | `External_Secrets`             | `${cluster_name}-External_Secrets`                     |
| `external_dns_irsa`     | `External_DNS`                 | `${cluster_name}-External_DNS`                         |
| `cert_manager_irsa`     | `Cert_Manager`                 | `${cluster_name}-Cert_Manager`                         |
| `velero_irsa`           | `Velero`                       | `${cluster_name}-Velero`                               |
| `ebs_csi_irsa`          | `EBS_CSI`                      | `${cluster_name}-EBS_CSI`                              |
| `alb_controller_irsa`   | `AWS_Load_Balancer_Controller` | `${cluster_name}-AWS_Load_Balancer_Controller`         |

### Why

The upstream `terraform-aws-modules/iam-role-for-service-accounts`
submodule hardcodes the canonical policy names when `policy_name` is
left unset. IAM policies are **account-scoped**, so the second EKS
cluster in the same AWS account that enables the same IRSA bundle fails
during apply with `EntityAlreadyExists`. Hit in production on 2026-05-13
bringing up `cortex-platform-hml` next to `cortex-platform-prd` (both in
account `093996075120`), where 4 of 6 policies collided.

### Behavior

- Default `false` — preserves existing canonical names. Zero-impact for
  every cluster already running (same names continue to be produced and
  managed by Terraform with no plan diff).
- Set `true` on **new** clusters being brought up alongside an existing
  cluster in the same AWS account.
- **Do NOT flip on an existing cluster** without first detaching +
  reattaching policies — Terraform plans delete-then-create on the
  policy, briefly revoking pod permissions.

### Convention for new IRSA modules

`CONTRIBUTING.md` (new file at repo root) documents the rule every
future IRSA module addition MUST follow:

```hcl
policy_name = var.iam_policy_name_use_cluster_prefix ? "${local.cluster_name}-<Canonical>" : null
```

This keeps the codebase free of the same trap surfacing every time a new
upstream IRSA helper is wired in.

### Files changed

- `providers/aws/variables.tf` — new variable with heredoc description
  + irreversibility warning.
- `providers/aws/iam.tf` — `policy_name` added to `external_secrets_irsa`,
  `external_dns_irsa`, `cert_manager_irsa`, `velero_irsa`.
- `providers/aws/eks.tf` — `policy_name` added to `ebs_csi_irsa`.
- `providers/aws/alb-controller.tf` — `policy_name` added to
  `alb_controller_irsa`.
- `providers/aws/terraform.tfvars.example` — documents the new tfvar.
- `CONTRIBUTING.md` — new file with IRSA module convention + release
  process notes.

## [0.51.0] - 2026-05-14

### Added — `spec/upstart/` and `spec/cleanup/` (Phase A of ADR 0036)

This release tags the post-`v0.50.0` merge of `feat(spec): upstart.yaml
v3 + cleanup.yaml v1 declarative specs` (#163), making the declarative
bootstrap / cleanup specifications available as part of a tagged release
for consumers (Phase B of `estabilis-platform-tools`, which renders them
via the new `upstart_loader` + `upstart_engine` + `cleanup_engine`).

New directories under `spec/`:

```
spec/
├── upstart/
│   ├── schema/upstart.v3.schema.json   # JSON Schema 2020-12 (21 $defs)
│   ├── upstart.yaml                     # base, provider-agnostic
│   ├── upstart.aws.yaml                 # AWS overlay (Karpenter pre,
│   │                                    #   Wave 0 inserted, vault init)
│   ├── upstart.azure.yaml               # Azure overlay (empty pre)
│   ├── values/argocd-seed.yaml          # ArgoCD helm values, static
│   └── schema/tests/{good,bad}/         # 14 fixtures (CI regression)
└── cleanup/
    ├── schema/cleanup.v1.schema.json    # cleanup gate schema
    ├── cleanup.yaml                     # base teardown (7 phases)
    ├── cleanup.aws.yaml                 # AWS overlay (Karpenter CRs,
    │                                    #   karpenter helm uninstall,
    │                                    #   EC2 orphan terminate)
    ├── cleanup.azure.yaml               # Azure overlay (empty)
    └── schema/tests/{good,bad}/         # additional fixtures
```

CI enforcement (since #163):

- `pre-commit` local hook + `.github/workflows/spec-validation.yaml`
  CI gate both delegate to `scripts/validate-specs.sh` (zero drift).
  Strict `additionalProperties: false` rejects unknown fields per
  ADR 0036 §4.11.
- 14 bad/* + 4 good/* fixtures guard against schema weakening.
- `spec/.argocdignore` blocks accidental consumption by any future
  ApplicationSet directory generator.

### Why a release tag now

`estabilis-platform-tools` Phase B (#222) introduced
`upstart_loader.ensure_upstart_spec_configmap()` which fetches
`spec/upstart/{base,overlay,argocd-seed}.yaml` from the **latest
release of this repository** (GitHub Releases API). Without a tag
containing `spec/upstart/`, consumers must use `--refresh-spec` against
`main` — acceptable for test deployments but undesirable for production.
This `v0.51.0` tag makes `spec/upstart/` available at a stable,
auditable ref.

No functional change to charts, Terraform modules, or Helm values from
`v0.50.0`. Operators upgrading from `v0.50.0` to `v0.51.0` see no
behavior change in their cluster — only the new `spec/` directory
becomes consumable by Phase B tooling.

### Migration notes

- Operators using `estabilis-platform-tools` ≥ Phase B (PR #222) and
  pointing at this `v0.51.0`: the CLI will populate
  `argocd/upstart-spec` ConfigMap on first run from the spec files
  shipped in this tag. No manual action.
- Operators on `estabilis-platform-tools` ≤ Phase A (legacy
  `upstart.py`): no action — the legacy tooling does not consume
  `spec/`. The downstream client's `upstart.yaml` v2 continues to be
  the source of truth for the old CLI.

---

## [0.50.0] - 2026-05-12

### Added — `alloy.configMap.extraContent` extension point

Clients can now append custom River components to the Alloy DaemonSet
config without forking `core/components/grafana-stack/alloy-values.yaml`,
via `overrides/alloy/values.yaml` in their gitops repo:

```yaml
alloy:
  configMap:
    extraContent: |
      // e.g. blackbox-exporter embedded in Alloy
      prometheus.exporter.blackbox "external_apis" {
        config = "{ modules: { http_2xx: { prober: http, timeout: 5s } } }"
        target {
          name    = "custom-data-api"
          address = "https://custom-data-api.example.com/health"
          module  = "http_2xx"
        }
      }

      prometheus.scrape "external_apis" {
        targets    = prometheus.exporter.blackbox.external_apis.targets
        forward_to = [prometheus.remote_write.mimir.receiver]
      }
```

#### Why

The Alloy chart consumes its entire River config as a single
`alloy.configMap.content` string. Helm value merging on a scalar string
is replace-not-merge — any downstream attempt to add scrape jobs would
require copying the full ~1200-line upstream content into the override,
which the downstream gitops convention explicitly forbids ("never
duplicate upstream charts").

Adding new scrape targets is a recurring need:
- Multi-target exporters (blackbox, snmp) that need static target lists
  scoped to a single client deployment
- Endpoints that pod-annotation discovery cannot reach (URLs in other
  clusters/accounts, headless services, non-pod targets)
- Domain-specific `prometheus.exporter.*` embeds that downstream owns

The Grafana Alloy chart at `1.6.2` already wraps its `configMap.content`
in a `tpl` call (chart's `templates/configmap.yaml`), so introducing a
client-controlled tail block is a 4-line `{{- with ... }}` substitution
at the end of the upstream content string. No chart fork.

#### Behavior

- Default `extraContent` = unset → no functional River added. The
  rendered ConfigMap gains only inert documentation comments describing
  the slot, behaviorally byte-equivalent to v0.49.0.
- When set, the string is `tpl`-evaluated against the chart context
  (downstream can reference `.Values.*` like any other Helm template),
  then appended after `prometheus.remote_write "mimir"`. River blocks
  in `extraContent` can therefore reference upstream-defined receivers
  and exporters by ID (e.g.
  `forward_to = [prometheus.remote_write.mimir.receiver]`).

#### Migration

No action required. Existing clusters render identically until an
override values file populates the new key.

To opt in, downstream gitops repos add `overrides/alloy/values.yaml`
with the `extraContent` block. The `overrideValueFile` helper in
`bootstrap/platform-root/templates/grafana-stack.yaml` already wires
this path into the Alloy `Application` — no platform-root change
needed.

#### Files changed

- `core/components/grafana-stack/alloy-values.yaml` — appends
  `{{- with .Values.alloy.configMap.extraContent }}{{ tpl . $ | trim }}{{- end }}`
  at the tail of the existing `configMap.content` string, framed by a
  descriptive comment block explaining the slot to operators reading
  the rendered River config in-cluster.

#### Smoke tested

- `helm template grafana/alloy --version 1.6.2 -f alloy-values.yaml`
  (no override) → renders without errors; only addition vs v0.49.0
  output is the documentation comment block at the end of the River
  config (functional River unchanged).
- `helm template grafana/alloy --version 1.6.2 -f alloy-values.yaml -f
  override-with-blackbox.yaml` → appends the override's
  `prometheus.exporter.blackbox` + `prometheus.scrape` blocks after the
  comment, preserves 4-space indentation, no template errors.

#### Why MINOR bump (not PATCH)

The 0.47.1 `alertOverrides` slot landed as PATCH because the empty
default produced a byte-identical rendered ConfigMap. This slot adds a
new permanent comment block to the rendered River regardless of opt-in
(serves as operator-facing documentation of the extension point), so
the no-op claim is "behaviorally byte-equivalent" rather than strictly
byte-identical. Matches the 0.48.0 `clientHubAppExtraSourceRepos`
precedent: new override slot → MINOR.

## [0.49.0] - 2026-05-08

### Changed — external-dns policy `upsert-only` → `sync`

`core/components/external-dns/values.yaml` switches the default
policy from `upsert-only` to `sync`. Removed Ingress / Service hosts
now have their CNAME + TXT registry records garbage-collected on the
next external-dns reconcile (default `--interval=1m`).

#### Why

`upsert-only` only creates and updates records; nothing ever deletes
them. Every offboarded app (any GitOps flow that removes Ingress
resources, manual `kubectl delete ingress`, cluster teardown, etc.)
leaves an orphan CNAME + TXT pair on the DNS zone forever. On
Cloudflare Free (zone record cap = 200), this hits the wall in days
for an active platform tenant.

Observed in a production cluster instance: 138 orphan records pinned
the zone at 200/200, blocking record creation for any new deployment
with Cloudflare `code 81045: Record quota exceeded`. New deployments
came up Healthy in the cluster but had NXDOMAIN on the public host
until manual API cleanup unblocked the quota.

#### Safety

`sync` only deletes records whose TXT registry companion matches the
local `--txt-owner-id` (set per cluster via `global.clusterName`).
Records created by another tool (manual entries, another cluster's
external-dns instance with a different owner-id, NS/SOA, etc.) are
preserved untouched — the registry is what gives external-dns
ownership; without that companion TXT, it walks past.

#### Migration

No action required for clusters where the cluster's external-dns is
the only writer of its hosts. Operators can confirm by listing
records in the zone and grouping by their `external-dns/owner=...`
TXT content; only records matching the cluster's own owner-id will
be touched.

This is a MINOR bump because the policy change is provider-wide and
operationally observable (deletion events appear in external-dns
logs that previously didn't).

## [0.48.0] - 2026-05-07

### Added — `clientHubAppExtraSourceRepos` slot for the `platform-client-infra` AppProject

New override slot in `bootstrap/platform-root/values.yaml`:

```yaml
clientHubAppExtraSourceRepos:
  - "https://github.com/<org>/<client>-projects.git"
  - "https://github.com/<org>/<client>-policies.git"
```

Appends additional repos to the `platform-client-infra` AppProject's `sourceRepos` list, beyond the default single entry (`clientGitopsRepoUrl`). Mirrors the existing `platformAppsExtraSourceRepos` / `workloadAppsExtraSourceRepos` pattern from ADR 0027 — no wildcards, every host must be explicit so AppProject scope-creep is auditable in code review.

#### Why

When a client splits gitops content across multiple repos — e.g. a dedicated provisioning repo (`<client>-projects`) for declarative project bootstrap (ADR 0033 Phase 4) alongside the runtime gitops repo (`<client>-gitops`) for app values — the second repo must be a permitted source of the same AppProject that authorizes hub-app Applications. Without this slot, the hardcoded `sourceRepos: [{{ .Values.clientGitopsRepoUrl }}]` rejected any Application sourced from the additional repo.

The four governance dimensions of `platform-client-infra` are now uniformly extensible via wrapper override:

| Dimension | Override slot |
|-----------|---------------|
| Source repos | `clientHubAppExtraSourceRepos` (this PR) |
| Destination namespaces | `clientHubAppNamespaces` |
| Cluster-scoped resource kinds | `clientHubAppExtraClusterResources` |
| Namespace-scoped resource kinds | `*/*` (always permitted) |

This is a MINOR bump because it adds a new override slot (no behavior change for clients who do not opt in — empty list default).

## [0.47.1] - 2026-05-06

### Added — `alertOverrides` slot in `mimir-rules` chart

Clients can now disable or customize platform-shipped alerts without
forking the chart, via `overrides/mimir-rules/values.yaml`:

```yaml
alertOverrides:
  TempoMetricsGeneratorFailures:
    enabled: false
  HighMemoryUsage:
    for: 30m
  PvcAlmostFull:
    expr: |
      (kubelet_volume_stats_used_bytes / kubelet_volume_stats_capacity_bytes) > 0.95
    labels:
      severity: info
```

#### Behavior

- `enabled: false` → rule is dropped from the rendered ConfigMap
- Any other field → SHALLOW-merged onto the upstream rule (override
  wins on collision). Providing a complex field like `labels:` REPLACES
  the entire labels map; caller must include every label intended.
- Threshold tweaks: provide the complete new `expr:` string. The chart
  does not parse PromQL — surgical edit of a single number inside an
  expr is intentionally not supported.
- Override key MUST match the `alert:` field exactly (case-sensitive).
  Typo silently no-ops; cross-check with `kubectl get configmap
  mimir-alerting-rules -n grafana -o yaml | grep "alert:"`.
- Group-level toggles (`ruleGroups.<group>.enabled`) and
  `customRuleGroups` keep working unchanged; `alertOverrides` is
  independent and stacks on top.

#### Files changed

- `core/components/mimir-rules/templates/_helpers.tpl` — new
  `mimir-rules.applyOverrides` helper (parse YAML → filter/merge → emit)
- `core/components/mimir-rules/templates/configmap.yaml` — calls helper
  for each tier file
- `core/components/mimir-rules/values.yaml` — adds `alertOverrides: {}`
  default (empty = upstream behavior preserved)
- `core/components/mimir-rules/Chart.yaml` — chart version bumped
  `0.2.0` → `0.3.0`

#### Why PATCH bump (not MINOR)

The new field defaults to `{}`, which produces a rendered ConfigMap
byte-equivalent to v0.47.0 output for every existing client. Zero
behavior change without opt-in. Per the same rationale used for default
tweaks elsewhere in this CHANGELOG, opt-in additions with a no-op
default land as PATCH.

#### Smoke tested

- `helm template` with empty overrides → 45 alerts, identical to v0.47.0
- `helm template` with `TempoMetricsGeneratorFailures.enabled=false` →
  44 alerts, target alert absent
- `helm template` with `HighMemoryUsage.for=30m` → field replaced,
  `expr`/`labels` preserved
- Typo (`TempoMetricsGeneratorFailur`) silently no-ops as designed
- Disabling all alerts in a group renders `groups: []` (Mimir Ruler
  accepts; no error)
- Group-level toggle (`ruleGroups.platformDegradation.enabled=false`)
  still drops the entire tier file as before

## [0.47.0] - 2026-05-06

### Added — Grafana Infinity datasource plugin enabled by default

`core/components/grafana-stack/grafana-values.yaml` — adds
`yesoreyeram-infinity-datasource` to the upstream `plugins:` list,
alongside the existing `grafana-llm-app`, `grafana-lokioperational-app`
and `grafana-github-datasource`.

#### Why

The Infinity datasource (a generic JSON/CSV/XML/HTML/GraphQL/REST
datasource) has been carried as a downstream-only override in
`cortex-platform-aws-us-east-1-prd/overrides/grafana/values.yaml`
since the Bright Data integration landed (2026-04). With the
brightdata-exporter hub-app coming online, a second consumer of the
Infinity plugin is needed (the exporter exposes a `/api` REST surface
the FinOps dashboard hits via Infinity), and other clients have asked
for ad-hoc REST/JSON datasources too.

Promoting the plugin to the platform default removes the bespoke
override (one fewer entry to repeat in every downstream that wants
Infinity-style datasources) while keeping the actual datasource
configuration downstream — the plugin is a generic capability, the
specific datasource declarations remain client-specific.

#### Impact

- `cortex-platform-aws-us-east-1-prd` removes the duplicate plugin
  entry from `overrides/grafana/values.yaml` after bumping
  `platform_version` (Helm list-replace semantics: the override
  REPLACES upstream's `plugins:` list, so the upstream Infinity entry
  is only seen once the override drops it).
- New downstream deployments inherit Infinity automatically.
- No new credentials / secrets / TF inputs — the plugin is
  load-time-free; specific datasources still declare their own auth
  in `overrides/grafana/values.yaml`.

## [0.46.1] - 2026-05-06

### Fixed — Velero memory limit insufficient for CSI snapshot flow

`core/components/velero/values.yaml` — bumps the velero container
memory request 128Mi → 256Mi and limit 512Mi → 1Gi.

#### Why

First real CSI backup test on cortex prd after v0.46.0 (snapshot-
controller addon + VolumeSnapshotClass) consistently OOMKilled at
~35-40s (exitCode 137). Velero v1.17.1 with `--features=EnableCSI`
holds:

- Cluster-wide resource discovery state (kopia uploader walks every
  resource in scope, ~1k-4k objects on a typical cortex-sized cluster)
- 12+ in-flight CSI VolumeSnapshot reconciles (one per PVC)
- AWS S3 multi-part upload buffers
- Plugin RPC channels to velero-plugin-for-aws

512Mi was sufficient for the no-CSI flow shipped by v0.46.0 but tight
once the snapshot-controller component started being exercised. 1Gi
gives ~2× headroom over observed peak. Memory peak after fix: spike
during backup phase, ~51Mi steady-state idle.

Request bumped to 256Mi so Karpenter reserves accurately for the
steady state plus CSI baseline (avoids node bin-packing surprises
during multi-cluster backup windows).

#### Lineage

This is the patch I expected per the "ship vX.Y.0 expecting patch
vX.Y.1 after first real consumer apply" rule — design-time review
(brutal-code-critic) catches structural issues but cannot anticipate
runtime memory pressure on a specific cluster's workload mix.

## [0.46.0] - 2026-05-06

### Added — CSI snapshot-controller EKS managed addon + VolumeSnapshotClass wiring

`providers/aws/eks.tf` adds `snapshot-controller` to `local.default_addons`
(installs the `volumesnapshots/volumesnapshotcontents/volumesnapshotclasses`
CRDs and the controller Deployment that reconciles them — managed by AWS,
upgrade lifecycle stays on the EKS control plane).

`bootstrap/platform-root/templates/snapshot-controller.yaml` (new) creates
an ArgoCD Application that pulls from `estabilis-platform-gitops`
v0.39.10's new `components/snapshot-controller` chart. AWS-only,
sync wave 6 (before velero in wave 7), `components.snapshot-controller`
toggle in `bootstrap/platform-root/values.yaml`.

`bootstrap/platform-root/templates/_helpers.tpl` — `componentsForwarding`
helper now lists `snapshot-controller` as AWS-only so it gets stripped
from the components map propagated to network-policies / resource-quotas
on Azure clusters (preventing OutOfSync drift).

#### Why

Velero CSI backups silently skip PV snapshotting unless a
VolumeSnapshotClass carries the `velero.io/csi-volumesnapshot-class:
"true"` discovery label. Observed on cortex prd 2026-05-05 after
v0.45.1 fixed the KMS gap: 14 PVs landed in `PartiallyFailed` phase
because no VSC existed at all. The CSI external-snapshotter (CRDs +
controller) is the prerequisite that unlocks the proper backup flow.

The community converged on the EKS managed addon as the canonical
install path (per AWS docs and Kubernetes SIG-Storage). It tracks
upstream releases (v8.5.0-eksbuild.4 today, paired with K8s 1.31+),
upgrades cleanly via the EKS control plane, and follows the same
opinionated treatment as the other 5 platform-managed addons (vpc-cni,
coredns, kube-proxy, eks-pod-identity-agent, aws-ebs-csi-driver).

The VolumeSnapshotClass itself (with the velero label) is shipped via
estabilis-platform-gitops v0.39.10 — paired release.

#### How

Existing AWS clients on platform v0.46.0+:
1. `terraform init -upgrade && terraform apply` (creates the addon)
2. `estabilis promote <client> -d <deployment> --force-refresh`
   (rolls the new `snapshot-controller` Application into platform-root)

Verification:
- `kubectl get crds | grep snapshot.storage.k8s.io` → 6 CRDs
- `kubectl get volumesnapshotclass ebs-csi-aws` → exists, with the velero label
- Trigger an ad-hoc backup: phase=Completed (no PartiallyFailed) and items list includes PVs

Azure clients are unaffected — addon block + Application both gated
on `global.provider == "aws"`.

## [0.45.1] - 2026-05-06

### Fixed — Velero IAM role missing KMS permissions

`providers/aws/iam.tf`. Adds an inline policy to the Velero IRSA role
granting `kms:Decrypt` + `kms:GenerateDataKey` scoped to the
customer-managed `s3_data` KMS key.

#### Why

The upstream module `terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts`
v6.5 with `attach_velero_policy = true` builds a policy with EC2
(snapshot management) + S3 (PutObject/GetObject/etc) but **no KMS
actions**. The default Velero policy template assumes the backup
bucket uses SSE-S3 (AES256), not SSE-KMS.

Estabilis platform encrypts the Velero bucket with the
customer-managed `aws_kms_key.s3_data` (see `s3.tf`). When Velero
calls `s3:PutObject`, S3 in turn calls `kms:GenerateDataKey` carrying
the **caller's identity** (the Velero IRSA role). IAM evaluates the
caller's policy and finds no KMS grant → `AccessDenied`. The KMS key
policy's `kms:ViaService` clause for the S3 service is necessary but
not sufficient — IAM still requires the caller to have the action
on its identity-based policy.

Observed in cortex prd (the only AWS client running this code today):
6 consecutive days of failed backups (2026-05-01 through 2026-05-06),
each with `errors: 14` and `failureReason` containing
`AccessDenied: ... is not authorized to perform: kms:GenerateDataKey`.

#### Why scoped to one key (not `kms:*` / `Resource: *`)

`aws_kms_key.s3_data` encrypts every S3 bucket in the platform that
needs customer-managed encryption (Velero, Loki, Cost Export, Flow
Logs). A blanket `kms:*` would let Velero touch keys it has no
business with (e.g. the `platform_secrets` key used by Vault). The
two scoped actions on a single key match Velero's actual need.

#### Compatibility

- Other Estabilis AWS clients running Velero are affected by the same
  bug — this fix lands at the platform tag level, so they pick it up
  on their next platform bump.
- The fix is purely additive (new `aws_iam_role_policy`); no existing
  resource modified, no destroy/recreate. `terraform plan` shows a
  single resource creation.

## [0.45.0] - 2026-05-05

### Added — `VaultPartialFailure` alert (Tier 2)

`core/components/mimir-rules/files/tier2-degradation.yaml`. Vault runs
as a 3-replica StatefulSet with raft consensus (quorum = 2/3). The
existing `VaultDown` (Tier 1, critical) only fires when ALL replicas
are at zero — full HA loss. This new alert catches the degraded state
earlier:

- 1/3 down: cluster operational but next failure breaks quorum
- 2/3 down: quorum lost, cluster goes read-only

Same `replicas_ready < spec_replicas` pattern used for
`MimirIngesterPartialFailure` (added in v0.43.0). Tier 2 warning so
operators can replace the failed replica before the cluster goes
fully read-only or down.

Total rules in AWS overlay: 43 → 44.

## [0.44.0] - 2026-05-05

### Added — 3 new platform alerts + Tempo /metrics scrape

Closes 3 of the 4 audit-listed Tier 3 component gaps + the Tempo
metrics-generator push-error gap. The other 2 originally-listed
components (OpenCost, Policy Reporter) turned out to have **no
workloads deployed** in this platform — namespaces exist but no
Deployments/StatefulSets/DaemonSets. Skipped accordingly; alerts can
be added in a follow-up if those components get rolled out.

#### `TrivyOperatorDown` (Tier 3, info)

`core/components/mimir-rules/files/tier3-operational.yaml`. Covers
the Trivy vulnerability scanner. Tier 3 because loss of Trivy doesn't
break running workloads; existing scan results remain valid in the
ConfigMaps. Promote to Tier 2 if compliance reporting depends on
scan freshness.

#### `EnvoyGatewayDown` (Tier 1, critical)

`core/components/mimir-rules/files/tier1-platform-down.yaml`. Single
alert covers both the Envoy Gateway controller (Deployment
`envoy-gateway`) AND the data-plane proxy (Deployment
`envoy-<class-name>-<hash>`). Controller down = no config reconcile;
data-plane down = ingress traffic stops on the affected Gateway. The
alert matches by namespace + label `deployment` rather than exact
name because the data-plane Deployment carries a per-cluster hash
suffix that's stable per cluster but unique across clusters.

#### `TempoMetricsGeneratorFailures` (Tier 2, warning)

`core/components/mimir-rules/files/tier2-degradation.yaml`. Catches
two failure modes of Tempo's metrics-generator (which feeds Grafana
Drilldown/Traces): registry collection failures and spans discarded
by the processor. Either means Drilldown silently returns incomplete
data.

**Required enabling Tempo /metrics scrape** —
`core/components/grafana-stack/tempo-values.yaml`. Audit found ZERO
`tempo_metrics_generator_*` metrics reaching Mimir despite Tempo
being healthy: the Tempo pod had no `prometheus.io/scrape` annotation,
so Alloy's `metric_pods` discovery never picked it up. Added pod
annotations (`prometheus.io/scrape=true`, `port=3200`,
`path=/metrics`) — same pattern already used by the `aws-load-balancer-controller`,
`cert-manager` and `beyla` pods on this platform. Without this scrape
fix, the new alert would be silently dead — same class as the
formerly-broken `ExternalDnsErrors` we replaced in v0.41.1.

### Skipped — no workloads to alert on

- **OpenCost**: namespace `opencost` exists, no Argo Application, no
  resources. Component not deployed in this platform.
- **Policy Reporter**: namespace `policy-reporter` exists, no Argo
  Application, no resources. Same situation.

If/when these are deployed, equivalent `*Down` alerts can be added
following the same `kube_deployment_status_replicas_available == 0`
pattern.

### Net effect

| | Before v0.44.0 | After v0.44.0 (AWS) |
|---|---|---|
| Total rules | 40 | 43 |
| Tier 1 alerts | 18 | 19 |
| Tier 2 alerts | 16 | 17 |
| Tier 3 alerts | 6 | 7 |
| Tempo `/metrics` scraped | NO | YES |

### Audit closure

This release closes the audit started in v0.41/v0.42. Net delta from
the original 33-rule baseline:
- 4 broken alerts repaired (v0.41.1)
- B1-B4 coverage gaps + 3 Tier 1 alerts (v0.42.0)
- 5 platform alerts (v0.43.0)
- 3 alerts + Tempo scrape (this release)

= **43 functional rules** (from 32 functional + 1 broken/dead-code,
actually 30 useful rules pre-audit) covering the platform topology as
of 2026-05-05.

## [0.43.0] - 2026-05-05

### Added — 5 new platform alerts (audit follow-up)

Closes 5 of the 7 audit-listed "opportunity" gaps from the v0.41/v0.42
audit. Each alert addresses a class of failure that was silent in the
existing rule set.

#### `CertManagerControllerDown` (Tier 1, critical)

`core/components/mimir-rules/files/tier1-platform-down.yaml`. Catches
loss of any of the 3 cert-manager deployments (controller, webhook,
cainjector). Existing `CertificateExpiring14d`/`CertificateExpiring3d`
(Tier 2) only catch the tail effect days after issuance/renewal stops
— this fires within 3 minutes of controller down.

#### `ArgocdApplicationSetControllerDown` (Tier 1, critical)

Same file. ApplicationSet controller renders dynamic Application sets
(e.g. `client-apps` + `hub-client-apps` cover 21 cortex client app
namespaces). Loss = template changes don't propagate, new clusters
don't get bootstrapped.

#### `ImagePullBackOff` (Tier 2, warning)

`core/components/mimir-rules/files/tier2-degradation.yaml`. Catches
deploy-time failures invisible until now: wrong ECR tag, podre digest,
missing IAM permissions, registry-egress NetworkPolicy gap. The
existing `PodCrashLooping*` alerts only catch restart loops AFTER the
container starts; this catches the state where it never starts.
Validation against cortex prd: the metric saw 1 `ImagePullBackOff`
event and 1 `ErrImagePull` event in the last 24h that this alert
would have caught.

#### `MimirIngesterPartialFailure` (Tier 2, warning)

Same file. Tier 1 (`MimirIngesterDown`) only fires when ALL ingesters
are down. On 2-ingester cortex prd, losing 1/2 means write
replication is gone — single point of failure if the remaining one
dies. New alert catches `replicas_ready < spec_replicas` for >5min.

#### `PvcGrowthVelocity` (Tier 3, info)

`core/components/mimir-rules/files/tier3-operational.yaml`. Predicts
empty-in-6h via `predict_linear` over the last 6h growth rate.
Complements the existing absolute thresholds (`PvcAlmostFull` @ 85%,
`PvcFull` @ 95%) — a fast-filling PVC can blow past those thresholds
between scrape intervals. Guarded with `> 70% used` so we don't alert
on early-life PVCs whose growth rate isn't stable yet.

### Net effect

| | Before | After (AWS) |
|---|---|---|
| Total rules | 35 | 40 |
| Tier 1 alerts | 16 | 18 |
| Tier 2 alerts | 14 | 16 |
| Tier 3 alerts | 5 | 6 |
| Components without any alert | 5 | 5 (Trivy, OpenCost, Policy Reporter, Envoy Gateway, metrics-server — Tier-3 priority, deferred) |

### Audit status after this release

✅ Done: 4 broken alerts (v0.41.1), B1-B4 coverage gaps + 3 new alerts (v0.42.0), 5 new alerts (this release).

⏳ Deferred: 4 Tier-3 components without alerts (Trivy, OpenCost, Policy Reporter, Envoy Gateway), RED metrics SLO alerts for 21 cortex client apps (scope dictates separate planning per app), Tempo metrics-generator push-error alerting (low value — Drilldown failures are user-visible immediately).

## [0.42.0] - 2026-05-05

### Added — Coverage gaps in mimir-rules platform alerts (B1–B4 + 3 new alerts)

Follow-up to v0.41.1 (broken-alert fixes). Audit identified the existing
33-rule set reflected platform state from ~2 months ago — selectors were
defaulted to a smaller core platform and didn't grow as the platform
added Karpenter, Beyla, more app namespaces (21 cortex client apps),
and ALB controller. Fixes:

#### B1 — ArgoCD project filter widened (`platform` → 3 projects)

`ArgocdAppOutOfSync` and `ArgocdAppDegraded` (Tier 1) checked
`project="platform"` only, leaving 25/64 ArgoCD apps unmonitored:
21 client apps in `platform-apps`, 3 in `platform-client-infra`.
Switched to `project=~"platform|platform-apps|platform-client-infra"`.
Added `{{ $labels.project }}` to the description so notifications
identify which fleet the failing app belongs to.

#### B2 — `PodCrashLoopingCritical` (Tier 1) namespace regex

Added: `aws-load-balancer-controller`, `external-dns`, `karpenter`,
`vault`, `velero`, `grafana`. These are core platform components
whose loss makes the cluster unusable but were missing from the
critical regex. Client app crashloops stay at Tier 2
(`PodCrashLoopingWarning`, see below).

#### B3 — `DaemonSetUnavailable` (Tier 1) daemonset regex

Added: `beyla` (deployed 2026-05-04), `aws-node`, `ebs-csi-node`,
`kube-proxy`, `eks-pod-identity-agent`. AWS/EKS-specific names are
cross-provider safe — on Azure the metric returns no series for
those, so the regex is harmless.

#### B4 — Tier 2/3 namespace regexes for client app coverage

Four alerts (`HighMemoryUsage` Tier 2, `PodCrashLoopingWarning` Tier 2,
`HighCpuThrottling` Tier 3, `DeploymentReplicasMismatch` Tier 3) now
include `app-.*` (matches all 21 cortex client app namespaces and any
future ones) plus the missing platform components (alb-controller,
karpenter, vault, etc.). Tier separation preserved: client app
crashloops route to warning, not critical.

#### Priority 2 — 3 new Tier 1 alerts for unmonitored platform components

- `AwsLoadBalancerControllerDown` — ALB controller is the ingress on
  EKS. It had zero alert coverage; cluster losing ALB controller =
  Ingresses stop being provisioned silently.
- `KarpenterDown` — Karpenter handles node autoscaling on EKS. Loss =
  pending pods get no nodes, scaling stops.
- `VaultDown` — full HA loss (all 3 replicas down). Partial-quorum
  degradation belongs in a separate Tier 2 alert if needed (not added
  now to keep scope tight).

All three use the `kube_*_status_*` metric pattern (no scrape
dependency) so they're cross-provider safe — on Azure clusters where
these components aren't installed, the metric returns no series and
the alert is silently inert.

### Net effect

| | Before v0.42.0 | After v0.42.0 (AWS) |
|---|---|---|
| Total rules | 32 (post-v0.41.1) | 35 |
| Apps in ArgocdAppOutOfSync scope | 39/64 (project=platform only) | 64/64 |
| Namespaces in PodCrashLooping coverage | 6 critical / 7 warning | 12 critical / 31 warning (incl. 21 app-*) |
| DaemonSets in unavailable alert | 2 | 7 |
| Components without ANY alert | 8+ | 5 (Trivy, OpenCost, Policy Reporter, Envoy Gateway, metrics-server) |

The 5 remaining unalerted components are Tier-3-priority and left for
a separate PR; this release covers everything that affects platform
availability or client workload health.

## [0.41.1] - 2026-05-05

### Fixed — 4 broken Mimir alerting rules

Audit of the 33-rule mimir-rules platform alert set against the live
state of cortex prd surfaced four rules that could never fire as
written. Fixes are query-level only — alert names, severities, tier
labels and runbook annotations are preserved where possible.

#### `PyroscopeDown` (Tier 1, critical)

`core/components/mimir-rules/files/tier1-platform-down.yaml`. The
alert checked `kube_deployment_status_replicas_available{deployment="grafana-pyroscope"}`,
but the `grafana/pyroscope` chart deploys Pyroscope as a StatefulSet,
not a Deployment. The metric returned 0 series, so the alert never
fired even when Pyroscope was unhealthy. Switched to
`kube_statefulset_status_replicas_ready{statefulset="grafana-pyroscope"}`,
matching the existing TempoDown / LokiDown pattern in the same group.

#### `KyvernoPolicyViolation` (Tier 3, info)

`core/components/mimir-rules/files/tier3-operational.yaml`. The alert
referenced `kyverno_policy_results`, but Kyverno renamed the metric to
`kyverno_policy_results_total` in v1.10 (Counter convention with the
`_total` suffix). The old name returned 0 series; the rename returns
~150 active series in cortex prd today. Added `_total`.

#### `ExternalDnsErrors` → `ExternalDnsDown` (Tier 2, warning)

`core/components/mimir-rules/files/tier2-degradation.yaml`. The alert
queried `external_dns_source_errors_total[10m]`, but no
`external_dns_*` metrics reach Mimir on this platform — the
external-dns chart doesn't ship with Prometheus scrape annotations
enabled and Alloy's `metric_pods` discovery never reaches the Pod's
:7979 metrics endpoint. Replaced with a controller-down query
(`kube_deployment_status_replicas_available{namespace="external-dns"} == 0`)
which doesn't depend on the metrics endpoint and surfaces the most
critical degradation (DNS records stop syncing) reliably. Renamed the
alert to `ExternalDnsDown` so the new semantic is reflected in
notifications. Enabling external-dns scrape coverage is left for a
separate follow-up; the metrics-based form can return when scrape lands.

#### `TraefikHighError5xx` — provider-gated (Tier 3, info)

`core/components/mimir-rules/files/tier3-traefik.yaml` (new) +
`core/components/mimir-rules/values{,-aws}.yaml`. The alert queries
`traefik_service_requests_total`, which is correct on Azure clusters
where Traefik serves ingress. On AWS clusters (cortex / future AWS
clients) Traefik is not the ingress controller — every Ingress uses
the AWS Load Balancer Controller (ALB) class, so the metric is empty
and the rule was dead-code in the rule list. Split the rule into a
new file `tier3-traefik.yaml` and gated its inclusion via
`ruleGroups.platformOperational.traefik` (default `true`, set to
`false` in `values-aws.yaml`). Existing Azure deployments behave
identically; AWS deployments stop loading the dead rule.

#### Net effect

Two formerly-silent critical alerts (Pyroscope, Kyverno) and one
formerly-silent warning (external-dns) now produce signal when the
underlying components fail. AWS clusters get one fewer dead-code
rule loaded into Mimir Ruler. No alert names changed except
`ExternalDnsErrors` → `ExternalDnsDown` (different semantic).

## [0.41.0] - 2026-05-04

### Added — TraceQL metrics support (Grafana Drilldown/Traces)

Tempo single-binary chart bumped `1.10.3 → 1.24.4` (Tempo `2.5.0 →
2.9.0`) to enable the `local-blocks` processor on the metrics-generator,
required by Grafana's Drilldown/Traces app for TraceQL metrics
queries (`{ } | rate()` style).

The previous `extraConfig.overrides.defaults.metrics_generator.processors`
block on chart 1.10 was a no-op because the template hard-coded the
processor list when `metricsGenerator.enabled=true`. Chart >=1.16
templatizes both `tempo.metricsGenerator.processor` and
`tempo.overrides.defaults`, so the local-blocks wiring is now actually
applied.

Three files touched:

- `bootstrap/platform-root/templates/grafana-stack.yaml` — bump chart
  pin to `1.24.4`.
- `core/components/grafana-stack/tempo-values.yaml` — drop dead
  `extraConfig` block, add `tempo.metricsGenerator.processor.local_blocks.flush_to_storage=true`,
  add `tempo.overrides.defaults.metrics_generator.processors` with
  `[service-graphs, span-metrics, local-blocks]`. Resources bumped
  `128Mi/512Mi → 1Gi/3Gi` requests/limits — `local-blocks` ingests live
  traces in memory before flushing, and Tempo 2.9 with all three
  processors OOM-killed on 512Mi during validation.
- `core/components/grafana-stack/grafana-values.yaml` — Tempo
  datasource URL `:3100 → :3200` (chart 1.20+ default
  `tempo.server.http_listen_port`).

Validated live in cortex prd cluster before commit:
`grafana-tempo-0` Ready/0-restarts on `tempo:2.9.0`, CM contains
`local-blocks` in the processors list and `processor.local_blocks.flush_to_storage:
true`, datasource health=OK, Drilldown/Traces no longer raises
"localblocks processor not found", `rate()` TraceQL metric returns
`series` with `samples` structure.

### Compatibility

- **Tempo URL `:3100 → :3200`**: only the in-cluster Grafana datasource
  references this URL. Alloy/Beyla push traces via OTLP gRPC `:4317`
  (unchanged). Downstreams that reference Tempo by URL outside this
  chart need to update.
- **Memory bump**: clients that overrode `tempo.resources` to a tighter
  limit (e.g. cortex AWS prd at 100Mi/512Mi) will OOM after this bump
  unless the override is widened or removed.

## [0.40.0] - 2026-05-04

Two changes shipped together — one bug fix and one new opt-in
component. Bundled to keep the release surface small ahead of the
Beyla pilot rollout.

### Fixed — Grafana Alloy `metric_pods` relabel + OTLP receiver routes

`core/components/grafana-stack/alloy-values.yaml`. Two pre-existing
bugs that silently dropped data on the hub Alloy:

- **`metric_pods` relabel** wrote `__address__="<port>:<port>"` because
  both backrefs in `replacement = "${1}:$0"` resolved to the same
  captured port value. Any pod relying on the `prometheus.io/scrape`
  annotation never had its `/metrics` endpoint reached. Replaced with
  the canonical Prometheus pattern that combines `__address__` (pod
  IP from discovery) with the annotation port. Also added a companion
  rule honoring `prometheus.io/path` when present.
- **OTLP receiver** routed only traces. Metrics and logs sent to
  `grafana-alloy:4317` were dropped at the receiver output. Added two
  batch processors (`metrics`, `logs`) plus two new exporters —
  `otelcol.exporter.prometheus` → existing `prometheus.remote_write.mimir`,
  `otelcol.exporter.loki` → existing `loki.write.default`. Trace path
  renamed `default` → `traces` for symmetry; trace endpoint unchanged.

Discovered while running an eBPF auto-instrumentation PoC. Beyla's
`/metrics` was healthy locally but never reached Mimir because of the
two issues. Validation: `helm template` clean, `alloy fmt` exit 0,
`alloy run` resolves all OTel + relabel components.

Refs estabilis-platform-tools#206 / PR #148.

### Added — Beyla platform component (eBPF auto-instrumentation)

`core/components/beyla/values.yaml` and
`bootstrap/platform-root/templates/beyla.yaml`. New opt-in component
deploying Grafana Beyla v3.9.7 (chart 1.16.5) for HTTP RED metrics +
traces without code changes in apps.

Default `components.beyla: false`; flip to `true` per cluster. Apps
opt in per-pod via the label
`estabilis.io/instrument-with-beyla: "true"`. Apps without the label
are never instrumented, even though the DaemonSet runs on every
non-Fargate node.

Design highlights (ADR 0031 in estabilis-platform-tools):

- Deploys to existing `grafana` namespace (already PSS=privileged via
  `inject-pss-privileged`, ResourceQuota headroom, AppProject
  destination — zero platform-side policy / quota / project changes).
- Image pinned by digest
  `sha256:d978d84eff1d54e1a185c6f4efe515b546e6754517c1834361ef57559e5628ed`.
- Explicit `resources.limits.memory: 1Gi` overrides the platform
  LimitRange default (128Mi). Without it, BPF map allocation OOMs at
  startup with `cannot allocate memory` from `cilium/ebpf` before any
  tracer attaches.
- `BEYLA_KUBE_CLUSTER_NAME` env passed via helm.parameters from
  `global.clusterName`. Chart RBAC excludes `kube-system/aws-auth` so
  EKS auto-detection fails; setting it explicitly is the supported
  path.
- `/sys/fs/bpf` hostPath bind mount for `log_enricher` and
  `profile_correlation` features.
- `nodeAffinity` excludes Fargate (no eBPF) and requires `amd64` (no
  validated arm64 path in v3.9.x).
- OTLP push for both metrics and traces to in-cluster Alloy `:4317` —
  depends on the Alloy fix above.
- Sync-wave 9, after `grafana-stack` (wave 8).

Refs estabilis-platform-tools#207 / PR #149,
estabilis-platform-tools#208 / PR #209 (ADR 0031).

### Added — `components.beyla: false` default

`bootstrap/platform-root/values.yaml` adds `beyla: false` to the
observability section. Existing clusters are unaffected; the
component activates only when explicitly flipped to `true`.

## [0.39.2] - 2026-05-03

Five bundled fixes around the Grafana stack, all triggered by the
2026-05-03 audit on the first AWS prd cluster. Each was validated
end-to-end live before commit; the cluster has been carrying the
matching live patches under disabled auto-sync since then.

### Fixed — `ArgoCD / Application / Overview` table data links

Four table panels (Unhealthy Applications, Out Of Sync Applications,
Applications That Failed to Sync, Applications With Auto Sync Disabled)
shipped with a global "Go To Application" link pointing at
https://github.com/adinhodovic/argo-cd-mixin?tab=readme-ov-file#argocd-badges.
Replaced with per-column data links (Application / Application
Namespace / Project) using a `__ARGOCD_URL__` placeholder that the
chart substitutes at render time.

#### `core/components/grafana-dashboards`

- `files/argocd-application.json`: 12 placeholders inserted (4 panels × 3
  columns), each producing the right ArgoCD UI URL via Grafana variable
  interpolation.
- `templates/dashboards.yaml`: `replace .Values.argocdUrl` substitutes
  placeholders before mounting.
- `values.yaml` (new): documents the value with empty default + opt-in
  degradation note.
- `Chart.yaml`: 0.1.0 → 0.2.0.

#### `bootstrap/platform-root/templates/grafana-dashboards.yaml`

Passes `argocdUrl` from `global.argocdUrl` via helm.parameters.

#### `providers/{aws,azure}/platform-outputs.tf`

Emits `global.argocdUrl` flat string, computed from
`local.argocd_exposures_resolved.external` (when enabled). Empty
otherwise — same opt-in pattern as `global.openaiApiKeyEnabled`.

### Fixed — `Application Sync Result by Application` empty panel

Same dashboard, panel #13. Used `increase(argocd_app_sync_total[$__rate_interval])`
which Grafana resolves to ~5 min for typical 6h time range. Platform
clusters with selfHeal-only sync activity virtually never have a sync
in a 5-minute window, so the panel sat empty even when the underlying
counter clearly had values. Replaced `[$__rate_interval]` with `[1h]`
hardcoded — captures sparse activity without losing temporal precision
when activity is high.

### Fixed — Sync/Health status colours per ArgoCD UI semantics

Same dashboard, panels #12 and #11.

- `Application Sync Status by Application`: Synced → green, OutOfSync →
  yellow (matched ArgoCD UI conventions; defaults were Grafana's
  auto-assigned palette).
- `Application Health Status by Application`: Progressing →
  rgb(13, 173, 234) blue (operator-supplied to match ArgoCD UI's
  progressing blue). Other states keep auto-assigned colours — only
  Progressing was explicitly requested.

`byRegexp` matcher with the `$` anchor avoids matching false positives
where application names happen to contain the status words.

### Fixed — Mimir `query_frontend` OOMKill loop

`core/components/grafana-stack/mimir-values.yaml`. Live incident on the
first AWS prd cluster: both query_frontend pods OOMKilled in a loop
(5 restarts in 24 h, exit 137). Symptom on Grafana side was HTTP 502
Bad Gateway from the mimir gateway nginx whenever a moderate-cardinality
panel was viewed (e.g. `gRPC Requests Handled` on `ArgoCD / Operational
/ Overview`). Diagnosis chain: gateway nginx logged
`upstream prematurely closed connection` while reading from
`http://<query-frontend-svc>:8080/prometheus/api/v1/query_range`, and
the querier in turn logged
`error notifying frontend ... connection refused` because the frontend
pod went away mid-response.

Live data behind the failing query: 3817 `grpc_server_handled_total`
series, ~1411 effective combinations per timestamp (17 grpc_service x
83 grpc_method x 17 grpc_code), 360 timestamps for a 6h step=60 query.
Parsing/aggregation buffer in query-frontend peaked above 128Mi.

#### Bumps

- `query_frontend.resources.requests.memory`: 64Mi → 128Mi (matches
  realistic working-set so Karpenter reserves accurately).
- `query_frontend.resources.limits.memory`: 128Mi → 384Mi (3× former,
  ~14× idle, leaves headroom for moderate-cardinality queries).

After the live patch with the same values, the failing query returned
HTTP 200 with 20 series / 1118 non-zero data points in 4 s; the new
pods came up clean (0 restarts) at idle ~27Mi (request 128Mi reserved).

### Added — `docs/research/grafana-official-dashboards.md`

New file documenting the audit of which Grafana products are running in
the platform stack and which official self-monitoring dashboards exist
for each (46 installable across the 6 products: Mimir, Loki, Tempo,
Pyroscope, Alloy, Grafana itself). Validates the mixin compile
toolchain end-to-end (jsonnet + jb + mixtool from `go install`),
confirms all 38 generated JSONs parse as valid Grafana dashboards.
Surfaces 6 caveats and 5 deferred decisions (install scope, build
pipeline, schemaVersion modernisation, datasource pre-substitution,
folder taxonomy) so a future operator picking this back up has a
complete starting point.

No installation done in this release — the doc explicitly defers the
work. Lives under `docs/research/` (new directory) — appropriate
location for work that's product-agnostic but cluster-realistic and
needs a human decision before becoming chart code.

### Potentially breaking — Mimir Alertmanager datasource URL changed

The `Mimir Alertmanager` datasource URL in `grafana-values.yaml` was
already changed from `…/alertmanager` to gateway root in v0.39.0 (the
data-links commit on this PR re-affirmed it). With the `/alertmanager`
suffix the Grafana proxy hit Mimir's deprecated AM v1 API and returned
HTTP 410. Existing operators viewing the Contact Points UI under the
Mimir Alertmanager dropdown would have seen empty content; now they
see real data. ArgoCD rewrites the ConfigMap on the next sync of the
`grafana` Application; Grafana picks up the new URL on the next pod
restart. No user action required.

## [0.39.1] - 2026-05-03

### Fixed — drop unused `null` receiver from Alertmanager config template

`core/components/mimir-alertmanager-config/files/alertmanager.yaml.tpl`
shipped a placeholder `- name: 'null'` receiver under the assumption
the Alertmanager config validator required every defined receiver to
be present even when not referenced by any route. That assumption was
wrong: the validator only checks the inverse direction (every receiver
referenced in a route must be defined). An unused receiver is allowed
but creates a confusing UX in the Grafana Alerting UI — operators see
4 contact points (slack-critical/warnings/info + null) under the
Mimir Alertmanager dropdown instead of the 3 actual destinations.

Validated 2026-05-03 on the first AWS prd deployment by re-uploading
the template without the null block via `mimirtool alertmanager load`
and confirming the AM API returns only the 3 Slack receivers. Chart
bumps `0.1.0` → `0.1.1`.

## [0.39.0] - 2026-05-03

### Added — Mimir Alertmanager tenant config + Grafana NGAlert routing standard

Defines and ships the platform standard for alert routing: Mimir
Alertmanager is the single source of truth for both Mimir-Ruler-managed
and Grafana-managed alert rules. Validated end-to-end on the first AWS
prd deployment ahead of this release (synthetic alerts at tier 1/2/3
delivered to Slack via the new pipeline; Grafana-managed alerts route
through Mimir AM via the NGAlert external mode).

The pipeline mirrors the openai_api_key gating pattern: when the
operator opts in (`slack_alerting_enabled = true` in tfvars), terraform
creates 3 SM secrets and the new chart renders the K8s side; when off,
zero resources are rendered and zero SecretSyncError noise appears in
the cluster.

#### `core/components/mimir-alertmanager-config` (new chart, v0.1.0)

Two pieces under one chart, each independently gated:

  1. Slack alerting pipeline (`slack.enabled`, default false; flipped
     to true on AWS via the `global.slackAlertingEnabled` flag from
     `providers/aws/platform-outputs.tf`):
     - ConfigMap with the Alertmanager YAML config TEMPLATE — channel
       names, tier-based routing tree, `inhibit_rules` (a critical
       alert silences related warning/info on same alertname+namespace),
       receivers with title/text Slack templates.
     - ExternalSecret pulling 3 webhook URLs from the platform secret
       store into K8s Secret `alertmanager-slack-webhooks` (one key per
       channel: critical/warnings/info).
     - PostSync Job pipeline (busybox initContainer for placeholder
       substitution → `grafana/mimirtool:3.0.6` main container for
       `alertmanager load`). Idempotent.

  2. Grafana NGAlert "external Alertmanager" mode
     (`grafanaExternalAm.enabled`, default true — chart-level standard,
     applies regardless of Slack config):
     - PostSync Job that POSTs `alertmanagersChoice=external` +
       `external_alertmanager_uid=mimir-alertmanager` to Grafana's
       `/api/v1/ngalert/admin_config` endpoint. Survives a CNPG
       recreate (the setting persists in DB normally; the Job recovers
       it on a fresh cluster bootstrap).

Why one chart instead of two: both configure the SAME architectural
decision ("Mimir AM is the single source of truth for alert routing");
splitting them adds an ArgoCD Application + sync ordering concerns
without isolating any independent failure mode.

Default routing tier-based (matches `mimir-rules` chart labels):
  - tier 1 → slack-critical (group_wait 0s, repeat 1h, continue:true)
  - tier 2 → slack-warnings (group_wait 30s, repeat 4h)
  - tier 3 → slack-info (group_wait 30s, repeat 12h, send_resolved:false)

Template gotcha (documented inline in `files/alertmanager.yaml.tpl`):
Alertmanager runtime template engine does NOT include Sprig's `default`
function. Use `or` (text/template builtin) for missing-label fallbacks
— validated 2026-05-03 by `function "default" not defined` notify
error on the first deployment.

Fallback config bypass (documented inline in `templates/upload-job.yaml`):
Mimir's `-config.expand-env=true` flag interpolates env vars in the
*global* mimir.yaml ONLY — NOT in the Alertmanager fallback config
file. Confirmed by reading `pkg/alertmanager/multitenant.go` on
grafana/mimir main: `os.ReadFile()` is raw, no expansion. So the
"override fallbackConfig + extraEnvFrom" approach doesn't work and
secrets must be inlined at upload time via the Job.

#### `core/components/grafana-stack/grafana-values.yaml`

Two datasource updates that surface Mimir alerting in the Grafana UI
natively, without the user toggling datasource view or selecting a
non-default Alertmanager from the dropdown:

  - **Mimir** (prometheus type):
    - `manageAlerts: true` + `manageAlertingRules: true` — Alert rules
      tab natively shows the mimir-rules groups
    - `prometheusType: Mimir` + `prometheusVersion: "3.0.1"` — tells
      Grafana this Prometheus is Mimir-flavored so it uses the Mimir
      Ruler config API (`/config/v1/rules/<ns>`) for write operations.
      Validated via `/api/datasources/uid/mimir/health` reporting
      `features.rulerApiEnabled: true`. Lets users create/edit "Data
      source-managed" rules directly in the UI.

  - **Mimir Alertmanager** (alertmanager type):
    - URL changed from `.../alertmanager` to gateway ROOT
      `http://grafana-mimir-gateway.grafana.svc.cluster.local`. The
      Grafana proxy calls `<url>/api/v1/alerts` for tenant config; with
      the `/alertmanager` suffix the call hit Mimir's deprecated AM v1
      API and returned HTTP 410. Root URL routes correctly to the
      multitenant config endpoint. POTENTIALLY BREAKING for any
      operator who hardcoded the old URL elsewhere.
    - `manageAlerts: true` + `handleGrafanaManagedAlerts: true` — Contact
      points / Notification policies UI tabs surface Mimir AM's
      receivers and routing tree (combined with the new chart's
      `mimir-alertmanager-config-upload` Job that loads the tenant
      config), and Grafana NGAlert auto-discovers this datasource as
      the dispatch target for Grafana-managed alerts.

#### `providers/aws/variables.tf`

Four new variables (one toggle + 3 sensitive URLs) declared exactly
the same shape as `openai_api_key`:

  - `slack_alerting_enabled` (bool, default false) — non-sensitive,
    operator sets in `terraform.tfvars` alongside `vault_enabled`.
  - `slack_webhook_alertmanager_critical|warnings|info` (string,
    sensitive, default "") — operator sets in `secrets.auto.tfvars`.

#### `providers/aws/secrets-manager.tf`

Three `aws_secretsmanager_secret` + `_secret_version` +
`_secret_policy` resources at
`estabilis/<deployment_id>/platform-alertmanager-slack-{critical,warnings,info}`,
each gated by
`var.slack_alerting_enabled && var.slack_webhook_alertmanager_X != ""`.
ESO IRSA already authorises GetSecretValue on the path prefix — no IAM
update required.

#### `providers/aws/platform-outputs.tf`

Adds `global.slackAlertingEnabled = tostring(var.slack_alerting_enabled)`
to the platform-infrastructure ConfigMap, the bridge that flows the
boolean from terraform into the platform-root chart's helm.parameters
and from there into the new chart's `slack.enabled` value.

#### `providers/aws/secrets.auto.tfvars.example`

Three placeholder lines for the webhook URLs with comment pointing the
operator to set the toggle in `terraform.tfvars` (knob ≠ secret).

#### `bootstrap/platform-root/templates/grafana-stack.yaml`

New Application `mimir-alertmanager-config` (sync-wave 8, project
`platform`, destination `grafana` ns), gated by
`components.mimir-alertmanager-config: false` for downstream opt-out.
Helm parameters injected from platform-root values:
  - Always: `slack.enabled` from `global.slackAlertingEnabled`
  - AWS only: `kvSecrets.slackWebhook{Critical,Warnings,Info}` with
    full `estabilis/<deploymentId>/...` path prefix (mirrors the
    `kvSecrets` pattern in core/components/platform-secrets).

#### Validation done on the first AWS prd deployment

Before this release, the live cluster had:
  - All chart files applied via `kubectl apply -f` from a hub-app dir
    in the client gitops repo (raw YAML).
  - 3 SM secrets created via a standalone `alertmanager-slack.tf` in
    the client repo (downstream-only).
  - Grafana datasource flags patched in-cluster via `kubectl patch`.
  - `alertmanagersChoice=external` set via Grafana UI manually.

Each piece validated separately end-to-end:
  - `mimirtool alertmanager load` Job: 77 lines rendered, 3 webhook
    URLs substituted, exit 0.
  - 3 synthetic alerts (one per tier) delivered to Slack with correct
    color/format. `cortex_alertmanager_notifications_failed_total{slack}`
    stayed at 3 (historical pre-fix failures); 4 new successes after.
  - Grafana datasource `/api/datasources/uid/mimir/health`:
    `features.rulerApiEnabled: true`.
  - Grafana datasource `/api/datasources/proxy/uid/mimir-alertmanager/api/v2/status`:
    receivers visible (slack-critical, slack-warnings, slack-info, null).
  - Grafana NGAlert `/api/v1/ngalert/admin_config`:
    `{"alertmanagersChoice":"external"}`.

After this release, the downstream client repo can drop the standalone
`alertmanager-slack.tf`, the hub-app manifests dir, and the
in-overrides datasource block — the upstream module + chart provide
identical behaviour from a single platform bump.

#### Caveat — `Mimir Alertmanager` datasource URL change

Existing AWS deployments on v0.38.0 and earlier had the URL as
`http://grafana-mimir-gateway.grafana.svc.cluster.local/alertmanager`.
v0.39.0 changes it to the gateway root. ArgoCD will rewrite the
ConfigMap on the next sync of the `grafana` Application. No manual
migration needed — the URL change only affects the Grafana proxy path
for the AM config endpoint, which was returning HTTP 410 before
anyway. Runtime AM endpoints (alerts, silences, status) are still
served correctly because Grafana with `implementation: mimir` knows to
prefix `/alertmanager/api/v2/*` for those.

## [0.38.0] - 2026-05-03

### Fixed — Mimir alerting rules never reached the Ruler on AWS

`core/components/mimir-rules` previously relied on the Ruler pod
mounting the `mimir-alerting-rules` ConfigMap directly at
`/data/rules/anonymous/` (extraVolumeMounts in
`core/components/grafana-stack/mimir-values.yaml`). That mount only
takes effect while the Ruler is configured with
`ruler_storage.backend = local` — the default kept by the Azure
overlay. The AWS overlay
(`core/components/grafana-stack/mimir-values-aws.yaml`) flips the
backend to `s3` because the Mimir chart validator rejects sharing a
bucket between blocks/ruler/alertmanager without distinct
`storage_prefix` per class. Once the Ruler is backed by S3 the local
mount is dead weight: nothing reads `/data/rules`, the bucket prefix
stays empty, and `GET /prometheus/api/v1/rules` returns
`groups: []` for every tenant. Symptom on the first AWS prd cluster:
0 of 33 platform alerting rules loaded vs the same 33 on Azure HML.

#### `core/components/mimir-rules`

- Reintroduce a PostSync `Job` that uses `grafana/mimirtool:3.0.6`
  to call `rules sync` against the in-cluster gateway and persist
  rule groups into whichever backend the Ruler is configured for.
  Image matches the Mimir 3.0.x server line so the protocol/API
  stays consistent.
- Job is gated by `uploadJob.enabled` (default `false`) so Azure
  clusters keep using the cheaper mount-based path untouched. The
  arg list mirrors the `ruleGroups`/`customRuleGroups` keys so
  disabling a tier removes both the ConfigMap key and the Job arg.
- Bump `Chart.yaml` 0.1.0 → 0.2.0 (new templated resource).

#### `core/components/mimir-rules/values-aws.yaml` (new)

- Flips `uploadJob.enabled` to `true`. The header comment references
  the Mimir chart `storage_prefix` constraint that drove the S3
  switch, so a future reader doesn't try to "simplify" the AWS
  overlay back to local-filesystem.

#### `core/components/mimir-rules/values-azure.yaml` (new)

- Empty placeholder (`{}`). Required because
  `bootstrap/platform-root/templates/grafana-stack.yaml` now loads
  `values-{provider}.yaml` unconditionally, and on clusters without
  an overrides repo the `platform-root.ignoreMissingValueFiles`
  helper isn't emitted (it only fires when overrides are enabled).
  A missing `values-azure.yaml` would then break ArgoCD sync. The
  file is opt-in for the same reason `mimir-values-azure.yaml`
  exists alongside `mimir-values-aws.yaml` in `grafana-stack`.

#### `bootstrap/platform-root/templates/grafana-stack.yaml`

- Add `$values/core/components/mimir-rules/values-{provider}.yaml`
  to the `mimir-rules` Application's `valueFiles`, mirroring the
  pattern already used for `mimir-values-{provider}.yaml` in the
  `grafana-mimir` Application.

#### Validation captured before merge

Patch was applied directly to the AWS prd cluster (auto-sync briefly
disabled on the `mimir-rules` Application, restored after). Job pod
completed in ~5s, exit 0; `mimirtool` log showed `Sync Summary: 3
Groups Created, 0 Updated, 0 Deleted`. Ruler API for tenant
`anonymous` then returned 3 rule groups / 33 rules (13 + 14 + 6),
matching Azure HML. S3 prefix `ruler/rules/anonymous/` was populated
with the three base64-encoded namespace/group objects. A second run
with the same image was idempotent (`0 Created, 0 Updated, 0
Deleted`), confirming repeated PostSync triggers won't churn rules.

## [0.37.0] - 2026-04-30

### Added — observability stack completeness sweep

Audit on cortex prd 2026-04-30 found 10 distinct visibility gaps in
the alloy → Mimir pipeline. None blocked anything functionally — they
just meant the corresponding Grafana dashboards had no data. This
release closes them all + raises the Mimir tenant series limit so the
extra scrapes don't get dropped.

#### alloy — new scrape jobs

  argocd-applicationset-controller    pod discovery, port 8080
  trivy-server                         svc trivy-service:4954
  vault                                svc vault-active:8200/v1/sys/metrics
  mimir-self                           pod discovery (label name=mimir, port 8080)
  loki-self                            pod discovery (label name=loki, port 3100)
  grafana-self                         pod discovery (label name=grafana, port 3000)
  tempo-self                           pod discovery (label name=tempo, port 3100)
  pyroscope-self                       pod discovery (label name=pyroscope, port 4040)
  alloy-self                           pod discovery (label name=alloy, port 12345; clustering disabled — every replica reports its own state)

#### alloy — fixed external-secrets target

The previous scrape target `external-secrets-metrics.external-secrets.svc.cluster.local:8080`
referenced a Service that does NOT exist in the chart. The actual
controller pod listens on container port 8080. Switched to pod-discovery
(role=pod, namespace=external-secrets, label app.kubernetes.io/name=
external-secrets) which targets the controller pod's IP directly.

#### vault — `unauthenticated_metrics_access`

Vault's `/v1/sys/metrics` endpoint returns 403 by default. Without
authentication, alloy can't scrape — and threading a Vault token
through alloy adds a TTL/rotation problem we don't need for an
in-cluster scrape that's already restricted by NetworkPolicy
(`allow-vault` already pinned port 8200 to grafana ns only).

Adds the `telemetry { unauthenticated_metrics_access = true }` block
inside the `listener "tcp"` HCL stanza, in BOTH the AWS and Azure
provider branches of `bootstrap/platform-root/templates/vault.yaml`.

Reference: HashiCorp docs note that the metrics endpoint exposes
operational counters/gauges only — no secrets.

#### mimir — `max_global_series_per_user` 150k → 500k

The Mimir default per-tenant active-series cap of 150,000 was too low
for a cluster with KSM + kyverno + cnpg + alloy + 6-component grafana
self-monitoring. Direct evidence from cortex prd 2026-04-30 alloy
logs:

    "non-recoverable error ... err='per-user series limit of 150000
     exceeded (err-mimir-max-series-per-user)' ... 2000 samples failed"

Existing scrape pipelines (kyverno_*, cnpg_*) had samples silently
dropped — the metrics appeared in `/api/v1/label/__name__/values`
(stale index) but `count({__name__=~"kyverno_.*"})` returned 0 series.

Bumped to 500,000 — covers KSM (~50k) + kyverno (~30k) + cnpg (~10k)
+ alloy/mimir/loki self-monitoring (~80k) + cortex apps (~20k) with
4× headroom for high-cardinality histograms.

#### Downstream propagation

NetworkPolicy fixes for cert-manager / cnpg-system / trivy-system
ship in `Estabilis/estabilis-platform-gitops` v0.39.7 (PR #38).
Bumping `platform_version` to v0.37.0 + `platformGitopsVersion` to
v0.39.7 in a client repo unlocks the full visibility sweep.

## [0.36.10] - 2026-04-30

### Fixed — alloy KSM namespace label rewrite destroyed pod namespace info

`core/components/grafana-stack/alloy-values.yaml` removes the
`prometheus.relabel "kube_state_metrics"` rule that overrode
`namespace = "kube-state-metrics"` on every metric scraped from KSM.

The rule was introduced in commit d4eed7a (2026-03-13, "feat: add
kube-state-metrics and OpenCost/KSM scrape jobs in Alloy") alongside
an analogous rule for OpenCost. The OpenCost rule remains untouched
because the OpenCost pod's metrics ARE about itself
(`namespace="opencost"` is correct). KSM is different: it reports
about OTHER pods — each metric carries the real pod's namespace
natively, and overwriting it destroys the information.

Effect on every cluster running this chart pre-v0.36.10:

  count by (namespace) (kube_pod_container_resource_requests)
  → only one bucket: namespace="kube-state-metrics"

Real namespace values (`kube-system`, `app-*`, `cnpg-system`, ...)
were absent from the namespace label of every `kube_*` metric.

Tools silently broken:
  - KRR / Goldilocks / VPA-style sizing — KRR's cluster-summary
    query `sum(kube_pod_container_resource_requests{namespace=
    "kube-system",...})` returned zero results, KRR aborted.
  - Grafana dashboards filtering `kube_*` by namespace mixed all
    namespaces into one bucket.
  - Cost-allocation dashboards (opencost / kubecost) using KSM
    attributed all costs to `kube-state-metrics` namespace.
  - Mimir alerts on `kube_pod_*{namespace="X"}` had silent miss.

Discovered 2026-04-30 when KRR ran against cortex prd:

  [WARNING] Error: Expected exactly one result from Prometheus query
  but instead got 0. sum(kube_pod_container_resource_requests
  {namespace="kube-system", resource="memory"})
  [CRITICAL] No objects available to scan.

Direct Mimir confirmation showed all 288 `kube_pod_container_resource_
requests` series carrying `namespace="kube-state-metrics"`.

Verified at runtime on cortex prd via the local override workaround
in [Cortex-Innovation/cortex-platform-aws-us-east-1-prd#46](https://github.com/Cortex-Innovation/cortex-platform-aws-us-east-1-prd/pull/46):
after the same one-rule deletion, Mimir returned 36 distinct
namespaces. Cortex prd's local override should be dropped once the
cluster bumps `platform_version` to v0.36.10+.

Inline comment added in alloy-values.yaml warning future operators
not to re-add the rule.

## [0.36.9] - 2026-04-30

### Fixed — argocd controller worker tunables actually reach the running pod

`core/components/argocd/values.yaml` now sets `controller.extraArgs`
instead of `controller.args`. The argocd helm chart (9.5.x
`statefulset.yaml`) only renders `extraArgs` — `args` is silently
dropped at template time. The intended `--status-processors=50` and
`--operation-processors=25` sizing introduced in commit 6c217ff
(2026-04-25, "feat(argocd): bump resources to fit ~40-App platform
deployment") has never reached any client cluster running this
chart since that commit. Every bootstrap fell back to the
argocd-application-controller binary defaults:

- `--status-processors=20`
- `--operation-processors=10`

Symptom: when ApplicationSet emits 30+ children simultaneously
during cluster bootstrap, the operation processing queue stalls for
minutes. Sync requests pile up; argocd-server times out waiting for
controller responses; UI loads indefinitely; users perceive the
control plane as dead. Verified on cortex prd 2026-04-30 — peak
controller-1 memory hit 87% of the 2Gi limit during a 20-app sync
wave (incremental, not full bootstrap), and the actual bootstrap
the day before exhibited the symptom that motivated this fix.

Confirmed via `helm template` against chart 9.5.6:

  controller.extraArgs:[--status-processors=50,...]  → rendered ✓
  controller.args:[--status-processors=50,...]       → ignored ✗

And via `kubectl get sts argocd-application-controller -o jsonpath
='{.spec.template.spec.containers[0].args}'` on the running cluster
before/after the fix.

Downstream propagation: clients pinned to v0.36.7/v0.36.8 should
either bump `platform_version` to v0.36.9 OR add `controller.extraArgs`
in their per-cluster `overrides/argocd/values.yaml` as an immediate
hotfix (cortex prd already applied the override on 2026-04-30 in
[Cortex-Innovation/cortex-platform-aws-us-east-1-prd#44](https://github.com/Cortex-Innovation/cortex-platform-aws-us-east-1-prd/pull/44);
that override should be dropped once cortex prd is bumped to
v0.36.9+).

## [0.36.8] - 2026-04-30

### Fixed — `grafana-llm-provisioning` ConfigMap rendered unconditionally

`core/components/platform-secrets/templates/grafana.yaml` now renders
the `grafana-llm-provisioning` ConfigMap on every deployment regardless
of `openaiApiKeyEnabled`. Only the `grafana-llm-credentials`
ExternalSecret remains gated.

Why this matters. v0.36.4 (commit 758d88b, PR #137) introduced a single
`{{- if .Values.openaiApiKeyEnabled }}` wrapping both the LLM
ExternalSecret and the LLM provisioning ConfigMap. The motivating bug
was real for the ExternalSecret — without the source secret in
AWS SM / Azure KV (TF gate `count = var.openai_api_key != "" ? 1 : 0`),
ESO reconciles forever with "Secret does not exist" errors. But the
gate was applied symmetrically to a resource that didn't have the same
dependency: the ConfigMap is just static plugin provisioning YAML, no
external dependency.

That over-gate broke deployments without an OpenAI key. The Grafana
pod template (`core/components/grafana-stack/grafana-values.yaml`)
declares the ConfigMap mount unconditionally:

```yaml
extraConfigmapMounts:
  - name: llm-provisioning
    configMap: grafana-llm-provisioning   # no `optional: true`
```

When `openaiApiKeyEnabled=false` rendered no ConfigMap, the volume
mount referenced a non-existent object → pod failed to start. Cortex
PRD postmortem 2026-04-30: an out-of-band ConfigMap was created
manually with `disabled: true`, which then triggered Grafana 12.3.1's
`grafana-llm-app v1.0.8` refusal — the plugin has `auto_enabled: true`
in its `plugin.json` and rejects `disabled: true` in provisioning,
crashing the boot with `app provisioning error: plugin is auto enabled
and cannot be disabled: grafana-llm-app`. The hot-fix was to flip the
ConfigMap to `disabled: false` and accept that the plugin starts idle
without an API key.

Why the fix is asymmetric (CM unconditional, ES gated). The
ExternalSecret has an external dependency (source secret in
SM / KV) that's only created when `var.openai_api_key != ""`. Rendering
it without that source guarantees a perpetual ESO reconcile error. The
ConfigMap has no such dependency: it always points at
`${OPENAI_API_KEY}`, an env var that resolves through
`envFromSecrets[grafana-llm-credentials].optional: true`. Missing
secret → empty env → plugin auto-enables and runs idle (no UI feature,
no log spam, no crash). Cost: ~5s extra plugin install on boot,
~12 MB on disk.

Files. `core/components/platform-secrets/templates/grafana.yaml`,
`VERSION`, `CHANGELOG.md`.

To pick up after release. Cortex PRD downstream bumps `platform_version`
to v0.36.8 in `providers/aws/terraform.tfvars` + `main.tf` ref, then
`estabilis promote cortex -d platform-aws-us-east-1-prd --force-refresh`.
The out-of-band `estabilis.io/temporary: "true"` annotation on the
existing CM is replaced by the chart's metadata via SSA — no manual
cleanup.

## [0.36.6] - 2026-04-30

### Fixed — `argocd-secret` data immune to spurious reconciliation

`bootstrap/platform-root/templates/argocd.yaml` now declares
`ignoreDifferences` for `Secret/argocd-secret`'s `.data` jqPath,
matching the existing pattern used for AKS `admissionsenforcer` webhook
drift on Mutating/Validating WebhookConfigurations.

The field is owned by `argocd-server` (it auto-populates
`server.secretkey`, `admin.password`, `admin.passwordMtime` on first
start). The chart `argo-cd 9.5.6` deliberately renders the Secret
WITHOUT a `data:` block when no optional (argocdServerAdminPassword,
extra, webhook secrets...) is set — so SSA preserves data in steady
state.

The hidden risk is during rolling restarts of argocd-server. Cortex prd
postmortem 2026-04-30: a self-managed sync changed the Deployment
template (tolerations + podAntiAffinity dropped after Azure→AWS
provider transition), rolled new pods. New pod's
`util/settings/settings.go:InitializeSettings` checks
`cdSettings.ServerSignature == nil`. If `argoCDSecret.Data` is empty in
the informer cache during the brief startup window, the function
regenerates `server.secretkey` from scratch — invalidating every JWT
in flight. Symptom on UI: `server.secretkey is missing` /
`invalid session: token signature is invalid` floods.

Pinning `.data` via `ignoreDifferences` makes the field fully owned by
argocd-server and immune to ArgoCD ever attempting to reconcile it.
Even if a future operator deletes the Secret manually, argocd-server
regenerates exactly once on the next pod startup and ArgoCD does not
fight that regeneration with a stale render.

This is hardening only — no observable change on a steady-state
cluster. Effect kicks in on the next argocd-server rolling restart.

### Files

- `VERSION` (→ v0.36.6)
- `bootstrap/platform-root/templates/argocd.yaml` (+ ignoreDifferences for argocd-secret data)
- `CHANGELOG.md` (this entry)

## [0.36.5] - 2026-04-30

### Added — Pass `vault.enabled` to `cluster-secret-store` chart

`bootstrap/platform-root/templates/cluster-secret-store.yaml` now
forwards the `components.vault` toggle as the `vault.enabled` helm
parameter to the gitops `cluster-secret-store` chart (>= v0.39.3),
which renders an additional Vault-backed ClusterSecretStore named
`app-secret-store` when activated.

Default off (`components.vault: false` in platform-root values). When
a downstream client opts in (`components.vault: true`), the same
toggle that activates the Vault StatefulSet now also wires the
`app-secret-store` so apps relying on the cortex `common-app`
convention (`externalSecrets.storeName: app-secret-store`) start
syncing immediately. No second toggle to forget.

Cortex prd 2026-04-30 postmortem: 19 ExternalSecrets in `app-*`
namespaces stuck on `SecretSyncedError` because the chart had only
AWS / Azure branches; this release closes the loop.

### Changed — Bump `platformGitopsVersion` default to v0.39.3

Pulls in the new `cluster-secret-store-vault.yaml` template from
[estabilis-platform-gitops v0.39.3](https://github.com/Estabilis/estabilis-platform-gitops/releases/tag/v0.39.3).

### Files

- `VERSION` (→ v0.36.5)
- `bootstrap/platform-root/templates/cluster-secret-store.yaml` (+ `vault.enabled` parameter)
- `bootstrap/platform-root/values.yaml` (`platformGitopsVersion` → v0.39.3)
- `CHANGELOG.md` (this entry)

## [0.36.4] - 2026-04-30

### Fixed — gate `grafana-llm-credentials` ExternalSecret on `openai_api_key`

`core/components/platform-secrets/templates/grafana.yaml` was rendering
the `grafana-llm-credentials` ExternalSecret + `grafana-llm-provisioning`
ConfigMap unconditionally, while the matching source secret in AWS
Secrets Manager / Azure Key Vault is only created when
`var.openai_api_key != ""` (TF gate
`count = var.openai_api_key != "" ? 1 : 0`).

Result on deployments that didn't populate the OpenAI key (the default —
cortex prd 2026-04-30 case): ESO reconciled the ExternalSecret
forever, producing continuous `error processing spec.data[0] (key:
estabilis/<deployment>/platform-openai-api-key), err: Secret does not
exist` events in the `grafana` namespace.

Fix flows a boolean flag through the existing GitOps Bridge pipeline
already used for `githubAppEnabled` / `opencostEnabled`:

1. `providers/{aws,azure}/platform-outputs.tf`: write
   `"global.openaiApiKeyEnabled" = tostring(var.openai_api_key != "")`
   to the `platform-infrastructure` ConfigMap.
2. CLI's `params.py` reads the ConfigMap and the value flows into the
   platform-root Application as `.Values.global.openaiApiKeyEnabled`
   (no CLI change — generic `params.items()` loop already handles new
   keys).
3. `bootstrap/platform-root/templates/platform-secrets.yaml`: passes
   the flag as the `openaiApiKeyEnabled` helm parameter.
4. `core/components/platform-secrets/templates/grafana.yaml`: wraps
   the two LLM resources in `{{- if .Values.openaiApiKeyEnabled }}`.

The actual API key is **never** flowed through the ConfigMap (which is
plaintext k8s data) — only the boolean. The key remains in
`secrets.auto.tfvars` (sensitive) and AWS Secrets Manager / Azure Key
Vault on the source side.

To enable Grafana LLM after this release: set `openai_api_key = "sk-..."`
in `secrets.auto.tfvars`, run `terraform apply`. Both the source secret
AND the ExternalSecret + ConfigMap come up together.

### Files

- `VERSION` (→ v0.36.4)
- `providers/aws/platform-outputs.tf` (+ `global.openaiApiKeyEnabled`)
- `providers/azure/platform-outputs.tf` (+ `global.openaiApiKeyEnabled`)
- `bootstrap/platform-root/templates/platform-secrets.yaml` (+ helm parameter)
- `core/components/platform-secrets/templates/grafana.yaml` (gate `if`)
- `core/components/platform-secrets/values.yaml` (default `openaiApiKeyEnabled: false`)
- `CHANGELOG.md` (this entry)

## [0.36.3] - 2026-04-30

### Fixed — `external-secrets` webhook field-manager fight (cert-manager mode)

`bootstrap/platform-root/templates/external-secrets.yaml`: adds three
helm parameters that flip the chart from its bundled cert-controller
to **cert-manager mode**:

- `webhook.certManager.enabled=true`
- `webhook.certManager.cert.issuerRef.kind=ClusterIssuer`
- `webhook.certManager.cert.issuerRef.name=selfsigned`

The bundled cert-controller writes the webhook `caBundle` via `Update`
(full PUT). ArgoCD reconciles the same ValidatingWebhookConfiguration
via `ServerSideApply`. The two operations race on `resourceVersion`,
producing a continuous stream of HTTP 409 conflicts and 50+ rv
increments/second on the cluster-scoped webhook configurations
(observed on cortex prd 2026-04-30).

`v0.36.2` only mitigated the **display** of the diff via
`ignoreDifferences[caBundle]` + `RespectIgnoreDifferences=true` — the
underlying race continued. This release eliminates the race at the
source by stopping the bundled cert-controller entirely; cainjector
populates `caBundle` via `Apply` (SSA), coexisting cleanly with
ArgoCD's reconciliation.

The chart creates a `Certificate` resource referencing the issuer; the
Issuer itself ships in `cert-manager-config` v0.39.2 (universal
`selfsigned` ClusterIssuer, applies to both Azure and AWS).

The previous `ignoreDifferences[caBundle]` + `RespectIgnoreDifferences=true`
in `external-secrets.yaml` is **kept** as belt-and-suspenders defense
in case the chart ever falls back to bundled cert-controller via
upstream config drift.

### Changed — Bump `platformGitopsVersion` default to v0.39.2

`bootstrap/platform-root/values.yaml`: `platformGitopsVersion:
"v0.39.1"` → `"v0.39.2"`. Pulls in the universal `selfsigned`
ClusterIssuer from gitops `cert-manager-config` referenced by the new
helm parameters above.

See [estabilis-platform-gitops v0.39.2 release notes](https://github.com/Estabilis/estabilis-platform-gitops/releases/tag/v0.39.2).

### Files

- `VERSION` (→ v0.36.3)
- `bootstrap/platform-root/templates/external-secrets.yaml`
- `bootstrap/platform-root/values.yaml` (`platformGitopsVersion` → v0.39.2)
- `CHANGELOG.md` (this entry)

## [0.36.2] - 2026-04-29

### Fixed — `RespectIgnoreDifferences=true` on external-secrets + aws-load-balancer-controller

Two `platform-root` Application templates declared `ignoreDifferences`
for webhook `caBundle` (and, for ALB, the TLS Secret data and
`IngressClassParams` body) but never paired the block with the
matching `RespectIgnoreDifferences=true` syncOption. Without that
syncOption, `ignoreDifferences` only hides diffs in the UI — ArgoCD
keeps re-applying the empty values from Git on every reconcile,
fighting the chart's own cert-controller / webhook self-signing init
(Server-Side Apply field-manager war).

Visible symptom on first AWS deployment of the cortex platform
cluster: `external-secrets` Application oscillating
`OutOfSync → Synced → OutOfSync`, controller pod up but webhook never
stabilizes, `ExternalSecret` / `ClusterSecretStore` CRs unable to
admit, dependent Apps stuck.

This is **not a regression** — the `ignoreDifferences` block was first
introduced in v0.26.2 (commit 2b9dac5) without the syncOption pair, so
both templates have shipped half-broken since then. Cortex is the
first AWS deployment exercising the path that triggers the fight; the
hub/HML Azure deployments stabilized through different timing and
masked the gap.

Files:
- `bootstrap/platform-root/templates/external-secrets.yaml` — add `RespectIgnoreDifferences=true`
- `bootstrap/platform-root/templates/aws-load-balancer-controller.yaml` — add `RespectIgnoreDifferences=true`

Pattern now matches `argocd.yaml`, `kyverno.yaml`, `platform-secrets.yaml`,
and `cert-manager.yaml` (Azure branch), all of which already had the
pair shipped together.

### Files

- `VERSION` (→ v0.36.2)
- `bootstrap/platform-root/templates/external-secrets.yaml`
- `bootstrap/platform-root/templates/aws-load-balancer-controller.yaml`

## [0.36.1] - 2026-04-29

### Fixed — `custom-apps.yaml` AppProject migration to taxonomy v2

`bootstrap/platform-root/templates/custom-apps.yaml` still declared
`project: applications` — an AppProject that was renamed to
`platform-apps` in v0.36.0 (ADR 0027 taxonomy v2). The Application
generated by this template would have failed sync with
`InvalidSpecError` on any cluster that synced `custom-apps` after the
v0.36.0 rollout. Updated to `project: platform-apps` to match the rest
of the chart.

### Changed — Bump `platformGitopsVersion` default to v0.39.1

`bootstrap/platform-root/values.yaml`: `platformGitopsVersion:
"v0.39.0"` → `"v0.39.1"`.

Pulls in the upstream gitops fix for the `allow-metrics-server`
NetworkPolicy port (4443 → 10250). See
[estabilis-platform-gitops v0.39.1 release notes](https://github.com/Estabilis/estabilis-platform-gitops/releases/tag/v0.39.1)
for details. AWS deployments that synced Wave 15 (`network-policies`)
without this fix had their metrics-server APIService stuck at
`Available=False`; this bump propagates the fix to all downstream
consumers automatically once they re-render `platform-root`.

### Files

- `VERSION` (→ v0.36.1)
- `bootstrap/platform-root/values.yaml` (`platformGitopsVersion` → v0.39.1)
- `bootstrap/platform-root/templates/custom-apps.yaml` (`project: applications` → `platform-apps`)

## [0.36.0] - 2026-04-28

### Changed — ADR 0027 taxonomy v2 (rename + add `workload-apps`, no aliases)

Per ADR 0027 (Accepted 2026-04-28), the AppProject taxonomy is
normalized so that every project pairing across cluster types follows
the `<cluster>-<modifier>` symmetry:

| Pre-v2 (deleted) | v2 (current) | Cluster | Owner | Scope |
|---|---|---|---|---|
| `applications` | `platform-apps` | platform | client | apps (`app-*`) |
| _(none)_ | `workload-apps` (NEW) | workload | client | apps (`app-*`) |
| `workload-infra` | `workload-client-infra` | workload | client | system |
| `platform-client-infra` | `platform-client-infra` (kept) | platform | client | system |
| `platform` | `platform` (kept) | platform | ops | system |
| `workload-baseline` | `workload-baseline` (kept) | workload | ops | system |

No backwards-compat aliases — rename is hard. Inner Applications in
client gitops repos that previously declared `project: workload-infra`
or `project: applications` MUST be migrated by the same release window
or sync fails with `InvalidSpecError`. Migration is a `sed` on
`spec.project:` per `application.yaml`.

`bootstrap/platform-root/templates/argocd-project.yaml` is the source
of truth for the 6 projects.

Reference: `estabilis-platform-tools/docs/adr/0027-appproject-taxonomy-and-workload-apps-split.md`
and the §"Concrete app mapping" section for transfero HML's 11-app
migration mapping.

### Changed — `clientApps.autoSync` default flips to `false` (manual sync)

The `automated.{prune,selfHeal}` block on Applications generated by
`hub-client-apps` (this chart) and `client-apps` (workload-bootstrap)
is now gated on `.Values.clientApps.autoSync` and **defaults to
`false`**. Workload Applications stay `OutOfSync` until the operator
or CI pipeline triggers an explicit sync.

Why default manual:

- **Cold-cluster bootstrap is race-free.** Workload Apps no longer
  thrash retry-syncing while ESO/ALB/CNPG/image-updater are still
  coming up.
- **Production-safe by default.** Every workload deploy goes through
  an explicit gate (operator, CI pipeline, argocd-image-updater).
- **Aligns with how workloads are typically deployed on Estabilis:**
  CI builds an image, writes back to gitops, and either triggers
  `argocd app sync` or relies on argocd-image-updater. Operator
  gating happens at the pipeline level.

Set `clientApps.autoSync: true` in `overrides/platform-root/values.yaml`
to opt back into pure GitOps continuous reconciliation per cluster.

The flag forwards from this chart's values into the `workload-bootstrap`
chart's values via the `workload-bootstrap.yaml` Application's helm
parameter, so a single override at the platform-root level toggles
both `client-apps` (workload) and `hub-client-apps` (platform)
ApplicationSets simultaneously.

### Changed — `*-apps` AppProject sourceRepos opt-in

The `platform-apps` and `workload-apps` AppProjects no longer carry a
hardcoded `https://charts.bitnami.com/bitnami` default. Clients
authorize upstream chart hosts explicitly via the wrapper override:

```yaml
# overrides/platform-root/values.yaml
platformAppsExtraSourceRepos:
  - "https://charts.bitnami.com/bitnami"
  - "https://github.com/Cortex-Innovation/helm-charts.git"
workloadAppsExtraSourceRepos:
  - "..."
```

Wildcards are not accepted — every host must be explicit so AppProject
scope creep stays auditable in code review.

### Changed — argo-cd Helm chart bump 9.4.7 → 9.5.6

`bootstrap/platform-root/templates/argocd.yaml`: `targetRevision: "9.4.7"`
→ `"9.5.6"`. Picks up upstream chart 9.5.x (appVersion ArgoCD v3.3.8).
Single `feat(argo-cd): VPA support` between 9.4 and 9.5; opt-in,
non-breaking.

### Changed — bump `platformGitopsVersion` default 0.38.2 → 0.39.0

`bootstrap/platform-root/values.yaml` `platformGitopsVersion: "v0.39.0"`
keeps the platform chart's default in sync with
`estabilis-platform-gitops` v0.39.0 (which ships the matching
`workload-bootstrap` updates: `client-apps` wrapper using
`workload-client-infra` + `clientApps.autoSync: false` default).

## [0.35.3] - 2026-04-28

### Fixed — vpc-cni prefix delegation breaks pod IP allocation in shared VPCs

v0.35.x defaulted `ENABLE_PREFIX_DELEGATION = "true"` for vpc-cni
unconditionally. Prefix delegation allocates `/28` chunks (16 IPs)
instead of individual IPs, raising pod density per node from ~50 to
~110 on c6a.xlarge — but it REQUIRES contiguous /28 blocks available
in every subnet the cluster uses.

In shared VPCs (multiple EKS clusters / RDS / standalone EC2
coexisting in the same /23), available IPs become fragmented across
the subnet. AWS API rejects `AssignPrivateIpAddresses` with:

```
InsufficientCidrBlocks: The specified subnet does not have enough
free cidr blocks to satisfy the request.
```

Karpenter-spawned EC2 nodes register `Ready` (kubelet OK), but pods
stay stuck `ContainerCreating` forever with:

```
failed to setup network for sandbox: plugin type="aws-cni" failed:
failed to assign an IP address to container
```

Observed on cortex-prd 2026-04-28: subnet `subnet-0e7ee2c1d44ff476a`
in shared VPC `vpc-main-tech-services` (us-east-1c, 10.207.4.0/23)
had 377/512 IPs free but fragmented — no contiguous /28 available.
Manual `aws eks update-addon` to set
`ENABLE_PREFIX_DELEGATION=false` unblocked the bring-up.

#### Fix

Inverted default: `ENABLE_PREFIX_DELEGATION = "false"` (mirror legacy
`cortex-eks-prod` — always works in fragmented shared VPCs).
Operators with dedicated VPCs can opt-in for density via the new
variable `var.vpc_cni_enable_prefix_delegation = true` in tfvars.

### Added — NetworkPolicy enforcement on by default

The vpc-cni v1.14+ DaemonSet ships an `aws-network-policy-agent`
sidecar (`aws-eks-nodeagent` container in `aws-node` pod). The
sidecar runs by default, but enforcement is OFF unless
`enableNetworkPolicy = "true"` is set in addon config.

Both legacy `cortex-eks-prod` (eks.tf:50) and the
`estabilis-platform-gitops/components/network-policies/` chart ship
NetworkPolicy CRs assuming an enforcer exists — but v0.35.x left
enforcement OFF, making the policies security theater.

Set `enableNetworkPolicy = "true"` unconditionally in addon config
(no variable — clusters without enforcement are silently insecure;
default should always be ON when policies are deployed). Matches
legacy.

### Migration

Cluster on v0.35.0–v0.35.2: bump `main.tf ref → v0.35.3`,
`terraform init -upgrade`, `terraform plan`. Expected:

- `aws_eks_addon.this[vpc-cni]`: `configuration_values` update
  (adds `enableNetworkPolicy=true`, flips
  `ENABLE_PREFIX_DELEGATION=false`)

`terraform apply` triggers vpc-cni rolling update on all aws-node
pods (~30s on EC2 nodes). Pods already running keep their IPs;
network policies start being enforced immediately. Operators
with NetworkPolicies that have restrictive egress should review
before applying — enforcement going from OFF → ON in a running
cluster can break previously-permissive traffic.

For the cortex-prd 2026-04-28 bring-up: terraform apply will
no-op for prefix delegation (already manually set to false in
v0.35.2 unblock) and add `enableNetworkPolicy=true` (rolling
update). No data plane impact.

## [0.35.2] - 2026-04-28

### Fixed — Fargate log group creation failed with AccessDeniedException

v0.35.1 defaulted `fargate_log_kms_key_arn` to `aws_kms_key.s3_data.arn`,
but that KMS key's policy does not grant `logs.<region>.amazonaws.com`
the `kms:Encrypt*`/`kms:Decrypt*` permissions required by CloudWatch
Logs. Result: `terraform apply` failed on
`aws_cloudwatch_log_group.fargate` with:

```
api error AccessDeniedException: The specified KMS key does not exist
or is not allowed to be used with Arn 'arn:aws:logs:...:log-group:.../fargate'
```

#### Fix

Default changed to **AWS-managed encryption** (no customer-managed KMS
key). Logs are still encrypted at rest — just with the default
`alias/aws/logs` key. Mirrors legacy `cortex-eks-prod` (no customer KMS
on Fargate log group).

Operators wanting customer-managed KMS pass `var.fargate_log_kms_key_arn`
explicitly AND ensure the key policy grants
`logs.<region>.amazonaws.com` access. v0.35.1 description updated to
flag this requirement.

#### No data loss / migration

Operators on v0.35.1 hit the error before any log group was created.
Just bump to v0.35.2 and re-apply.

## [0.35.1] - 2026-04-28

### Fixed — Karpenter on Fargate broken in `autoscaler = "karpenter"` (and hybrid)

v0.35.0 inherited the v21 EKS karpenter sub-module's default
`create_pod_identity_association = true` and the trust policy
hardcoded to `pods.eks.amazonaws.com` only (no IRSA). Pod Identity
**REQUIRES** the `eks-pod-identity-agent` DaemonSet on the node, but
Fargate does not run DaemonSets.

Both `autoscaler = "karpenter"` (pure) and `autoscaler = "hybrid"`
land Karpenter pods on the `karpenter` namespace Fargate profile
(selectors take precedence over MNG nodes), so Pod Identity was
non-functional for Karpenter in **all** our modes — the controller
hung waiting for AWS APIs (`AWS_CONTAINER_CREDENTIALS_FULL_URI`
endpoint `169.254.170.23` unreachable from Fargate without the
agent), health probes timed out, pods stuck `0/1 Ready` forever.
Observed on cortex-prd 2026-04-28 v0.35.0 bootstrap.

#### Fix in `providers/aws/karpenter.tf`

- `create_pod_identity_association = false` (was `true`)
- New `data "aws_iam_policy_document" "karpenter_irsa_trust"` adding
  IRSA federation (`AssumeRoleWithWebIdentity` from the cluster's
  OIDC provider, scoped to `system:serviceaccount:karpenter:karpenter`)
- Passed via `iam_role_source_assume_policy_documents` (additive merge
  with the module's default `pods.eks.amazonaws.com` statement —
  preserves Pod Identity for any future EC2-side use, but removes the
  active association)

The Karpenter helm chart already annotates the SA with
`eks.amazonaws.com/role-arn` (via `platform-root` helm parameters in
`bootstrap/platform-root/templates/karpenter.yaml`), so the AWS SDK
uses `AssumeRoleWithWebIdentity` correctly. Mirrors the legacy
`cortex-eks-prod` pattern that has been running in production with
IRSA for over a year.

> **Note on AWS SDK credential providers:** SDKs do NOT auto-fall-back
> between credential providers. If the Pod Identity webhook injects
> `AWS_CONTAINER_CREDENTIALS_FULL_URI`, the SDK locks to that path and
> ignores IRSA env vars (`AWS_WEB_IDENTITY_TOKEN_FILE`). We therefore
> DELETE the Pod Identity association entirely (not coexist with it).

### Added — Fargate pod stdout/stderr → CloudWatch Logs (default-on)

EKS Fargate has a Fluent Bit agent embedded in the runtime, but it
only ships logs when the `aws-observability` namespace + `aws-logging`
ConfigMap are present. Without these, Fargate pods (CoreDNS, Karpenter
controller, ebs-csi-controller) silently drop stdout/stderr and emit
`LoggingDisabled` warning events.

Mirrors the legacy `cortex-eks-prod` pattern (`security.tf:43-105`)
that has been running in production for over a year — was a known gap
in v0.35.0 (mapped in the legacy comparison report).

#### New file

`providers/aws/fargate-logging.tf` — provisions, when
`var.fargate_logging_enabled = true` (default) AND the cluster has
at least one Fargate profile:

- `aws_cloudwatch_log_group.fargate` — `/aws/eks/<cluster>/fargate`
  with retention from `var.fargate_log_retention_days`
  (falls back to `var.cluster_log_retention_days`) and KMS encryption
  from `var.fargate_log_kms_key_arn` (falls back to `aws_kms_key.s3_data`).
- `kubernetes_namespace_v1.aws_observability` with the required label
  `aws-observability=enabled`.
- `kubernetes_config_map_v1.aws_logging` with the Fluent Bit
  `[OUTPUT]` config (cloudwatch_logs plugin, log group name,
  log stream prefix). Operators append additional filters via
  `var.fargate_log_filters` (raw Fluent Bit config snippet).
- `aws_iam_role_policy.fargate_logging` — one per Fargate profile
  pod execution role (CloudWatch Logs write).

#### New variables

  fargate_logging_enabled       bool   default true
  fargate_log_retention_days    number default null  (falls back to cluster_log_retention_days)
  fargate_log_kms_key_arn       string default ""    (falls back to aws_kms_key.s3_data)
  fargate_log_filters           string default ""    (extra Fluent Bit config)

#### New output

  fargate_log_group_name        string  CloudWatch log group name (empty when disabled)

### Migration from v0.35.0

Cluster operators upgrading from v0.35.0 should:

1. `terraform apply` — additive (creates 4 resources: log group +
   namespace + ConfigMap + IAM policies; updates Karpenter trust
   policy + drops Pod Identity association).
2. Restart Karpenter pods so the SDK reads the new (IRSA-only) creds:
   `kubectl rollout restart deployment/karpenter -n karpenter`
3. Restart other Fargate pods to pick up the Fluent Bit config:
   `kubectl rollout restart deployment/coredns -n kube-system`
   `kubectl rollout restart deployment/ebs-csi-controller -n kube-system`
4. Verify logs landing in `/aws/eks/<cluster>/fargate` log streams.

## [0.35.0] - 2026-04-28

### Added — Provenance tags on every AWS resource (`source` / `version`)

Every AWS resource provisioned by this module now carries 4 provenance
tags via `provider "aws" { default_tags }`. Mirrors the
`cortex-postgres-aws-*` pattern so AWS Cost Explorer, Resource Groups,
Tag Editor, and CloudTrail all show which repo + commit produced each
resource — no manual labeling.

```
platform_source  = https://github.com/Estabilis/estabilis-platform
platform_version = <upstream VERSION file at the cloned ref>
source           = <client repo URL>           (passed via var.repo_url)
version          = <client semver>             (passed via var.client_version)
```

The first pair is intrinsic to this module (constant URL + the same
VERSION file already used to populate `platform_revision_effective`).
The second pair is opt-in from the client side — empty values are
filtered out.

#### Module surface

  variables.tf — 2 new vars (both default `""`):
    `repo_url`        client GitHub URL
    `client_version`  client deployment semver

  main.tf — `caf_tags` extended with the 4 keys above.

#### Client adoption (1-time per client repo, reusable forever)

Add to the client's `providers/aws/main.tf`:

```hcl
locals {
  changelog_path  = "${path.module}/../../CHANGELOG.md"
  current_version = regex("## \\[([0-9]+\\.[0-9]+\\.[0-9]+)\\]", file(local.changelog_path))[0]
}

module "estabilis_platform" {
  source = "..."
  ...
  repo_url       = var.repo_url
  client_version = local.current_version
}
```

Add `var.repo_url` to the client's `variables.tf` (default to the client
repo URL). Every `chore(release)` commit on the client bumps the
`version` tag automatically — no manual sync.

The `estabilis-platform-downstream/templates/aws/` shell ships with
this wiring pre-installed.

### Added — Container Network Observability (Amazon CloudWatch NFM) on AWS

New opt-in feature that wires Amazon CloudWatch Network Flow Monitor
(NFM) into the EKS cluster, providing the "Container Network
Observability" experience available in the EKS console
(`Cluster → Observability → Network`). Disabled by default — NFM is a
paid CloudWatch service.

Reference:
[EKS docs](https://docs.aws.amazon.com/eks/latest/userguide/network-observability.html).

#### New file

`providers/aws/network-observability.tf` — provisions, when
`var.network_observability_enabled = true`:

  - `aws_iam_role.network_flow_monitor_agent` + Pod Identity association
    bound to the AWS-managed
    `CloudWatchNetworkFlowMonitorAgentPublishPolicy` (Pod Identity is the
    AWS-recommended path for the NFM agent — IRSA still works but is no
    longer the default).
  - `aws_networkflowmonitor_scope` — account+region singleton when
    `network_observability_scope_mode = "create"` (default), or skipped
    with the existing ARN passed in via
    `network_observability_existing_scope_arn` when `mode = "existing"`.
    Operators with multiple clusters in the same account+region SHOULD
    set `mode = "existing"` on the second/Nth cluster to avoid paying
    for duplicate Scopes.
  - `aws_networkflowmonitor_monitor` — per-cluster, with
    `local_resource.type = AWS::EKS::Cluster` and a defaultable
    `remote_resource` list (same-region by default; override via
    `var.network_observability_remote_resources`).
  - `aws_eks_addon.network_flow_monitor_agent` — the
    `aws-network-flow-monitoring-agent` addon (≥ v1.1.0) configured via
    `configuration_values` merged from `var.network_observability_addon_config`
    so operators only override the `OPEN_METRICS*` keys they care about.

#### New variables

  network_observability_enabled                  bool   default false
  network_observability_scope_mode               string default "create"   ("create" | "existing")
  network_observability_existing_scope_arn       string default ""
  network_observability_monitor_name             string default ""         (defaults to `<cluster>-monitor`)
  network_observability_remote_resources         list   default []
  network_observability_addon_version            string default null
  network_observability_addon_config             map    default {}
  network_observability_agent_namespace          string default "amazon-network-flow-monitor"
  network_observability_agent_service_account    string default "aws-network-flow-monitor-agent-service-account"

#### New outputs

  network_observability_enabled         bool
  network_observability_scope_arn       string  ARN — share with sibling clusters in the same account+region
  network_observability_monitor_arn     string
  network_observability_agent_role_arn  string

### Fixed — `effective_addons` substitution → merge

Pre-existing bug in `eks.tf`: `effective_addons` switched fully to
`var.cluster_addons` whenever the user supplied any keys, **silently
dropping the 5 platform defaults** (coredns, kube-proxy, vpc-cni,
eks-pod-identity-agent, aws-ebs-csi-driver). Operators trying to enable
e.g. `amazon-cloudwatch-observability` had to re-declare every default
or break the cluster. Now uses `merge(local.default_addons,
var.cluster_addons)` so per-key overrides work as expected.

### Changed — Provider + module version bumps (BREAKING)

All AWS-side providers and root-level modules bumped to current latest.
Cluster operators upgrading from earlier platform tags MUST run
`terraform init -upgrade` and acknowledge the breaking changes below.
The cortex AWS HML cluster was destroyed and re-applied on this version
to validate the greenfield path end-to-end.

| Dependency                                         | From       | To          |
| -------------------------------------------------- | ---------- | ----------- |
| `hashicorp/aws`                                    | `~> 5.80`  | `~> 6.42`   |
| `terraform-aws-modules/eks/aws`                    | `~> 20.37` | `~> 21.19`  |
| `terraform-aws-modules/iam/aws/.../eks` submodule  | `~> 5.60`  | `~> 6.5` (submodule renamed — see below) |
| `hashicorp/kubernetes`                             | `~> 2.37`  | `~> 3.1`    |
| `hashicorp/helm`                                   | `~> 2.17`  | `~> 3.1`    |
| `cloudflare/cloudflare`                            | `~> 4.0`   | `~> 5.19`   |
| `hashicorp/tls`, `time`, `random`, `http`          | minors     | latest      |

Code-side adjustments applied in this release:

  - **EKS module v21** stripped `cluster_` prefixes from cluster-level
    inputs. Renamed in `eks.tf`: `cluster_name` → `name`,
    `cluster_additional_security_group_ids` → `additional_security_group_ids`,
    `cluster_endpoint_*` → `endpoint_*`, `cluster_enabled_log_types`
    → `enabled_log_types`, `cluster_encryption_config`
    → `encryption_config`, `cluster_addons` → `addons`. Outputs are
    unchanged (`module.eks.cluster_name`, `cluster_endpoint`, etc.
    still resolve as before).
  - **Karpenter sub-module v21** removed `enable_irsa` and
    `irsa_oidc_provider_arn` — Pod Identity is now the only authentication
    path. The chart values rendered by ArgoCD MUST NOT annotate the
    Karpenter ServiceAccount with `eks.amazonaws.com/role-arn`.
  - **IAM module v6** renamed the submodule
    `iam-role-for-service-accounts-eks` → `iam-role-for-service-accounts`.
    The 8 module calls (`external_secrets_irsa`, `external_dns_irsa`,
    `cert_manager_irsa`, `velero_irsa`, `vault_irsa`, `alb_controller_irsa`,
    `cluster_autoscaler_irsa`, `ebs_csi_irsa`) updated. Inputs renamed:
    `role_name` → `name`. Outputs renamed: `iam_role_arn` → `arn`,
    `iam_role_name` → `name`. The `karpenter` sub-module of the EKS
    module is unaffected — it kept the old `iam_role_arn` /
    `iam_role_name` / `node_iam_role_*` names.
  - **Helm provider v3** moved provider configuration from
    `kubernetes { ... }` block syntax to `kubernetes = { ... }` object
    syntax (terraform-plugin-framework). `main.tf` updated.
  - **Cloudflare provider v5** is a complete rewrite (schema v500). The
    `cloudflare_record` resource was renamed to `cloudflare_dns_record`
    and `name` is now a FQDN rather than a zone-relative label. The
    computed `hostname` attribute was removed (`r.name` is the FQDN).
    `acm.tf` updated. **State migration:** v4 → v5 of an in-place
    cluster requires `tf-migrate` from Cloudflare or
    `terraform state mv` per resource — the safe upgrade path is a
    fresh apply, which is what the cortex AWS HML cluster did for this
    release.
  - **AWS provider v6**: `aws_eks_addon.resolve_conflicts` was removed in
    favour of `resolve_conflicts_on_create` and `resolve_conflicts_on_update`.
    The EKS module v21 owns these for managed addons; the new
    `network-observability.tf` sets both explicitly.

## [0.34.0] - 2026-04-28

### Added — Vault root-token Secrets Manager shell + github-auth variables

Every cluster running with `vault_enabled = true` needs (a) a named AWS
Secrets Manager secret to hold the root token that `vault operator init`
produces post-deploy, and (b) three string inputs for the github auth
wiring (`vault auth enable github` + `vault write auth/github/config`)
the operator runs once after the chart is up. Until now both pieces
were duplicated in every downstream client (e.g.
`cortex-platform-aws-us-east-1-prd/providers/aws/vault-bootstrap.tf`).
Pulled upstream so all clients consume the contract through
`module.estabilis_platform.*` outputs.

#### Resource

`aws_secretsmanager_secret.vault_root_token` (count gated on
`var.vault_enabled`):

  - Name `${secrets_path_prefix}/platform-vault-root-token` (mirrors
    the 8 existing `platform-*` secret naming).
  - KMS-encrypted with `aws_kms_key.platform_secrets`.
  - `recovery_window_in_days = var.secretsmanager_recovery_days`.
  - Tagged `estabilis.io/{component=vault, purpose=bootstrap,
    lifecycle=out-of-band}`.

NO `aws_secretsmanager_secret_version` is declared — the token value
is populated by the operator via `aws secretsmanager put-secret-value`
post `vault operator init`. Storing the token in tfvars or a TF version
resource would put a real secret in state files / plan output / git.

#### Variables (all default `""`)

  vault_github_org         GitHub org name for the github auth method.
  vault_github_admins      Comma-separated usernames → `admin` policy.
  vault_github_org_admins  Comma-separated usernames → `org-admin` policy.

#### Outputs (5 new)

  vault_root_token_secret_id    secret name (consumed by bootstrap script)
  vault_root_token_secret_arn   secret ARN (for IAM policy authoring)
  vault_github_org              org name (passed through)
  vault_github_admins           admins list (passed through)
  vault_github_org_admins       org-admins list (passed through)

All five emit `""` when `vault_enabled = false`.

#### Migration for existing downstreams

Clients currently carrying their own `vault-bootstrap.tf` (a vestigial
copy of these resources) should:

  1. Bump the module ref to `v0.34.0`.
  2. `terraform import 'module.estabilis_platform.aws_secretsmanager_secret.vault_root_token[0]' estabilis/<deployment_id>/platform-vault-root-token`
     so the upstream-owned resource adopts the existing AWS secret in
     place (no recreate, no token loss).
  3. Delete the local `vault-bootstrap.tf`. References to
     `aws_secretsmanager_secret.vault_root_token` flip to
     `module.estabilis_platform.vault_root_token_secret_{id,arn}`
     outputs.
  4. Add the github-auth values directly to the client `terraform.tfvars`
     under the upstream variable names (`vault_github_org`,
     `vault_github_admins`, `vault_github_org_admins`) — they accept the
     same string shapes the local `vault-bootstrap.tf` already used.

The downstream bootstrap script (e.g. `scripts/vault-bootstrap.sh`)
reads the same outputs, so nothing changes there.

## [0.33.0] - 2026-04-28

### Added — `existing_subnet_role_tags_management` opt-out for shared-VPC deployments (AWS provider)

`vpc_mode = "existing"` deployments unconditionally created
`aws_ec2_tag.existing_private_internal_elb` (`kubernetes.io/role/internal-elb=1`)
and `aws_ec2_tag.existing_public_elb` (`kubernetes.io/role/elb=1`) on the
operator-supplied subnets. ALB Controller requires these for subnet
auto-discovery, but their KEYS are NOT cluster-scoped — the AWS Load
Balancer Controller hardcodes them — so when N Estabilis deployments share
the same VPC each TF state would own the same tag.

The failure mode is asymmetric:

- **`apply`-time**: AWS `CreateTags` is idempotent, so two clusters
  applying the same `(subnet, key, value)` triple does not error in
  practice — both states co-own the tag.
- **`destroy`-time**: the FIRST cluster to destroy issues `DeleteTags`,
  removing the tag from the shared subnets. The surviving cluster's
  ALB Controller then loses subnet auto-discovery until the next
  `terraform apply` re-asserts the tag.

Karpenter discovery tags were already opt-out via the per-cluster
`karpenter_discovery_tag_key`; the cluster-membership tag
(`kubernetes.io/cluster/<name>=shared`) is cluster-scoped by name and never
collides. Only the two role tags above are shared keys.

Added `existing_subnet_role_tags_management` (string, default `"create"`):

- `"create"` (default — preserves current behavior): TF creates and owns
  the tags. Use for the FIRST cluster sharing a VPC, or any standalone
  deployment.
- `"skip"`: TF does NOT manage these tags. Use for the SECOND/Nth cluster
  sharing a VPC where another deployment (or the operator) already owns
  them. Eliminates cross-state ownership and makes `terraform destroy`
  non-destructive to the surviving cluster's ALB subnet discovery.

The variable name follows the codebase convention of prefixing
`existing_`-only variables (`private_subnet_ids`, `public_subnet_ids`,
`vpc_id`) so the `vpc_mode = "existing"` scoping is signalled at the
call site without relying on the description. A precondition guard
(`terraform_data.existing_subnet_role_tags_guard` in `eks.tf`) rejects
the nonsensical combination `vpc_mode = "create" + "skip"` at plan
time instead of silently no-op'ing.

Backward compatible: existing deployments keep the current behavior on
upgrade. No state migration required.

### Migration playbook (multi-cluster shared VPC)

When promoting a second Estabilis deployment into a VPC where another
Estabilis cluster already runs:

1. Bump the second deployment's module ref to `v0.33.0+`.
2. Set `existing_subnet_role_tags_management = "skip"` in the second
   deployment's `terraform.tfvars` BEFORE the first apply.
3. Apply normally. Verify ALB ingress lifecycle on both clusters.

When retrofitting an already-deployed second cluster:

1. Bump module ref to `v0.33.0+`.
2. Set `existing_subnet_role_tags_management = "skip"`.
3. Run `terraform plan` — expect
   `length(var.private_subnet_ids) + length(var.public_subnet_ids)`
   `aws_ec2_tag` resources to be destroyed (one per private subnet for
   `internal-elb`, one per public subnet for `elb`). For the typical
   3-AZ deployment with 3 private + 3 public subnets that is 6
   resources; counts vary with the actual subnet topology.
4. Run `terraform apply` to release the state resources. The AWS tags
   are NOT removed: the FIRST cluster's TF state still owns them at
   the AWS API, so the surviving cluster's ALB Controller continues
   subnet auto-discovery without interruption. This step only mutates
   the second cluster's state file. Verify post-apply that ingress
   reconciliation on both clusters remains healthy.

## [0.32.1] - 2026-04-27

### Fixed — `validation` null short-circuit on storage-class IOPS/throughput

The `default_storage_class_throughput` and `default_storage_class_iops`
variables shipped in v0.32.0 used the canonical-looking guard:

  ```
  condition = var.foo == null || (var.foo >= 125 && var.foo <= 1000)
  ```

Terraform's `||` operator does **not** short-circuit inside
`validation { condition }` blocks, so when the variable was left
null (the default), the right-hand side still evaluated `null >= 125`
and produced `Error during operation: argument must not be null` at
plan time. The first downstream consumer (HML cluster) hit this on
the very first `terraform plan` post-bump.

Replaced the `||` form with the ternary `var.foo == null ? true :
(...)`, which **does** short-circuit and is the documented workaround
for nullable validations. No behavior change when the variable is set
explicitly.

This is the same class of pitfall as `coalesce(x, "")` in validation
contexts — keeping the fix small (just the two condition lines) so
the v0.32.0 changelog entry below remains the canonical reference for
the storage-class feature itself.

## [0.32.0] - 2026-04-27

### Added — Default StorageClass `gp3` (AWS provider)

EKS 1.30+ no longer ships the in-tree gp2 StorageClass, so a fresh
Estabilis AWS cluster came up with no default class — every PVC that
omitted `storageClassName` (loki, mimir, vault, cnpg, tempo,
pyroscope, ...) stayed Pending. Until now the gap was being closed
manually after each bootstrap (or by the legacy
`iac-infrastructure-aws/eks/storage.tf` for the legacy cortex
cluster).

`providers/aws/storage.tf` now declares a `gp3` StorageClass via the
existing `hashicorp/kubernetes` provider:

  - provisioner `ebs.csi.aws.com` (consumes the EBS CSI addon already
    installed by the EKS module)
  - `volumeBindingMode: WaitForFirstConsumer` (AZ-aware scheduling)
  - `allowVolumeExpansion: true` (gp3 supports online resize; the
    legacy class did not have this enabled)
  - encrypted at rest by default (matches the EC2NodeClass root-disk
    policy; legacy class did not encrypt)
  - `is-default-class` annotation togglable

New variables (all sane defaults; no tfvars change needed for the
common case):

  create_default_storage_class       bool   default true
  default_storage_class_is_default   bool   default true
  default_storage_class_encrypted    bool   default true
  default_storage_class_throughput   number default null  (AWS baseline 125 MiB/s)
  default_storage_class_iops         number default null  (AWS baseline 3000 IOPS)

New output: `default_storage_class_name` — downstream charts can wire
`storageClass` parameters without hardcoding.

#### Upgrade note for existing clusters

Clusters that already carry a hand-applied `gp3` StorageClass
(cortex-platform-aws-us-east-1-prd, anything bootstrapped before this
release) need a one-time import after pulling the module:

```
cd providers/aws
terraform init -upgrade
terraform import 'module.estabilis_platform.kubernetes_storage_class_v1.gp3[0]' gp3
terraform plan
terraform apply
```

The plan will likely show drift on `allowVolumeExpansion` and
`parameters.encrypted` (the hand-applied class typically has neither
set). Both changes are non-destructive — they only affect new PVCs
created after the apply, never existing volumes.

## [0.31.13] - 2026-04-27

### Fixed — Azure-specific spot toleration emitted on AWS clusters

The `platform-root.schedulingTolerations` helper used to emit
`kubernetes.azure.com/scalesetpriority=spot:NoSchedule` unconditionally
in every Application that called it. On AWS that taint never exists,
so the toleration was inert noise polluting Pod specs (cosmetic; no
functional harm).

The helper now requires `.provider` in the dict and only emits the
Azure toleration when the value is `"azure"`. All 16 callers in
`bootstrap/platform-root/templates/*.yaml` updated to pass
`"provider" .Values.global.provider`.

When `.provider` is omitted or any value other than `"azure"`, no
toleration is emitted (safe default — pods schedule normally).

## [0.31.12] - 2026-04-27

### Changed — vpc-cni back to aws-node defaults (no env tuning)

Reverts the prior two attempts at pre-allocation tuning, both of which
left Karpenter-spawned nodes susceptible to `FailedCreatePodSandBox`
until their `aws-node` pod was manually restarted:

  v0.29.1  WARM_PREFIX_TARGET=2 + MINIMUM_IP_TARGET=10  (non-canonical)
  v0.31.9  MINIMUM_IP_TARGET=10 + WARM_IP_TARGET=2     (canonical pair, race still observed)

New config keeps only `ENABLE_PREFIX_DELEGATION=true` (so each allocation
is a /28 prefix instead of a single secondary IP) and falls back to the
aws-node default behavior (`WARM_ENI_TARGET=1`, `WARM_PREFIX_TARGET=1`,
lazy allocation). Operator preference based on observation that the
untuned default produced the alarm less often.

## [0.31.11] - 2026-04-27

### Added — `client-argocd-appsets` Application

New Application template in `bootstrap/platform-root/templates/`
that syncs `platforms/{deploymentId}/argocd/` from the client gitops
repo into the `argocd` namespace. Closes the gap where client-authored
ApplicationSets (the matrix-generator pattern that creates one
Application per `apps/*` subdirectory) were applied only via manual
`kubectl apply` — they now live in gitops, reconciled automatically.

Sync-wave 5 (after platform-level Applications, before client apps
themselves).

Only active when `clientGitopsRepoUrl` AND `deploymentId` are set —
same gate as `client-kyverno-exceptions`.


## [0.31.10] - 2026-04-27

### Added — `bridge.tier` + `bridge.secret-path-template` annotations on `hub-cluster` Secret

Two new annotations on the ArgoCD `hub-cluster` cluster Secret consumed
by client ApplicationSets via the `clusters` generator. Apps using the
Cortex `common-app` chart (>= v0.2.0) now derive their ExternalSecret
backend path purely from cluster annotations — no per-app values.yaml
hardcoding, no per-cluster overrides.

- **`estabilis.io/bridge.tier`** — derived from `var.environment`.
  Maps `prd` / `prod` → `"production"` (matches the Vault path
  convention `secret/org/production/*`); other environments
  (`hml`, `stg`, `dev`, `uat`) pass through verbatim.

- **`estabilis.io/bridge.secret-path-template`** — Vault path schema
  `"secret/data/org/{tier}/{app}"` when `vault_enabled = true`, empty
  string otherwise. The chart fails loud (`required`) on empty so apps
  do NOT silently render an invalid path.

The `{tier}` / `{app}` substitution variables are resolved by the chart
template at render time (`{tier}` ← cluster annotation; `{app}` ←
`Release.Name`).

Future provider migrations (Vault → Azure Key Vault → AWS Secrets
Manager) require changing **only** the path template string in the
upstream — zero changes to client repos or chart consumers. See
`locals.tf:bridge_secret_path_template` for the provider mapping
table.

### Migration

Client ApplicationSets must inject two new helm parameters when
rendering common-app v0.2.0+:

```yaml
- name: externalSecrets.tier
  value: '{{ index .metadata.annotations "estabilis.io/bridge.tier" }}'
- name: externalSecrets.pathTemplate
  value: '{{ index .metadata.annotations "estabilis.io/bridge.secret-path-template" }}'
```

(The other 7 `bridge.*` annotations remain unchanged. Existing
ApplicationSets that don't enable ExternalSecrets are unaffected.)

## [0.31.9] - 2026-04-27

### Fixed — VPC CNI canonical IP target pair (replaces v0.29.1 attempt)

The v0.29.1 fix introduced `WARM_PREFIX_TARGET=2` + `MINIMUM_IP_TARGET=10`
to close the bootstrap race where pods scheduled on a new node hit
`FailedCreatePodSandBox` for ~30s before aws-node finished allocating
the first `/28` prefix. The intent was correct, but the variable pair
chosen was non-canonical — per the [AWS VPC CNI
docs](https://github.com/aws/amazon-vpc-cni-k8s/blob/master/docs/prefix-and-ip-target.md):

> "WARM_IP_TARGET and MINIMUM_IP_TARGET if set will override
> WARM_PREFIX_TARGET."

The override requires **both** of the pair to be set. With only
`MINIMUM_IP_TARGET=10` (no `WARM_IP_TARGET`), behavior is undefined.
On cortex prd 2026-04-27 this surfaced as 3 of 5 newly-provisioned
`c7a.medium` nodes registering Ready with **zero** `/28` prefixes
allocated, blocking pod sandbox creation until manual restart of
the aws-node DaemonSet.

#### Fix

Replace `WARM_PREFIX_TARGET` with the canonical `WARM_IP_TARGET`:

```diff
 env = {
   ENABLE_PREFIX_DELEGATION = "true"
-  WARM_PREFIX_TARGET       = "2"
   MINIMUM_IP_TARGET        = "10"
+  WARM_IP_TARGET           = "2"
 }
```

`MINIMUM_IP_TARGET=10` pre-allocates the floor before the node
reports Ready (covers cold-start). `WARM_IP_TARGET=2` keeps two free
IPs ahead of demand for micro-bursts. Together they override
`WARM_PREFIX_TARGET` to its default (1) and produce deterministic
behavior across multi-node Karpenter bursts.

#### Files changed

- `providers/aws/eks.tf` — env vars replaced; comment updated to
  cite the AWS docs override rule.

#### Operator notes

- vpc-cni addon updates in-place on next `terraform apply`. No node
  replacement, no pod restarts. aws-node DaemonSet rolls automatically
  to pick up new env vars.
- Existing nodes with the broken config can be cured by deleting
  their aws-node pod (DS recreates with new env). Or wait for
  Karpenter/MNG churn to roll them naturally.
- For clusters that already saw the v0.29.1 vars in production:
  verify post-apply that nodes have at least 1 prefix:
  ```
  aws ec2 describe-network-interfaces \
    --filters "Name=attachment.instance-id,Values=<node-id>" \
    --query 'NetworkInterfaces[].Ipv4Prefixes[].Ipv4Prefix'
  ```

## [0.31.8] - 2026-04-26

### Fixed — ACM cert SAN keeps `*.{local.cluster_name}.{domain}` covered

v0.31.7 changed ACM `domain_name` from `*.{local.cluster_name}.{domain}`
(`eks-{base}`) to `*.{name_prefix}-{deployment_id}.{domain}` to align
with the bridge annotation. Platform-managed Ingresses (argocd,
grafana, vault) still use the old `local.cluster_name` pattern in
their host field, so they lost cert coverage and the old cert
couldn't be deleted (in-use by the platform ALB).

Fix: include `*.{local.cluster_name}.{domain}` automatically as a SAN
when it differs from the primary domain. Cert now covers BOTH
patterns; new apps and legacy platform Ingresses keep working.

#### Files changed

- `providers/aws/acm.tf` — `locals.acm_legacy_san` derives the legacy
  wildcard automatically; concatenated into
  `subject_alternative_names` along with the existing
  `var.acm_extra_domain_names` user overrides.

#### Operator notes

- `aws_acm_certificate.wildcard` recreated again (immutable
  domain_name + SANs trigger replace). create_before_destroy lifecycle
  applies; brief revalidation window via Cloudflare DNS-01 (~30-90s).
- After apply: `aws acm describe-certificate ... --query 'Certificate.SubjectAlternativeNames'`
  should list `*.{name_prefix}-{deployment_id}.{domain}`,
  `*.{local.cluster_name}.{domain}`, plus any extras.
- The orphaned v0.31.7 cert (no longer in use after this re-issue)
  gets cleaned up on apply.

## [0.31.7] - 2026-04-26

### Fixed — ACM wildcard cert FQDN aligned with bridge.cluster-name annotation

ACM `domain_name` used `local.cluster_name` (= `eks-${base}`).
Bridge annotation `cluster-name` (v0.31.5+) uses
`${name_prefix}-${deployment_id}`. App FQDNs composed from the bridge
annotation never matched the cert — ALB auto-discovery couldn't pick
it up, HTTPS broke.

Fix: cert covers `*.${name_prefix}-${deployment_id}.${domain}` —
same identifier as the bridge annotation. Single wildcard covers all
apps in the cluster.

#### Files changed

- `providers/aws/acm.tf` — `domain_name` realigned + Cloudflare
  validation comment updated.

#### Operator notes

- `aws_acm_certificate.wildcard` is **destroyed and recreated**
  (immutable `domain_name`). `lifecycle.create_before_destroy = true`
  issues the new cert before deleting the old; DNS-01 validation via
  Cloudflare takes ~30-90s.
- ALB Controller auto-rediscovers the new cert; existing Ingresses
  pick it up on next reconciliation (~30s).

## [0.31.6] - 2026-04-26 — `cluster-name` annotation includes `name_prefix`

(Empty release commit — see [#122](https://github.com/Estabilis/estabilis-platform/pull/122).)

## [0.31.5] - 2026-04-26

### Added — cluster Secret annotations for ADR 0023 Etapa B (dynamic cluster metadata)

Three new annotations on the `hub-cluster` ArgoCD Secret in `argocd`
ns, written by `providers/aws/platform-outputs.tf`:

- `estabilis.io/bridge.cluster-name` = `var.deployment_id`
- `estabilis.io/bridge.domain` = `var.domain`
- `estabilis.io/bridge.ingress-group-name` = `${var.name_prefix}-${var.environment}-shared-apps`

Eliminates hardcoded cluster/domain/ingress-group values in client
gitops ApplicationSets. ApplicationSets matrix-generated against
`clusters` selector now read these via `{{ index .metadata.annotations
"estabilis.io/bridge.<key>" }}` Go-template syntax — same chart, same
gitops repo, different values per cluster automatically.

#### Why ingress-group-name

ALB Controller's `alb.ingress.kubernetes.io/group.name` annotation
merges multiple Ingresses (with the same group) onto a single ALB
with host-based routing. Default behavior (no group) creates one ALB
per Ingress — at $16-22/mo per ALB, a 30-app cluster costs $500+/mo
just on ALBs. Setting a cluster-default group at the AppSet level
(read from the annotation) collapses that to a single ALB while
preserving per-app override capability for compliance/isolation
needs.

#### Files changed

- `providers/aws/platform-outputs.tf` — 3 new annotations on
  `kubernetes_secret.hub_cluster`.

#### Operator notes

- Plan diff: 1 in-place update on `kubernetes_secret.hub_cluster`
  (annotation map extended).
- Client gitops ApplicationSets must be refactored to matrix
  (clusters × git) generator + read annotations to consume the new
  values. Hardcoded values in existing AppSets continue to work but
  miss the new dynamic capabilities.

## [0.31.4] - 2026-04-26

### Reverted — drop ArgoCD ↔ ECR OCI auth bridge (v0.31.2 + v0.31.3)

Cortex (and the legacy `iac-infrastructure-aws/eks/argocd.tf`) **never**
consumed helm charts via OCI from ECR. ArgoCD reads charts directly
from git (e.g. `Cortex-Innovation/helm-charts`, path-based) using the
existing GitHub App org credential (`secret-type=repo-creds`). ECR is
used for app **images** (pushed by CI), not for chart distribution.

The ArgoCD↔ECR OCI auth bridge added in v0.31.2 (extended ESO IRSA
with ECR permissions + ECRAuthorizationToken + ExternalSecret) and
attempted-fix v0.31.3 (auth removal) was solving a problem that didn't
exist. Removed in v0.31.4 to clean up dead infrastructure on consumer
clusters.

#### Files changed

- `providers/aws/argocd-ecr-creds.tf` — deleted.

#### Operator notes

- Cortex consumers on v0.31.2 / v0.31.3 see 4 resource removals on
  next apply: `aws_iam_policy.external_secrets_ecr`,
  `aws_iam_role_policy_attachment.external_secrets_ecr`, and 2
  `kubernetes_manifest` resources in `argocd` ns. None were
  functionally referenced — clean removal.
- If a future client genuinely needs OCI helm charts (e.g. private
  charts NOT in git), reintroduce the pattern as a separate, gated
  feature (`var.argocd_ecr_oci_enabled`) with end-to-end validation
  before merge. Issue [#202](https://github.com/Estabilis/estabilis-platform-tools/issues/202)
  is closed as "no real consumer demand for OCI charts".

## [0.31.2] - 2026-04-26

### Fixed — ArgoCD can now pull OCI helm charts from platform-provisioned ECR

v0.31.0 introduced ECR (per-repo + pull-through cache). `argocd-repo-server`
had no AWS credentials, so Applications referencing
`oci://<account>.dkr.ecr.<region>.amazonaws.com/<prefix>/<chart>` failed
at sync with `basic credential not found`. The cortex pilot blocked on
this; see [estabilis-platform-tools#202](https://github.com/Estabilis/estabilis-platform-tools/issues/202)
for the full postmortem.

Fix wires `external-secrets-operator` (already deployed + IRSA-bound) to
mint ECR auth tokens via the native `ECRAuthorizationToken` generator,
write them to an ArgoCD repo Secret, and refresh every 10h (under the
12h ECR token TTL).

#### New file `providers/aws/argocd-ecr-creds.tf`

Three resources, all conditional on `var.ecr_enabled`:

1. `aws_iam_policy.external_secrets_ecr` — adds `ecr:GetAuthorizationToken`
   (mint tokens) + ECR pull permissions (so the minted token can fetch
   artifacts; ECR token authority is bound to the requesting principal).
2. `aws_iam_role_policy_attachment.external_secrets_ecr` — attaches the
   policy to the existing `external_secrets_irsa` role.
3. `kubernetes_manifest.ecr_auth_token` — `ECRAuthorizationToken`
   generator in `argocd` ns referencing ESO's SA.
4. `kubernetes_manifest.argocd_ecr_repo` — `ExternalSecret` in `argocd`
   ns targeting `argocd-ecr-repo` Secret with label
   `argocd.argoproj.io/secret-type=repository`, refreshInterval=10h,
   url = registry root (so any chart pulled from this registry matches
   by prefix).

#### Operator notes

- Apply order: ESO CRDs must be installed before the `kubernetes_manifest`
  resources apply. ESO is deployed by ArgoCD (platform-root chart) on
  first reconcile after the cluster bootstraps. On a fresh cluster, the
  first `terraform apply` may report a CRD-not-found error on the
  `kubernetes_manifest.ecr_auth_token` resource; re-run after ArgoCD
  syncs the external-secrets Application. Subsequent applies are
  idempotent.
- Cortex bump path: `main.tf` ref `v0.31.1` → `v0.31.2`, then
  `terraform plan` shows `+1` IAM policy + `+1` policy attachment +
  `+2` Kubernetes manifests. After apply, the `argocd-ecr-repo` Secret
  appears in `argocd` ns within ~30s of ESO reconciling.
- Future: migrate the K8s manifests to a chart in
  `estabilis-platform-gitops/components/argocd-ecr-creds/` rendered by
  platform-root, eliminating the cross-domain TF→CRD ordering. Tracked
  in #202.

## [0.31.1] - 2026-04-26

### Fixed — ECR pull-through cache default no longer includes auth-required upstreams

The v0.31.0 default upstream set `{ ghcr, quay, k8s, public-ecr }`
broke at apply time with `UnsupportedUpstreamRegistryException` —
AWS requires Secrets Manager credentials for `ghcr.io`, `quay.io`,
`gitlab-registry.com`, and Docker Hub. Only `registry.k8s.io` and
`public.ecr.aws` are truly anonymous.

Fix: drop ghcr/quay from `local.ecr_default_pt_cache_upstreams`.
Operators caching auth-required upstreams must set
`ecr_pull_through_cache_upstreams` explicitly and provide credentials
(`ecr_dockerhub_credentials_secret_arn` for Docker Hub today; per-
upstream credential map planned for v0.32.0).

#### Files changed

- `providers/aws/ecr.tf` — `local.ecr_default_pt_cache_upstreams` reduced to `{ k8s, public-ecr }`.
- `providers/aws/variables.tf` — descriptions of `ecr_pull_through_cache_enabled` and `ecr_pull_through_cache_upstreams` rewritten to call out the auth requirement.
- `providers/aws/terraform.tfvars.example` — comments updated to mark which upstreams are anonymous vs authenticated.

#### Operator notes

- v0.31.0 deployments with `ecr_pull_through_cache_upstreams` left empty failed at apply (or partially applied). On bump to v0.31.1, plan shows `+2` PT cache rules + `+2` creation templates total (k8s, public-ecr only); any state from a partial v0.31.0 apply is reconciled.
- v0.31.0 deployments that explicitly limited upstreams to `{ k8s, public-ecr }` see no plan changes.

## [0.31.0] - 2026-04-26

### Changed — ECR ownership model + pull-through cache defaults

Splits ECR responsibility between platform-declarative repos and
CI-owned workload repos, and gives pull-through cache usable defaults.

#### Ownership model

- `var.ecr_repositories` is now scoped to **platform-managed** repos
  only — CLI-published addons (workload-operator image, chart). The
  variable description is updated to call this out.
- **Workload application repos no longer go in TF.** CI pipelines
  create them on first `docker push` via the OIDC IAM role (added in a
  follow-up). Forcing every workload onboarding through `terraform
  apply` was the friction this split removes.
- No variables removed. Existing operators keep working; updated
  descriptions document the boundary.

#### Pull-through cache

- New resource `aws_ecr_repository_creation_template.pull_through_cache`
  applied with `applied_for = ["PULL_THROUGH_CACHE"]` so cache-created
  repos inherit KMS encryption + lifecycle policy. Without it, AWS
  defaults apply (AES256, no lifecycle).
- `var.ecr_pull_through_cache_upstreams` left empty with
  `ecr_pull_through_cache_enabled = true` now activates a default
  anonymous public set: `ghcr`, `quay`, `k8s`, `public-ecr`. Override
  to add `docker-hub` (still requires
  `ecr_dockerhub_credentials_secret_arn` to bypass anonymous rate
  limits).

#### Output

- New output `ecr_pull_through_cache_prefixes` — map of prefix to
  upstream URL. Use it to construct cached image refs like
  `<registry>/k8s/coredns/coredns:v1.11.1`.

#### Files changed

- `providers/aws/ecr.tf` — full rewrite: locals + creation template.
- `providers/aws/variables.tf` — descriptions updated for
  `ecr_repositories`, `ecr_pull_through_cache_enabled`,
  `ecr_pull_through_cache_upstreams`.
- `providers/aws/outputs.tf` — new `ecr_pull_through_cache_prefixes`.
- `providers/aws/platform-outputs.tf` — `global.ecrRegistry` now
  follows `ecr_enabled` only (was guarded by non-empty
  `ecr_repositories`, which excluded PT-cache-only deployments).
- `providers/aws/terraform.tfvars.example` — comments updated.

#### Operator notes

- No state mutations on existing repos. Apply is additive: PT-cache
  operators see 4 new pull-through cache rules + 4 creation templates
  on first apply when leaving the upstreams map empty.
- Operators using `ecr_repositories` for workload apps should remove
  those entries; existing repos remain in AWS but become unmanaged
  (lifecycle/scan settings stay as last applied).

## [0.30.0] - 2026-04-26

### Added — Single source of truth for module version (`VERSION` file)

Eliminates the duplication where operators had to bump both
`providers/<cloud>/main.tf` `ref=...` AND `terraform.tfvars`
`platform_revision = "..."` (or `platform_version`) on every release.
The module now self-derives its version from a `VERSION` file at the
upstream repo root, read via `file("${path.module}/../../VERSION")` at
apply time. Bump only `main.tf ref=...` going forward; the tfvar is
optional override.

#### Components

1. **`VERSION`** (new) — root file; one line, prefix `v`, e.g. `v0.30.0`.
   Updated automatically by the release workflow on every
   `chore(release): vX.Y.Z` commit (see workflow change below).

2. **`providers/aws/main.tf`** — `local.module_version` reads the file;
   `platform_revision_effective` resolution chain becomes:
   ```
   var.platform_revision (override) →
     var.platform_version (legacy alias / override) →
       local.module_version (default — derived from VERSION)
   ```

3. **`providers/azure/main.tf`** — same pattern with
   `local.platform_version_effective` (Azure uses a single `*_version`
   var, no `*_revision` legacy variant).

4. **`providers/aws/variables.tf` + `providers/azure/variables.tf`** —
   `platform_version` default flipped from `"0.1.0-alpha"` (a sentinel
   value clients always overrode) to `""`. Empty default routes to
   VERSION fallback. Description rewritten to flag override semantics.

5. **`.github/workflows/release.yaml`** — new step `Sync VERSION file
   to release commit` runs immediately after the duplicate-tag guard.
   It writes the detected version to `VERSION`, `git commit --amend`s
   the release commit if a diff exists, and force-pushes (safe under
   the existing `concurrency: group: release`). The subsequent tag +
   GitHub Release steps then point at the amended commit.

#### Operator workflow (unchanged from external POV)

```bash
git commit --allow-empty -m "chore(release): v0.30.0"
git push origin main
# → workflow: amends VERSION → tags → creates Release page
```

Operator still does **only** the empty-commit push. The workflow
handles VERSION sync + tag + Release atomically.

#### Backward compatibility

100% preserved. Existing clients that set `platform_version` or
`platform_revision` in tfvars continue working — the override path
wins over VERSION. Removing the tfvar (recommended) routes to VERSION
fallback automatically with no other change required.

#### Migration (per client, gradual)

When upgrading client to `?ref=v0.30.0`:

1. `terraform apply` — VERSION-based derivation is now active for any
   field left blank.
2. **Optional**: Remove `platform_revision = "..."` (and/or
   `platform_version = "..."`) from `providers/<cloud>/terraform.tfvars`.
   Subsequent ref bumps then need only the `main.tf` edit.

The `platform-outputs` ConfigMap continues to receive the same
`platformVersion` + `platformRevision` keys; the value source is now
the VERSION file when not explicitly overridden.

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
