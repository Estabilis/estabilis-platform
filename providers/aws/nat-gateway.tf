# ---------------------------------------------------------------------------
# NAT Gateway — outbound internet for private subnets
#
# Two topologies:
#   - nat_gateway_az_count = 1: single NAT in the first public subnet,
#     shared by all private subnets. Cheapest but single-AZ failure removes
#     outbound for the whole cluster.
#   - nat_gateway_az_count = availability_zone_count: one NAT per AZ, each
#     private subnet routes to its local NAT. HA and AZ-isolated, but
#     triples the cost (~$32/mo + $0.045/GB per NAT).
#
# Only rendered when vpc_mode = "create" AND public_subnets_enabled. In
# "existing" mode we assume the caller wired their own NAT/egress.
# ---------------------------------------------------------------------------

locals {
  nat_gateway_render = var.vpc_mode == "create" && var.public_subnets_enabled && var.nat_gateway_enabled
  nat_gateway_count  = local.nat_gateway_render ? var.nat_gateway_az_count : 0
}

resource "aws_eip" "nat" {
  count = local.nat_gateway_count

  domain = "vpc"

  tags = {
    Name = "eip-${local.base_name}-natgw-${local.azs_selected[count.index]}"
  }

  depends_on = [aws_internet_gateway.platform]
}

resource "aws_nat_gateway" "platform" {
  count = local.nat_gateway_count

  allocation_id     = aws_eip.nat[count.index].id
  subnet_id         = aws_subnet.public[count.index].id
  connectivity_type = "public"

  tags = {
    Name = "natgw-${local.base_name}-${local.azs_selected[count.index]}"
  }

  depends_on = [aws_internet_gateway.platform]
}

# Route 0.0.0.0/0 in each private route table to the appropriate NAT. When
# nat_gateway_az_count = 1 every RT targets the single NAT; when per-AZ,
# each RT targets its local NAT.
resource "aws_route" "private_nat" {
  count = var.vpc_mode == "create" && var.nat_gateway_enabled ? var.availability_zone_count : 0

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.platform[min(count.index, local.nat_gateway_count - 1)].id
}

locals {
  nat_gateway_public_ips = aws_eip.nat[*].public_ip
}
