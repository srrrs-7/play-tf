# =============================================================================
# Transit Gateway for Direct Connect Integration
# =============================================================================
# Transit Gateway enables connectivity between:
# - This VPC
# - On-premises networks via Direct Connect Gateway
# - Other VPCs (hub-and-spoke architecture)
#
# For Direct Connect, you would:
# 1. Create a Direct Connect Gateway
# 2. Associate it with this Transit Gateway
# 3. Create Transit Virtual Interface on your Direct Connect connection
# =============================================================================

# =============================================================================
# Transit Gateway (Create new or use existing)
# =============================================================================

resource "aws_ec2_transit_gateway" "main" {
  count = var.enable_transit_gateway && var.transit_gateway_id == "" ? 1 : 0

  description                     = "${local.name_prefix} Transit Gateway"
  amazon_side_asn                 = var.transit_gateway_asn
  auto_accept_shared_attachments  = "disable"
  default_route_table_association = "enable"
  default_route_table_propagation = "enable"
  dns_support                     = "enable"
  vpn_ecmp_support                = "enable"

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-tgw"
  })
}

locals {
  # Use existing TGW ID or newly created one
  tgw_id = var.enable_transit_gateway ? (
    var.transit_gateway_id != "" ? var.transit_gateway_id : aws_ec2_transit_gateway.main[0].id
  ) : null
}

# =============================================================================
# Transit Gateway VPC Attachment
# =============================================================================

resource "aws_ec2_transit_gateway_vpc_attachment" "main" {
  count = var.enable_transit_gateway ? 1 : 0

  transit_gateway_id = local.tgw_id
  vpc_id             = aws_vpc.main.id
  subnet_ids         = aws_subnet.private[*].id

  dns_support                                     = "enable"
  transit_gateway_default_route_table_association = true
  transit_gateway_default_route_table_propagation = true

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-tgw-attachment"
  })
}

# =============================================================================
# Routes to On-Premises via Transit Gateway
# =============================================================================

resource "aws_route" "tgw" {
  count = var.enable_transit_gateway ? length(var.transit_gateway_cidr_blocks) : 0

  route_table_id         = aws_route_table.private.id
  destination_cidr_block = var.transit_gateway_cidr_blocks[count.index]
  transit_gateway_id     = local.tgw_id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.main]
}

# =============================================================================
# Transit Gateway Route Table (Optional - for advanced routing)
# =============================================================================

resource "aws_ec2_transit_gateway_route_table" "main" {
  count = var.enable_transit_gateway && var.transit_gateway_id == "" ? 1 : 0

  transit_gateway_id = aws_ec2_transit_gateway.main[0].id

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-tgw-rt"
  })
}

# =============================================================================
# Direct Connect Gateway Association (Reference)
# =============================================================================
# To connect Direct Connect to Transit Gateway:
#
# 1. Create Direct Connect Gateway (if not exists)
# resource "aws_dx_gateway" "main" {
#   name            = "${local.name_prefix}-dxgw"
#   amazon_side_asn = "64513"
# }
#
# 2. Associate Direct Connect Gateway with Transit Gateway
# resource "aws_dx_gateway_association" "main" {
#   dx_gateway_id         = aws_dx_gateway.main.id
#   associated_gateway_id = aws_ec2_transit_gateway.main[0].id
#
#   allowed_prefixes = [var.vpc_cidr]
# }
#
# 3. Create Transit Virtual Interface on Direct Connect Connection
# resource "aws_dx_transit_virtual_interface" "main" {
#   connection_id  = "dxcon-xxxxxxxx"  # Your Direct Connect connection ID
#   dx_gateway_id  = aws_dx_gateway.main.id
#   name           = "${local.name_prefix}-transit-vif"
#   vlan           = 4094
#   address_family = "ipv4"
#   bgp_asn        = 65000  # Your on-premises BGP ASN
# }

# =============================================================================
# RAM Resource Share for Cross-Account Transit Gateway
# =============================================================================

resource "aws_ram_resource_share" "tgw" {
  count = var.enable_transit_gateway && var.transit_gateway_id == "" ? 1 : 0

  name                      = "${local.name_prefix}-tgw-share"
  allow_external_principals = false

  tags = merge(local.common_tags, var.additional_tags, {
    Name = "${local.name_prefix}-tgw-share"
  })
}

resource "aws_ram_resource_association" "tgw" {
  count = var.enable_transit_gateway && var.transit_gateway_id == "" ? 1 : 0

  resource_arn       = aws_ec2_transit_gateway.main[0].arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

# To share with other accounts, add:
# resource "aws_ram_principal_association" "tgw" {
#   principal          = "123456789012"  # Account ID
#   resource_share_arn = aws_ram_resource_share.tgw[0].arn
# }
