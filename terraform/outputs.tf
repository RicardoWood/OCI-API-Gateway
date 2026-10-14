output "gateway_id" {
  value = local.gateway_id
}

output "gateway_hostname" {
  value = var.create_gateway ? oci_apigateway_gateway.this[0].hostname : null
}

output "deployment_endpoints" {
  description = "Base URL of each deployment"
  value       = { for k, d in oci_apigateway_deployment.this : k => d.endpoint }
}
