variable "vpc_name" {
  description = "VPC名"
  type        = string
}

variable "vpc_cidr" {
  description = "VPCのCIDRブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "azs" {
  description = "使用するAvailability Zones"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "パブリックサブネットのCIDRブロック"
  type        = list(string)
  default     = []
}

variable "private_subnet_cidrs" {
  description = "プライベートサブネットのCIDRブロック"
  type        = list(string)
  default     = []
}

variable "database_subnet_cidrs" {
  description = "データベースサブネットのCIDRブロック"
  type        = list(string)
  default     = []
}

variable "enable_nat_gateway" {
  description = "NAT Gatewayを作成するか"
  type        = bool
  default     = true
}

variable "single_nat_gateway" {
  description = "単一のNAT Gatewayを使用するか(コスト削減)"
  type        = bool
  default     = false
}

variable "enable_dns_hostnames" {
  description = "DNS hostnamesを有効化するか"
  type        = bool
  default     = true
}

variable "enable_dns_support" {
  description = "DNS supportを有効化するか"
  type        = bool
  default     = true
}

variable "enable_vpn_gateway" {
  description = "VPN Gatewayを作成するか"
  type        = bool
  default     = false
}

variable "tags" {
  description = "リソースに付与する共通タグ"
  type        = map(string)
  default     = {}
}
