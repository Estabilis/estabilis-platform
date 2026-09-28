# spaces-bucket-with-key-protected

The protected sibling of [`spaces-bucket-with-key`](../spaces-bucket-with-key).
Same bucket-and-scoped-key unit, for buckets that hold data a plan must never be
able to destroy.

## What it changes, and why none of it is a variable

| | `spaces-bucket-with-key` | this module |
|---|---|---|
| destroy protection | none | `lifecycle { prevent_destroy = true }` on the bucket |
| `force_destroy` | a variable (default false) | fixed to `false` |
| `enabled` toggle | yes (`count`) | none — always creates |
| `versioning_enabled` default | `false` | `true` |

`prevent_destroy` takes a **literal**, not an expression, so it cannot be a
module input — protection is the identity of this module, not a setting a caller
flips from a tfvars file. Any plan that would destroy or replace the bucket — a
rename, a region change, a removal, `force_destroy` — fails at plan time.

There is deliberately no `enabled` flag: "turn it off" and "delete the data" are
the same operation on a bucket, and this module refuses to offer it. Choose this
module when the bucket holds something that would hurt to lose; choose the plain
one for scratch.

## The key stays replaceable

Only the bucket is frozen. The scoped key carries no `prevent_destroy`, so
rotating it is an ordinary apply. Create/destroy order still comes from the
grant referencing the bucket resource, exactly as in the plain module: bucket
then key on create, key then bucket on destroy.

## Not the pattern for a state bucket

Same caveat as the plain module: the Terraform state bucket
(`providers/digitalocean/tfstate.tf`) grants by NAME and uses `depends_on`
because it is released from Terraform management after bootstrap. This module's
scoped key references the bucket resource, so it is not a fit for a backend
bucket. Do not unify the two.

## Usage

```hcl
module "evidence" {
  source = "github.com/Estabilis/estabilis-platform//modules/spaces-bucket-with-key-protected?ref=vX.Y.Z"

  name   = "nsights-datahub-prd-a1b2c3"
  region = "nyc3"
  # versioning_enabled defaults true; permission defaults readwrite
}
```
