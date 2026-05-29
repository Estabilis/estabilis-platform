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

## Validation

- `kubectl get applicationset estabilis-workload-operator -n argocd` exists.
- The generated Application resolves `hubTokenSync.clientId/tenantId/keyVaultName`
  from the `hub-cluster` Secret annotations (non-empty).
- After sync, the operator pod publishes `hub-registrar-token` to the hub Key
  Vault; a subsequent workload `terraform apply` reads it (no manual step).
