# ---------------------------------------------------------------------------
# Cluster additional Security Group + node-level ingress rules
#
# The EKS module creates two SGs automatically:
#   - cluster SG:  attached to the control-plane ENIs
#   - node SG:     attached to EC2 nodes (managed + Karpenter-provisioned)
#
# This file adds a third SG ("cluster_additional") owned by Terraform that:
#   - Is attached to the EKS cluster's additional_security_group_ids
#   - Applies to both control plane and node ENIs as a defense-in-depth
#     surface for operator-defined rules (on-prem peering, SaaS callbacks,
#     ingress flows when ingress_controller = 'traefik')
#
# Shape mirrors the Azure provider's nsg.tf: HTTP(S) rules only when
# ingress_controller = 'traefik' (ALB Controller creates its own SGs), and
# an extra_ingress_rules map for custom rules.
# ---------------------------------------------------------------------------

resource "aws_security_group" "cluster_additional" {
  count = var.security_groups_hardening_enabled ? 1 : 0

  name_prefix = "${local.cluster_name}-additional-"
  description = "Estabilis platform additional SG: operator-defined ingress for ${local.cluster_name}"
  vpc_id      = local.vpc_id

  # Egress fully open — EKS control plane and nodes need outbound to public
  # registries, AWS APIs, DNS, NTP, etc. Egress restriction should happen
  # at the VPC/firewall layer (e.g., egress filter via Network Firewall) or
  # via Cilium FQDN policies — not at the SG level.
  egress {
    description      = "All outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = "${local.cluster_name}-additional"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# HTTP(S) ingress — only when Traefik is the ingress controller. ALB
# Controller creates and manages its own SGs for public ALB traffic.
# ---------------------------------------------------------------------------

locals {
  ingress_render_http = (
    var.security_groups_hardening_enabled &&
    var.ingress_controller == "traefik"
  )

  ingress_cidrs = length(var.ingress_allowed_ip_ranges) > 0 ? var.ingress_allowed_ip_ranges : ["0.0.0.0/0"]
}

resource "aws_vpc_security_group_ingress_rule" "allow_https" {
  for_each = local.ingress_render_http ? toset(local.ingress_cidrs) : []

  security_group_id = aws_security_group.cluster_additional[0].id
  description       = "Traefik HTTPS ingress from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "allow_http" {
  for_each = local.ingress_render_http ? toset(local.ingress_cidrs) : []

  security_group_id = aws_security_group.cluster_additional[0].id
  description       = "Traefik HTTP ingress from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

# ---------------------------------------------------------------------------
# Custom ingress rules — operator-defined escape hatch. Rendered as discrete
# rule resources so state diffs are readable and removals are surgical.
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "extra_cidr" {
  for_each = {
    for k, v in var.extra_ingress_rules : "${k}-cidr" => v
    if var.security_groups_hardening_enabled && length(v.cidr_blocks) > 0
  }

  security_group_id = aws_security_group.cluster_additional[0].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_ipv4         = each.value.cidr_blocks[0]
}

resource "aws_vpc_security_group_ingress_rule" "extra_ipv6" {
  for_each = {
    for k, v in var.extra_ingress_rules : "${k}-ipv6" => v
    if var.security_groups_hardening_enabled && length(v.ipv6_cidr_blocks) > 0
  }

  security_group_id = aws_security_group.cluster_additional[0].id
  description       = each.value.description
  ip_protocol       = each.value.protocol
  from_port         = each.value.from_port
  to_port           = each.value.to_port
  cidr_ipv6         = each.value.ipv6_cidr_blocks[0]
}

resource "aws_vpc_security_group_ingress_rule" "extra_sg" {
  for_each = {
    for k, v in var.extra_ingress_rules : "${k}-sg" => v
    if var.security_groups_hardening_enabled && length(v.source_security_group_id) > 0
  }

  security_group_id            = aws_security_group.cluster_additional[0].id
  description                  = each.value.description
  ip_protocol                  = each.value.protocol
  from_port                    = each.value.from_port
  to_port                      = each.value.to_port
  referenced_security_group_id = each.value.source_security_group_id
}
