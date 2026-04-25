# cloudflare-credentials

Cloud-agnostic Terraform module that creates a Kubernetes Secret carrying
a Cloudflare API token + the zone ID it scopes to.

Consumed by:
- **external-dns** — `CF_API_TOKEN` env var (today via helm.parameter
  passthrough; can migrate to `secretKeyRef` against this Secret).
- **cert-manager** DNS-01 ClusterIssuer — `apiTokenSecretRef.name`.

The Cloudflare zone itself is **not** managed by this module. It must
already exist (created at the registrar / Cloudflare Dashboard
manually). The token's permissions must include `Zone:DNS:Edit` and
`Zone:Zone:Read` on the target zone.

## Why this module

- **Single source of truth** for Cloudflare credentials in the cluster.
  Eliminates the duplication between `providers/aws/` and
  `providers/azure/` of identical `cloudflare_zone_id` /
  `cloudflare_api_token` variables and their pass-through logic.
- **Cloud-agnostic**: same module called from every provider's caller
  TF (`providers/aws/cloudflare.tf`, `providers/azure/cloudflare.tf`).
  Each provider additionally mirrors the token in its own cloud secret
  store (AWS Secrets Manager / Azure Key Vault) for rotation/audit/
  recovery — same pattern as `modules/github-app-credentials/`.
- **Future-proof**: when Estabilis eventually wants to manage zone
  resources, firewall rules, or rotate tokens via the `cloudflare`
  Terraform provider, the natural place is to extend this module.

## Inputs

| Variable | Required | Description |
|---|---|---|
| `cloudflare_zone_id` | yes | 32-char hex Zone ID from the Cloudflare Dashboard |
| `cloudflare_api_token` | yes | API token (NOT API key) with Zone:DNS:Edit + Zone:Zone:Read (sensitive) |
| `domain` | yes | Zone domain name (e.g. `estabilis-cortex.com`) |
| `namespace` | no | Kubernetes namespace (default: `external-dns`) |
| `secret_name` | no | Name of the Secret (default: `cloudflare-credentials`) |

## Outputs

| Output | Description |
|---|---|
| `secret_name` | Name of the created Kubernetes Secret |
| `namespace` | Namespace where the Secret lives |
| `zone_id` | Passthrough of the Zone ID |
| `domain` | Passthrough of the zone domain |

## Secret data layout

| Key | Value |
|---|---|
| `api-token` | Cloudflare API token (no `Bearer ` prefix) |
| `zone-id` | 32-char Cloudflare Zone ID |
| `domain` | Zone domain (e.g. `estabilis-cortex.com`) |

## Token creation (manual, one-time per org)

1. Cloudflare Dashboard → My Profile → API Tokens → Create Token.
2. Use the **Edit zone DNS** template OR Custom token with:
   - Zone:Zone:Read on the target zone
   - Zone:DNS:Edit on the target zone
3. Copy the token (shown once). Pass to Terraform via `secrets.auto.tfvars`
   or environment variable. Never commit.
