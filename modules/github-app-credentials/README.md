# github-app-credentials

Cloud-agnostic Terraform module that creates a Kubernetes Secret with the
ArgoCD `repo-creds` credential-template label, carrying GitHub App
installation identifiers and PEM-encoded private key.

Once applied, any ArgoCD Application whose `repoURL` starts with the
provided `github_org_url` uses the GitHub App installation token for
authentication — no user-scoped PATs, no deploy keys per repo.

## Why a GitHub App

- **Not user-scoped**: the credential belongs to the organization, not to
  a specific GitHub user. If the user who created it leaves the org, the
  App (and this credential) continue working.
- **Fine-grained permissions**: read-only access to `Contents` is enough.
- **Automatic token rotation**: ArgoCD internally exchanges the JWT for
  installation access tokens (1-hour TTL) and refreshes on expiry. No
  external rotation infrastructure needed.
- **Scales across repos**: one App installation can cover every repo in
  the org, including new repos added later.

## Inputs

| Variable | Required | Description |
|---|---|---|
| `github_app_id` | yes | App ID (numeric) |
| `github_app_installation_id` | yes | Installation ID (from the org install URL) |
| `github_app_private_key` | yes | PEM-encoded private key (sensitive) |
| `github_org_url` | yes | `https://github.com/<org>` (no trailing path) |
| `namespace` | no (default `argocd`) | Kubernetes namespace for the Secret |
| `secret_name` | no | Override the default `github-app-<slug>` name |

## Outputs

| Output | Description |
|---|---|
| `secret_name` | Name of the created Secret |
| `namespace` | Namespace of the Secret |
| `org_slug` | Derived lowercased slug of the org |

## Usage

```hcl
module "github_app" {
  source = "../../modules/github-app-credentials"

  github_app_id              = var.github_app_id
  github_app_installation_id = var.github_app_installation_id
  github_app_private_key     = var.github_app_private_key
  github_org_url             = "https://github.com/Cortex-Innovation"
}
```

The caller is responsible for mirroring the private key into whichever
cloud secret store is appropriate (AWS Secrets Manager, Azure Key Vault,
GCP Secret Manager, ...) for audit, rotation, and disaster recovery.
That intentionally lives outside this module — the module owns only the
rendering of the Kubernetes-side credential.

## How to create the GitHub App

1. Navigate to `https://github.com/organizations/<org>/settings/apps/new`
2. Set a unique name (e.g. `estabilis-argocd-<client>`)
3. Disable the webhook (uncheck "Active")
4. Repository permissions: `Contents: Read-only`, `Metadata: Read-only`
5. Organization / Account permissions: all `No access`
6. Scope: "Only on this account"
7. Create the App and note the **App ID**
8. On the App settings page, scroll to "Private keys" and generate one —
   download the `.pem` file
9. In the sidebar, click "Install App" → install on the org →
   "Only select repositories" → pick the repos that need ArgoCD access
10. The post-install URL contains the **Installation ID**:
    `https://github.com/organizations/<org>/settings/installations/<ID>`

Pass the three values (App ID, Installation ID, PEM contents) into the
module.

## What this module does NOT do

- Does not create the GitHub App itself (GitHub has no public API for
  that — manifest-based OAuth flow is close but still needs browser
  handshake)
- Does not install the App on repos (manual or via the GitHub API
  outside Terraform)
- Does not handle rotation of the GitHub App private key (rare
  operation — follow the usual credential rotation runbook)
