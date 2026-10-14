terraform {
  required_version = ">= 1.9.0"

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = ">= 6.0.0"
    }
  }
}

# Credentials: in CI the values arrive via TF_VAR_* env vars. Locally, leave them
# null and the provider falls back to ~/.oci/config (DEFAULT profile).
provider "oci" {
  region           = var.region
  tenancy_ocid     = var.tenancy_ocid
  user_ocid        = var.user_ocid
  fingerprint      = var.fingerprint
  private_key_path = var.private_key_path
}
