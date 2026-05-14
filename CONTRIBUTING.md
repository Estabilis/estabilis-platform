# Contributing to `estabilis-platform`

This document captures conventions that aren't obvious from the code but
matter for keeping downstream consumers (`estabilis-platform-downstream`
templates and per-client downstream repos) safe and predictable.

## IRSA module convention (AWS provider)

The `providers/aws/` module composes the upstream
[`terraform-aws-modules/iam-role-for-service-accounts`][upstream] submodule
for each cluster-scoped workload that needs AWS API access via IRSA. Today
six built-in IRSA bundles are wired:

| Module                  | File                          | Canonical policy name           |
| ----------------------- | ----------------------------- | ------------------------------- |
| `external_secrets_irsa` | `providers/aws/iam.tf`        | `External_Secrets`              |
| `external_dns_irsa`     | `providers/aws/iam.tf`        | `External_DNS`                  |
| `cert_manager_irsa`     | `providers/aws/iam.tf`        | `Cert_Manager`                  |
| `velero_irsa`           | `providers/aws/iam.tf`        | `Velero`                        |
| `ebs_csi_irsa`          | `providers/aws/eks.tf`        | `EBS_CSI`                       |
| `alb_controller_irsa`   | `providers/aws/alb-controller.tf` | `AWS_Load_Balancer_Controller` |

### The pitfall

When you set `attach_<name>_policy = true` and leave `policy_name` unset, the
upstream submodule **hardcodes** the canonical name (see
`policy_name = try(coalesce(...))` in the submodule source). IAM policies
are **account-scoped**, not cluster-scoped. So a second EKS cluster brought
up in the same AWS account that enables the same IRSA bundle fails at
apply time with `EntityAlreadyExists`.

This bit us in May 2026 when bootstrapping `cortex-platform-hml` alongside
the existing `cortex-platform-prd` (both in account `093996075120`). Four
of the six policies collided in a single `terraform apply`.

### The rule

**Every new IRSA module added to `providers/aws/` MUST set an explicit
`policy_name` gated on `var.iam_policy_name_use_cluster_prefix`.** Default
`false` preserves backward compatibility with clusters that already own the
unprefixed name; set `true` on new clusters in shared accounts.

The pattern, applied identically to all six modules above:

```hcl
module "<name>_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.5"

  use_name_prefix          = false
  name                     = "${local.cluster_name}-<name>"
  attach_<name>_policy     = true

  # See CONTRIBUTING.md "IRSA module convention".
  policy_name = var.iam_policy_name_use_cluster_prefix ? "${local.cluster_name}-<Canonical>" : null

  oidc_providers = { ... }
}
```

`<Canonical>` is the exact string the submodule would have hardcoded
(check the upstream submodule's `coalesce` cascade for the
`attach_<name>_policy = true` branch). Setting `policy_name = null` in the
`false` branch is critical — it preserves the submodule's existing
canonical-name behavior, which is what existing clusters in the field
already own.

### Why not just always prefix?

Backward compatibility. Existing production clusters already own the
unprefixed policy names. Flipping the default to `true` would plan
delete-then-create on the policy resources in every running cluster,
briefly revoking pod permissions across the platform — an outage we won't
inflict for an aesthetic improvement.

### Migration path for existing single-cluster-per-account deployments

If you must rename the policies on a running cluster (e.g. to onboard a
second cluster in the same account), do it as a controlled migration:

1. `terraform plan` — confirm the diff is only the IAM policy resources,
   not the IAM roles.
2. Pre-create the new prefixed policies out of band (`aws iam create-policy`)
   and attach to the IRSA roles ahead of the apply.
3. Run apply during a maintenance window — there will still be a brief
   window during the in-place policy version replacement.
4. After apply, delete the old unprefixed policies manually.

Or, simpler: bring up the second cluster with `iam_policy_name_use_cluster_prefix = true`
and leave the first cluster on the canonical names indefinitely. Both modes
coexist permanently.

[upstream]: https://github.com/terraform-aws-modules/terraform-aws-iam/tree/master/modules/iam-role-for-service-accounts

## Release process

1. Land all feature PRs to `main`.
2. Bump `VERSION` and add a `CHANGELOG.md` entry under the new
   `## [X.Y.Z]` header (no `[Unreleased]` accumulator — entries are
   written directly under the version they ship in).
3. Commit with subject `chore(release): vX.Y.Z` and **direct-push** to
   `main`. Do NOT route through a PR — squash merge rewrites the subject
   to `chore(release): vX.Y.Z (#NNN)`, which breaks the auto-tag
   workflow's prefix regex.
4. The `.github/workflows/auto-tag.yml` workflow tags the commit and
   publishes the GitHub Release page automatically.
5. Propagate to downstream template + clients per the version-propagation
   checklist in the consumer repo's `CLAUDE.md`.
