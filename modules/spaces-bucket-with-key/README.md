# spaces-bucket-with-key

Creates a DigitalOcean Spaces bucket together with the access key scoped to it,
as a single unit that cannot come apart.

## Why the two are one module

On DigitalOcean a scoped Spaces key reaches exactly the one bucket named in its
grant, so every bucket needs its own key. That makes two failure states
possible, and both are silent:

- a bucket with no key — storage nothing can reach
- a key with no bucket — an orphaned credential nobody will notice

One `enabled` flag drives both resources, so neither state is representable.

## Ordering comes from the reference, not from `depends_on`

The key's grant names the bucket **resource**, not a string. That single
reference puts them in Terraform's dependency graph and fixes the order in both
directions:

| | order | why it has to be that way |
|---|---|---|
| create | bucket, then key | DigitalOcean rejects a grant naming a bucket that does not exist: `403 invalid grant` |
| destroy | key, then bucket | reverse dependency order, which Terraform derives on its own |

Verified by applying and destroying: creation logs the bucket complete before
the key starts; destruction logs the key complete before the bucket starts; and
disabling the module leaves no key behind.

## Not the pattern for a state bucket

The Terraform state bucket in `providers/digitalocean/tfstate.tf` does the
opposite — it grants by NAME and uses `depends_on`. That is deliberate: the
state bucket is released from Terraform management after bootstrap
(`terraform state rm`), and a key referencing the resource would be destroyed
with it, taking the backend's only credential. Do not "unify" the two.

## Usage

```hcl
module "observability_storage" {
  source = "../../modules/spaces-bucket-with-key"

  enabled = var.observability_bucket_enabled
  name    = "${var.name_prefix}-observability-${local.env_code}-${local.suffix}"
  region  = var.region

  versioning_enabled = false
}
```

Bucket names are globally unique across every DigitalOcean account, so include
a random suffix rather than a predictable name.

## Inputs

| Name | Default | Notes |
|---|---|---|
| `enabled` | `false` | drives both resources |
| `name` | — | required; globally unique |
| `region` | — | required; a region where Spaces is offered |
| `key_name` | `""` | derives `{name}-key` |
| `permission` | `readwrite` | `read`, `readwrite` or `fullaccess`; scoped to this bucket either way |
| `versioning_enabled` | `false` | note versioned objects are why `force_destroy` is not enough on teardown |
| `force_destroy` | `false` | does NOT cover object versions — every object version has to be removed first — the downstream template ships a script for it |
| `abort_incomplete_multipart_days` | `7` | `0` disables |
| `expire_noncurrent_days` | `0` | `0` disables; ignored without versioning |

## Outputs

`bucket_name`, `bucket_urn`, `bucket_endpoint`, `access_key_id`, and
`secret_key` (sensitive).

`bucket_urn` is what a DigitalOcean Project assignment needs. Note the project
API rejects a urn for a bucket that does not exist yet, so gate the assignment
on the same flag.
