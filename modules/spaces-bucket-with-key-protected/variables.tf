variable "name" {
  description = "Bucket name. Spaces names are globally unique across every DigitalOcean account, so include a random suffix. Changing it would replace the bucket, which prevent_destroy blocks."
  type        = string
}

variable "region" {
  description = "Spaces region. Changing it would replace the bucket, which prevent_destroy blocks."
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
  description = "Keep prior object versions. Defaults true here: this module is for buckets that hold data, and versioning is what lets a bad overwrite be recovered."
  type        = bool
  default     = true
}

variable "abort_incomplete_multipart_days" {
  description = "Abort unfinished multipart uploads after N days. 0 disables the rule."
  type        = number
  default     = 7
}

variable "expire_noncurrent_days" {
  description = "Expire non-current object versions after N days. 0 disables (keep every version). Ignored unless versioning is on."
  type        = number
  default     = 0
}
