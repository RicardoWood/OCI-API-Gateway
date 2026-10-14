variable "region" {
  type        = string
  description = "OCI region identifier, e.g. uk-london-1"
}

variable "tenancy_ocid" {
  type    = string
  default = null
}

variable "user_ocid" {
  type    = string
  default = null
}

variable "fingerprint" {
  type    = string
  default = null
}

variable "private_key_path" {
  type    = string
  default = null
}

variable "compartment_ocid" {
  type        = string
  description = "Compartment for the gateway, deployments and logs"
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "create_gateway" {
  type        = bool
  default     = true
  description = "false = deploy into an existing gateway (set existing_gateway_id)"
}

variable "existing_gateway_id" {
  type    = string
  default = null
}

variable "gateway_name" {
  type    = string
  default = "api-gateway"
}

variable "gateway_endpoint_type" {
  type    = string
  default = "PUBLIC"

  validation {
    condition     = contains(["PUBLIC", "PRIVATE"], var.gateway_endpoint_type)
    error_message = "Must be PUBLIC or PRIVATE."
  }
}

variable "subnet_id" {
  type        = string
  default     = null
  description = "Regional subnet for the gateway (required when create_gateway = true)"
}

variable "network_security_group_ids" {
  type    = list(string)
  default = []
}

variable "log_level" {
  type    = string
  default = "INFO"

  validation {
    condition     = contains(["INFO", "WARN", "ERROR"], var.log_level)
    error_message = "Must be INFO, WARN or ERROR."
  }
}

variable "log_retention_days" {
  type        = number
  default     = 30
  description = "OCI Logging retention, in 30-day increments (30-180)"
}

variable "create_functions_policy" {
  type        = bool
  default     = false
  description = "Create the IAM policy letting the gateway invoke OCI Functions (needed for `function` backends)"
}
