# State lives in OCI Object Storage via its S3-compatible API.
# Bucket / key / endpoint are supplied with: terraform init -backend-config=backend.hcl
# Credentials: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY = an OCI "Customer Secret Key".
# Note: this backend has no native locking on OCI, so CI serialises runs (see workflow).
terraform {
  backend "s3" {
    use_path_style              = true
    skip_region_validation      = true
    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }
}
