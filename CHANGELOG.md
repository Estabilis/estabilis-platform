# Changelog

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
