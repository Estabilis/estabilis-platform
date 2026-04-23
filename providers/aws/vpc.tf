# ---------------------------------------------------------------------------
# VPC — create or look up existing
#
# EKS requires at least 2 AZs. When vpc_mode = "create":
#   - New VPC with var.vpc_cidr
#   - Private subnets (length = availability_zone_count), sized via
#     private_subnet_newbits (default /20 from /16)
#   - Public subnets (when public_subnets_enabled) sized via
#     public_subnet_newbits + public_subnet_offset
#   - Internet Gateway + public route table
#   - Karpenter + kubernetes.io/role discovery tags applied to subnets so
#     the EKS + ALB Controller + Karpenter all find them automatically
#
# When vpc_mode = "existing":
#   - Read VPC + subnets via data sources
#   - Caller is responsible for tagging subnets with the discovery tags
#     (eks.tf does a best-effort tag on the subnets it knows about, but
#      this only works if the IAM principal has ec2:CreateTags)
# ---------------------------------------------------------------------------

# ===========================================================================
# Create mode
# ===========================================================================

resource "aws_vpc" "platform" {
  count = var.vpc_mode == "create" ? 1 : 0

  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-${local.base_name}"
  }
}

resource "aws_internet_gateway" "platform" {
  count = var.vpc_mode == "create" && var.public_subnets_enabled ? 1 : 0

  vpc_id = aws_vpc.platform[0].id

  tags = {
    Name = "igw-${local.base_name}"
  }
}

resource "aws_subnet" "private" {
  count = var.vpc_mode == "create" ? var.availability_zone_count : 0

  vpc_id            = aws_vpc.platform[0].id
  cidr_block        = local.private_subnet_cidrs[count.index]
  availability_zone = local.azs_selected[count.index]

  tags = {
    Name                                          = "snet-${local.base_name}-private-${local.azs_selected[count.index]}"
    "kubernetes.io/role/internal-elb"             = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    (var.karpenter_discovery_tag_key)             = local.cluster_name
  }
}

resource "aws_subnet" "public" {
  count = var.vpc_mode == "create" && var.public_subnets_enabled ? var.availability_zone_count : 0

  vpc_id                  = aws_vpc.platform[0].id
  cidr_block              = local.public_subnet_cidrs[count.index]
  availability_zone       = local.azs_selected[count.index]
  map_public_ip_on_launch = false

  tags = {
    Name                                          = "snet-${local.base_name}-public-${local.azs_selected[count.index]}"
    "kubernetes.io/role/elb"                      = "1"
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
  }
}

# Public route table — routes 0.0.0.0/0 via the Internet Gateway. Associated
# with every public subnet.
resource "aws_route_table" "public" {
  count = var.vpc_mode == "create" && var.public_subnets_enabled ? 1 : 0

  vpc_id = aws_vpc.platform[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.platform[0].id
  }

  tags = {
    Name = "rt-${local.base_name}-public"
  }
}

resource "aws_route_table_association" "public" {
  count = var.vpc_mode == "create" && var.public_subnets_enabled ? var.availability_zone_count : 0

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public[0].id
}

# Private route tables — one per AZ so per-AZ NAT Gateways can be wired
# individually by nat-gateway.tf. Even with a single shared NAT, keeping
# one RT per AZ keeps the topology symmetric and simplifies future HA
# upgrades.
resource "aws_route_table" "private" {
  count = var.vpc_mode == "create" ? var.availability_zone_count : 0

  vpc_id = aws_vpc.platform[0].id

  tags = {
    Name = "rt-${local.base_name}-private-${local.azs_selected[count.index]}"
  }
}

resource "aws_route_table_association" "private" {
  count = var.vpc_mode == "create" ? var.availability_zone_count : 0

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ===========================================================================
# Existing mode — data sources only
# ===========================================================================

data "aws_vpc" "existing" {
  count = var.vpc_mode == "existing" ? 1 : 0
  id    = var.vpc_id
}

data "aws_subnet" "existing_private" {
  count = var.vpc_mode == "existing" ? length(var.private_subnet_ids) : 0
  id    = var.private_subnet_ids[count.index]
}

data "aws_subnet" "existing_public" {
  count = var.vpc_mode == "existing" ? length(var.public_subnet_ids) : 0
  id    = var.public_subnet_ids[count.index]
}

# ===========================================================================
# Unified locals — eks.tf / karpenter.tf / nat-gateway.tf / sg.tf read these
# regardless of mode.
# ===========================================================================

locals {
  vpc_id         = var.vpc_mode == "create" ? aws_vpc.platform[0].id : data.aws_vpc.existing[0].id
  vpc_cidr_block = var.vpc_mode == "create" ? aws_vpc.platform[0].cidr_block : data.aws_vpc.existing[0].cidr_block

  private_subnet_ids = var.vpc_mode == "create" ? aws_subnet.private[*].id : var.private_subnet_ids
  public_subnet_ids  = var.vpc_mode == "create" && var.public_subnets_enabled ? aws_subnet.public[*].id : var.public_subnet_ids

  private_subnet_azs      = var.vpc_mode == "create" ? aws_subnet.private[*].availability_zone : data.aws_subnet.existing_private[*].availability_zone
  private_route_table_ids = var.vpc_mode == "create" ? aws_route_table.private[*].id : []
  public_route_table_ids  = var.vpc_mode == "create" && var.public_subnets_enabled ? [aws_route_table.public[0].id] : []
}

# ---------------------------------------------------------------------------
# Harden the VPC default Security Group — revoke all ingress and egress
# rules. CIS AWS Foundations Benchmark 5.3. Applies to both modes.
#
# Explicit empty ingress/egress guards against the AWS provider silently
# changing implicit behavior in future versions: absent blocks are not the
# same as empty blocks in recent provider releases.
# ---------------------------------------------------------------------------

resource "aws_default_security_group" "revoked" {
  count = var.security_groups_hardening_enabled ? 1 : 0

  vpc_id = local.vpc_id

  ingress = []
  egress  = []

  tags = {
    Name = "${local.base_name}-default-revoked"
  }
}
