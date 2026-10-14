locals {
  deployments_dir = "${path.module}/../deployments"

  # One YAML file == one gateway deployment. The file name is the Terraform key.
  deployments = {
    for f in fileset(local.deployments_dir, "*.yaml") :
    trimsuffix(f, ".yaml") => yamldecode(file("${local.deployments_dir}/${f}"))
  }

  backend_types = {
    http     = "HTTP_BACKEND"
    function = "ORACLE_FUNCTIONS_BACKEND"
    stock    = "STOCK_RESPONSE_BACKEND"
  }

  gateway_id = var.create_gateway ? oci_apigateway_gateway.this[0].id : var.existing_gateway_id

  tags = {
    "managed-by"  = "terraform"
    "environment" = var.environment
  }

  log_targets = {
    for pair in setproduct(keys(local.deployments), ["access", "execution"]) :
    "${pair[0]}-${pair[1]}" => { deployment = pair[0], category = pair[1] }
  }
}

# ---------------------------------------------------------------- Gateway
resource "oci_apigateway_gateway" "this" {
  count = var.create_gateway ? 1 : 0

  compartment_id             = var.compartment_ocid
  display_name               = "${var.gateway_name}-${var.environment}"
  endpoint_type              = var.gateway_endpoint_type
  subnet_id                  = var.subnet_id
  network_security_group_ids = var.network_security_group_ids
  freeform_tags              = local.tags

  lifecycle {
    precondition {
      condition     = var.subnet_id != null
      error_message = "subnet_id is required when create_gateway = true."
    }
  }
}

# ------------------------------------------------------------ Deployments
resource "oci_apigateway_deployment" "this" {
  for_each = local.deployments

  compartment_id = var.compartment_ocid
  gateway_id     = local.gateway_id
  display_name   = each.value.name
  path_prefix    = each.value.path_prefix
  freeform_tags  = local.tags

  specification {
    # ---- deployment-wide policies (auth, CORS, rate limit)
    dynamic "request_policies" {
      for_each = (
        try(each.value.auth, null) != null ||
        try(each.value.cors, null) != null ||
        try(each.value.rate_limit, null) != null
      ) ? [1] : []

      content {
        dynamic "authentication" {
          for_each = [for a in [try(each.value.auth, null)] : a if a != null]
          content {
            type                        = "JWT_AUTHENTICATION"
            token_header                = "Authorization"
            token_auth_scheme           = "Bearer"
            issuers                     = [authentication.value.issuer]
            audiences                   = authentication.value.audiences
            is_anonymous_access_allowed = anytrue([for r in each.value.routes : try(r.anonymous, false)])

            public_keys {
              type                        = "REMOTE_JWKS"
              uri                         = authentication.value.jwks_uri
              max_cache_duration_in_hours = 1
            }
          }
        }

        dynamic "cors" {
          for_each = [for c in [try(each.value.cors, null)] : c if c != null]
          content {
            allowed_origins              = cors.value.allowed_origins
            allowed_methods              = try(cors.value.allowed_methods, null)
            allowed_headers              = try(cors.value.allowed_headers, null)
            exposed_headers              = try(cors.value.exposed_headers, null)
            is_allow_credentials_enabled = try(cors.value.allow_credentials, null)
            max_age_in_seconds           = try(cors.value.max_age_seconds, null)
          }
        }

        dynamic "rate_limiting" {
          for_each = [for r in [try(each.value.rate_limit, null)] : r if r != null]
          content {
            rate_in_requests_per_second = rate_limiting.value.requests_per_second
            rate_key                    = try(rate_limiting.value.key, "CLIENT_IP")
          }
        }
      }
    }

    logging_policies {
      access_log {
        is_enabled = true
      }
      execution_log {
        is_enabled = true
        log_level  = var.log_level
      }
    }

    # ---- routes
    dynamic "routes" {
      for_each = each.value.routes

      content {
        path    = routes.value.path
        methods = routes.value.methods

        backend {
          type        = local.backend_types[routes.value.backend.type]
          url         = try(routes.value.backend.url, null)
          function_id = try(routes.value.backend.function_id, null)
          status      = try(routes.value.backend.status, null)
          body        = try(routes.value.backend.body, null)

          connect_timeout_in_seconds = try(routes.value.backend.connect_timeout_seconds, null)
          read_timeout_in_seconds    = try(routes.value.backend.read_timeout_seconds, null)
          send_timeout_in_seconds    = try(routes.value.backend.send_timeout_seconds, null)

          dynamic "headers" {
            for_each = try(routes.value.backend.headers, [])
            content {
              name  = headers.value.name
              value = headers.value.value
            }
          }
        }

        dynamic "request_policies" {
          for_each = (
            length(try(routes.value.scopes, [])) > 0 || try(routes.value.anonymous, false)
          ) ? [1] : []

          content {
            authorization {
              type          = length(try(routes.value.scopes, [])) > 0 ? "ANY_OF" : "ANONYMOUS"
              allowed_scope = length(try(routes.value.scopes, [])) > 0 ? routes.value.scopes : null
            }
          }
        }
      }
    }
  }

  lifecycle {
    precondition {
      condition = !(
        try(each.value.auth, null) == null &&
        anytrue([for r in each.value.routes : length(try(r.scopes, [])) > 0 || try(r.anonymous, false)])
      )
      error_message = "Routes using `scopes` or `anonymous` require an `auth` block on the deployment."
    }
  }
}

# ---------------------------------------------------------------- Logging
resource "oci_logging_log_group" "apigw" {
  compartment_id = var.compartment_ocid
  display_name   = "${var.gateway_name}-${var.environment}-logs"
  freeform_tags  = local.tags
}

resource "oci_logging_log" "this" {
  for_each = local.log_targets

  display_name       = each.key
  log_group_id       = oci_logging_log_group.apigw.id
  log_type           = "SERVICE"
  is_enabled         = true
  retention_duration = var.log_retention_days
  freeform_tags      = local.tags

  configuration {
    compartment_id = var.compartment_ocid
    source {
      category    = each.value.category
      resource    = oci_apigateway_deployment.this[each.value.deployment].id
      service     = "apigateway"
      source_type = "OCISERVICE"
    }
  }
}

# ------------------------------------------- Optional: gateway -> Functions
resource "oci_identity_policy" "apigw_functions" {
  count = var.create_functions_policy ? 1 : 0

  compartment_id = var.compartment_ocid
  name           = "${var.gateway_name}-${var.environment}-invoke-functions"
  description    = "Allow API Gateway to invoke OCI Functions"
  statements = [
    "ALLOW any-user to use functions-family in compartment id ${var.compartment_ocid} where ALL {request.principal.type = 'ApiGateway', request.resource.compartment.id = '${var.compartment_ocid}'}"
  ]
}
