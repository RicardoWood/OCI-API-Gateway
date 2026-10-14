# OCI API Gateway: route deployment pipeline

Add or edit a YAML file in `deployments/`, open a PR, merge. The pipeline validates it, plans, and applies it to OCI API Gateway.

```
deployments/*.yaml -> validate (schema + terraform validate) -> plan -> [approval] -> apply
one file = one API Gateway deployment (path_prefix + routes, JWT auth, CORS, rate limit)
```

| Path | Purpose |
|---|---|
| `deployments/` | Route definitions (source of truth) |
| `schema/deployment.schema.json` | JSON Schema for those files |
| `scripts/validate_deployments.py` | Schema + cross-file checks (duplicate prefixes/routes, scopes without auth) |
| `terraform/` | Gateway, deployments, access/execution logs, optional Functions IAM policy |
| `.github/workflows/deploy.yml` | PR: validate + plan. `main`: validate + plan + apply |

## One-time setup

**1. OCI prerequisites**
- A regional subnet for the gateway (for a PUBLIC gateway, allow ingress TCP 443). Or use an existing gateway: set `create_gateway=false` and `existing_gateway_id`.
- An Object Storage bucket for Terraform state, plus a **Customer Secret Key** for the CI user (User settings > Customer secret keys).
- A CI user with an API key, in a group with roughly:
```
Allow group api-deployers to manage api-gateway-family in compartment <c>
Allow group api-deployers to manage logging-family in compartment <c>
Allow group api-deployers to use virtual-network-family in compartment <c>
Allow group api-deployers to manage objects in compartment <c> where target.bucket.name='<state-bucket>'
Allow group api-deployers to use functions-family in compartment <c>      # function backends
Allow group api-deployers to manage policies in compartment <c>           # only if create_functions_policy=true
```

**2. GitHub settings**

| Type | Name |
|---|---|
| Secret | `OCI_TENANCY_OCID`, `OCI_USER_OCID`, `OCI_FINGERPRINT`, `OCI_PRIVATE_KEY` (PEM contents), `TF_STATE_ACCESS_KEY`, `TF_STATE_SECRET_KEY` |
| Variable | `OCI_REGION`, `OCI_COMPARTMENT_OCID`, `OCI_SUBNET_OCID`, `TF_STATE_BUCKET`, `TF_STATE_NAMESPACE`, `ENVIRONMENT` (optional, default `prod`) |

Create a GitHub **Environment** named `production` and add required reviewers for a manual approval gate before apply.

**3. Add a route**: copy `deployments/orders.yaml`, edit, PR. Endpoints are printed in the run summary.

## Route file reference

- `backend.type`: `http` (url, optional timeouts), `function` (function_id), `stock` (status, body, headers).
- `scopes`: JWT scopes required for the route (needs deployment-level `auth`).
- `anonymous: true`: bypass JWT on one route of an authenticated deployment.
- Path params: `/{orderId}` in `path`, used as `${request.path[orderId]}` in backend URLs.

## Running locally
```bash
pip install pyyaml jsonschema && python scripts/validate_deployments.py
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edit
terraform init -backend=false                  # or -backend-config=backend.hcl
terraform plan
```

## Notes
- HTTP backends on private networks need a network path from the gateway subnet.
- OCI's S3-compatible backend has no state locking; the workflow `concurrency` group serialises CI runs. Avoid local `apply` against shared state.
- Deleting a YAML file removes its deployment on the next apply.
