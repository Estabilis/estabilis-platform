# ---------------------------------------------------------------------------
# VPC Endpoints
#
# Rationale: every call to an AWS service API from a pod/node that exits
# through NAT incurs $0.045/GB + $0.045/hour. For busy clusters (ECR pulls,
# Secrets Manager reads, STS AssumeRoleWithWebIdentity, CloudWatch log
# shipping) this adds up to hundreds of dollars/mo. VPC endpoints route
# traffic directly on the AWS backbone — free for gateway endpoints,
# ~$7/mo + $0.01/GB for interface endpoints.
#
# Also reduces security blast radius: traffic never leaves AWS to reach
# S3/ECR/KMS/SM.
# ---------------------------------------------------------------------------

locals {
  gateway_endpoint_services = {
    for svc, enabled in var.vpc_endpoints_gateway : svc => enabled if enabled
  }

  interface_endpoint_services = {
    for svc, enabled in var.vpc_endpoints_interface : svc => enabled if enabled
  }

  # Map the shorthand service name in variables to the full AWS service
  # endpoint string. Keeps the variable keys stable even if AWS renames
  # internal service identifiers.
  interface_endpoint_service_names = {
    ecr_api              = "com.amazonaws.${var.region}.ecr.api"
    ecr_dkr              = "com.amazonaws.${var.region}.ecr.dkr"
    sts                  = "com.amazonaws.${var.region}.sts"
    secretsmanager       = "com.amazonaws.${var.region}.secretsmanager"
    kms                  = "com.amazonaws.${var.region}.kms"
    logs                 = "com.amazonaws.${var.region}.logs"
    ec2                  = "com.amazonaws.${var.region}.ec2"
    elasticloadbalancing = "com.amazonaws.${var.region}.elasticloadbalancing"
    autoscaling          = "com.amazonaws.${var.region}.autoscaling"
  }
}

# ---------------------------------------------------------------------------
# Security group for interface VPC endpoints — allow HTTPS from the VPC
# CIDR so any pod/node can reach the endpoint ENIs.
# ---------------------------------------------------------------------------

resource "aws_security_group" "vpc_endpoints" {
  count = length(local.interface_endpoint_services) > 0 ? 1 : 0

  name_prefix = "${local.cluster_name}-vpce-"
  description = "Ingress for VPC interface endpoints (${local.cluster_name})"
  vpc_id      = local.vpc_id

  ingress {
    description = "HTTPS from VPC"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.cluster_name}-vpce"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Gateway endpoints — S3 and DynamoDB. Free, only cost is route table
# entries. Route tables must span both private (for nodes/pods) and public
# (for completeness) so the endpoint is reachable from every subnet.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "gateway" {
  for_each = local.gateway_endpoint_services

  vpc_id            = local.vpc_id
  service_name      = "com.amazonaws.${var.region}.${each.key}"
  vpc_endpoint_type = "Gateway"

  route_table_ids = concat(
    local.private_route_table_ids,
    local.public_route_table_ids,
  )

  tags = {
    Name = "vpce-${local.base_name}-${each.key}"
  }
}

# ---------------------------------------------------------------------------
# Interface endpoints — use ENIs in private subnets with optional private
# DNS so SDK calls transparently resolve to the endpoint.
# ---------------------------------------------------------------------------

resource "aws_vpc_endpoint" "interface" {
  for_each = local.interface_endpoint_services

  vpc_id              = local.vpc_id
  service_name        = local.interface_endpoint_service_names[each.key]
  vpc_endpoint_type   = "Interface"
  subnet_ids          = local.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints[0].id]
  private_dns_enabled = var.vpc_endpoints_private_dns_enabled

  tags = {
    Name = "vpce-${local.base_name}-${replace(each.key, "_", "-")}"
  }
}
