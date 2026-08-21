variable "enabled" {
  description = "Create the bucket and its key. False destroys both — they share one lifecycle by design."
  type        = bool
  default     = false
}

variable "name" {
  description = "Bucket name. Spaces names are globally unique across every DigitalOcean account, so include a random suffix."
  type        = string
}

variable "region" {
  description = "Spaces region."
  type        = string
}

variable "key_name" {
  description = "Name of the scoped key. Empty derives `{name}-key`."
  type        = string
  default     = ""
}

variable "permission" {
  description = "Grant on the bucket: read, readwrite or fullaccess. A scoped key reaches only this bucket regardless."
  type        = string
  default     = "readwrite"

  validation {
    condition     = contains(["read", "readwrite", "fullaccess"], var.permission)
    error_message = "permission must be one of: read, readwrite, fullaccess."
  }
}

variable "versioning_enabled" {
  description = "Keep prior object versions. Note versioned objects are what makes force_destroy insufficient on teardown."
  type        = bool
  default     = false
}

variable "force_destroy" {
  description = "Allow destroying the bucket while it holds objects. Does NOT cover object versions — see scripts/empty-spaces-bucket.py."
  type        = bool
  default     = false
}

variable "abort_incomplete_multipart_days" {
  description = "Abort unfinished multipart uploads after N days. 0 disables the rule."
  type        = number
  default     = 7
}

variable "expire_noncurrent_days" {
  description = "Expire non-current object versions after N days. 0 disables. Ignored unless versioning is on."
  type        = number
  default     = 0
}
