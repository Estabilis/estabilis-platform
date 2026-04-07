# hubble-ui

Visualizes Cilium network flows captured by `hubble-relay` on AKS clusters
running `network_dataplane = cilium-acns`.

## Why this component exists

Microsoft's Advanced Container Networking Services (ACNS) installs the
Hubble backend (`cilium`, `cilium-operator`, `hubble-relay`, certificate
secrets) automatically when ACNS is enabled. The **UI is not installed** —
Microsoft leaves it as an opt-in customer concern. This component fills
that gap with a Helm chart aligned to the platform's GitOps conventions.

## v1 scope

- **ACNS only.** `mode: acns` is the only valid value. BYO-CNI mode is
  deferred until a real BYO-CNI cluster exists for validation.
- **Single replica, ClusterIP only.** No ingress, no public exposure.
  Access is via `kubectl port-forward` (or the
  `estabilis hubble-ui <client>` helper, when implemented).
- **Deployed into `kube-system`.** This is non-negotiable: the UI backend
  must read the `hubble-relay-client-certs` Secret created by the
  Microsoft-managed certgen Job, which lives in `kube-system`.

## Critical: mTLS to the Hubble relay

The Hubble relay enforces **mutual TLS**. The UI backend must present a
client certificate signed by the same CA the relay trusts, otherwise the
connection is rejected with `error reading server preface: remote error:
tls: certificate required`.

The Microsoft-managed `certgen` Job creates two TLS Secrets in `kube-system`:

| Secret | Purpose |
|---|---|
| `hubble-relay-server-certs` | Server cert presented BY the relay (used by clients to verify the server) |
| `hubble-relay-client-certs` | **Client cert presented TO the relay by callers** (this is what the UI backend mounts) |

The Microsoft documentation example for accessing Hubble (`hubble observe
--tls --tls-allow-insecure`) is **incomplete** — it omits the client
certificate, which is why running it against a fresh ACNS cluster fails
with the TLS error above. This component mounts the correct
`hubble-relay-client-certs` Secret and configures the backend with the
server name SNI that matches the relay's wildcard cert SAN
(`*.hubble-relay.cilium.io`).

## Version compatibility matrix

The UI version must be aligned with the Hubble relay version. Microsoft
controls the relay version on ACNS clusters and may bump it during AKS
maintenance windows.

| Cilium / hubble-relay version | Compatible hubble-ui version |
|---|---|
| `v1.18.x` (current ACNS, 2026-04) | `v0.13.x` (pinned: `v0.13.3`) |
| `v1.14.x` | `v0.12.x` |

If `hubble observe` works against the cluster but the UI returns "Failed
to load flows" with `unimplemented` or `internal` errors, the relay was
likely upgraded by Microsoft. Bump `image.frontend.tag` and
`image.backend.tag` in this chart's `values.yaml`, ship a new platform
release, and re-sync the downstream.

A drift check (Phase 3 of estabilis-platform-tools#46) will surface
this automatically as part of `estabilis verify` once implemented.

## Enabling on a client

In the client's downstream repo:

```yaml
# overrides/platform-root/values.yaml
components:
  hubble-ui: true
```

Then re-sync ArgoCD's `platform-root` Application. The `hubble-ui`
Application appears in sync wave 8 (same wave as other observability
components).

## Accessing the UI

```bash
# Port-forward (manual)
kubectl --context <client-context> -n kube-system \
  port-forward svc/hubble-ui 12000:80

# Open in browser
xdg-open http://localhost:12000   # Linux
open http://localhost:12000       # macOS
```

Once the helper is implemented (Phase 4):

```bash
estabilis hubble-ui <client> [--open]
```

## Disabling

Set `components.hubble-ui: false` in the downstream override (or omit it
entirely — `false` is the platform default). The Application is removed
from ArgoCD on the next reconciliation; no namespace cleanup is needed
(resources live in `kube-system` and are pruned individually).
