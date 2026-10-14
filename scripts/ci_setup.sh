#!/usr/bin/env bash
# CI helper: writes the OCI API key to disk and generates the Terraform backend config.
# Required env: OCI_PRIVATE_KEY OCI_REGION TF_STATE_BUCKET TF_STATE_NAMESPACE TF_ENV
set -euo pipefail
umask 077

KEY_FILE="${RUNNER_TEMP:-/tmp}/oci_api_key.pem"
printf '%s\n' "$OCI_PRIVATE_KEY" > "$KEY_FILE"

cat > terraform/backend.hcl <<EOF
bucket    = "${TF_STATE_BUCKET}"
key       = "api-gateway/${TF_ENV}/terraform.tfstate"
region    = "${OCI_REGION}"
endpoints = { s3 = "https://${TF_STATE_NAMESPACE}.compat.objectstorage.${OCI_REGION}.oraclecloud.com" }
EOF

echo "TF_VAR_private_key_path=${KEY_FILE}" >> "${GITHUB_ENV:?must run inside GitHub Actions}"
