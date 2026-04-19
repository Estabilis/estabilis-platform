# Changelog

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
