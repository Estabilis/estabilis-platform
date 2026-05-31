# Workload operator delivery (no-CLI path)

How the `estabilis-workload-operator` is delivered to the **hub** cluster and
how it publishes the `hub-registrar-token` — without the `estabilis` CLI in the
critical path.

## Delivery mechanism — GitOps Bridge (ADR 0010)

The operator is an ArgoCD platform addon, delivered through the GitOps Bridge.
This is already wired across the repos; there is nothing to do at apply time
beyond having the chart in the ACR:

1. **Terraform (this repo)** emits the hub ArgoCD Cluster Secret
   (`hub-cluster`, `providers/azure/platform-outputs.tf`) with the
   `estabilis.io/bridge.*` annotations (tenant-id, hub-key-vault-name,
   workload-operator-client-id, …), and provisions the operator's UAMI +
   federated credential (subject
   `system:serviceaccount:estabilis-system:estabilis-workload-operator`) +
   `Key Vault Secrets Officer` on the hub Key Vault
   (`providers/azure/workload-identity.tf`, gated on `shared_hub_kv_enabled`).
2. **platform-root** renders the addon as an ApplicationSet when its entry sets
   `bridge: true`, mapping the bridge annotations onto
   `hubTokenSync.{clientId,tenantId,keyVaultName}`
   (`bootstrap/platform-root/templates/platform-addons.yaml`).
3. **Client override** (`overrides/platform-root/values.yaml`, from the
   downstream template) declares only the business toggle:

   ```yaml
   platformAddons:
     estabilis-workload-operator:
       chart: estabilis-workload-operator
       targetRevision: "0.8.0"        # = operator chart version (git tag)
       namespace: estabilis-system
       bridge: true                   # ADR 0010 — IDs come from the Cluster Secret
       values:
         image: estabilis-workload-operator
         hubTokenSync:
           enabled: true
   ```

   The platform default is `platformAddons: {}` — clients opt in via the
   override above (this is the documented mechanism; the platform does not
   force-deliver the operator).
4. **Operator runtime** publishes the registrar ServiceAccount token to the hub
   Key Vault as `hub-registrar-token` using Workload Identity (its
   `hubTokenSync` handler). No CLI, no manual `kubectl`, no `estabilis upstart`.

## Operational prerequisite — publish image + chart to the client ACR

The bridge consumes the chart from the client ACR (`repoURL: <acr>/charts`).
**The `estabilis` CLI is NOT used here**, so the image and chart must be
published to the ACR as an explicit operational step (or a CI job) before the
ApplicationSet can sync. `targetRevision` must equal the operator chart version
(git tag), e.g. `0.8.0`.

```bash
# Authenticate to the client ACR
az acr login --name <acr-name>
ACR=<acr-name>.azurecr.io
VERSION=0.8.0   # = estabilis-workload-operator Chart.yaml version / git tag

# 1. Image  → <acr>/estabilis/estabilis-workload-operator:<version>
#    (the chart's values default registry is "<acr>/estabilis")
docker build -t "$ACR/estabilis/estabilis-workload-operator:$VERSION" \
  /path/to/estabilis-workload-operator
docker push "$ACR/estabilis/estabilis-workload-operator:$VERSION"

# 2. Chart  → oci://<acr>/charts/estabilis-workload-operator
helm package /path/to/estabilis-workload-operator/charts/estabilis-workload-operator \
  --version "$VERSION" --app-version "$VERSION"
helm push "estabilis-workload-operator-$VERSION.tgz" "oci://$ACR/charts"

# 3. Verify
az acr repository show-tags --name <acr-name> \
  --repository estabilis/estabilis-workload-operator
az acr repository show-tags --name <acr-name> \
  --repository charts/estabilis-workload-operator
```

> The operator repo's CI also publishes image + chart to GHCR on each tag; the
> client-ACR publish above is the step required for the platform's ArgoCD to
> pull the chart from the **client's** registry. Mirror from GHCR or build into
> the ACR — either is fine, as long as `:<version>` exists in the ACR before
> sync.

## Per-cluster capability gating (convention contract)

Besides the `estabilis.io/bridge.*` annotations above, the operator promotes
**capability** flags to **labels** on each *workload* Cluster Secret so the
`workload-bootstrap` ApplicationSet `clusters`-generators can gate addons
per-cluster (generators select by label, not annotation). As of operator
`0.11.0` this is a **convention, not a mapping**:

```
bridge key  capability.<name>   →   label  estabilis.io/capability.<name>
```

No product names and no bridgeKey→label table live anywhere. The producer
(`estabilis-workload` Terraform) emits `capability.<name>` in the bridge Secret;
the consumer (`estabilis-platform-gitops` selectors) matches
`estabilis.io/capability.<name>`. Both sides just follow the convention.
Governance is centralized in the operator chart's `capabilities` value (a flat
allowlist of known capability names + `unknownPolicy`), validated at startup.

Current capabilities:

| Bridge key (intent) | Cluster Secret label |
|---|---|
| `capability.ingress` | `estabilis.io/capability.ingress` |
| `capability.ingress-internal` | `estabilis.io/capability.ingress-internal` |
| `capability.dns-internal` | `estabilis.io/capability.dns-internal` |

### Breaking change — coordinated cutover across three repos

This replaces the earlier product-named keys/labels (`traefik-enabled`,
`estabilis.io/ingress.traefik`, …). There is **no dual-emit / backward-compat**;
the change must land together in three repos:

1. **`estabilis-workload` (Terraform)** — rename the bridge Secret keys:

   ```hcl
   # bridge Secret `data` — capability gates (ADR 0010)
   "capability.ingress"          = tostring(var.ingress_enabled)            # was traefik-enabled
   "capability.ingress-internal" = tostring(var.ingress_internal_enabled)   # was traefik-internal-enabled
   "capability.dns-internal"     = tostring(var.dns_internal_enabled)       # was external-dns-internal-enabled
   # other bridge values (tenant-id, keyvault-uri, …) unchanged
   ```

   Renaming the variables (`traefik_enabled → ingress_enabled`, etc.) is optional
   but keeps capability naming end-to-end.

2. **`estabilis-workload-operator`** — already done in `0.11.0` (this change).
   The chart's `capabilities.known` allowlist must contain `ingress`,
   `ingress-internal`, `dns-internal`.

3. **`estabilis-platform-gitops` (`workload-bootstrap` ApplicationSets)** — point
   the cluster-generator selectors at the capability labels:

   ```yaml
   generators:
     - clusters:
         selector:
           matchLabels:
             estabilis.io/capability.ingress: "true"          # was estabilis.io/ingress.traefik
   # likewise: estabilis.io/capability.ingress-internal, estabilis.io/capability.dns-internal
   ```

**Cutover order.** ArgoCD syncs each repo independently, so there is no atomic
flip. For a **greenfield** fleet (these gates are days old — v0.9.0 was
2026-05-29 — so likely not yet relied on in production), simply land all three
with capability naming; no transition needed. For an **already-live** fleet,
schedule a short maintenance window: roll the operator `0.11.0`, then the
workload bridge keys, then the gitops selectors — the gated addons re-sync once
the new labels and selectors line up. (If a zero-downtime transition is ever
required, reintroduce a temporary dual emission behind `capabilities`, migrate
selectors, then drop it — but for a days-old feature this is unnecessary.) The
capability naming also lets the ingress/DNS implementation change (nginx, Istio,
a different DNS controller) later without touching any selector name.

## Validation

- `kubectl get applicationset estabilis-workload-operator -n argocd` exists.
- The generated Application resolves `hubTokenSync.clientId/tenantId/keyVaultName`
  from the `hub-cluster` Secret annotations (non-empty).
- After sync, the operator pod publishes `hub-registrar-token` to the hub Key
  Vault; a subsequent workload `terraform apply` reads it (no manual step).
