output "bucket_name" {
  description = "Bucket name, or null when disabled."
  value       = one(digitalocean_spaces_bucket.this[*].name)
}

output "bucket_urn" {
  description = "Bucket urn, for assignment to a DigitalOcean Project."
  value       = one(digitalocean_spaces_bucket.this[*].urn)
}

output "bucket_endpoint" {
  description = "S3-compatible endpoint."
  value       = one(digitalocean_spaces_bucket.this[*].endpoint)
}

output "access_key_id" {
  description = "Access key ID of the scoped key."
  value       = one(digitalocean_spaces_key.this[*].access_key)
}

output "secret_key" {
  description = "Secret of the scoped key. Stored in Terraform state, like every credential Terraform creates."
  value       = one(digitalocean_spaces_key.this[*].secret_key)
  sensitive   = true
}
