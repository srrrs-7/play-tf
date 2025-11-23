output "vpc_id" {
  description = "VPCのID"
  value       = aws_vpc.main.id
}

output "vpc_cidr" {
  description = "VPCのCIDRブロック"
  value       = aws_vpc.main.cidr_block
}

output "public_subnet_ids" {
  description = "パブリックサブネットのIDリスト"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "プライベートサブネットのIDリスト"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "データベースサブネットのIDリスト"
  value       = aws_subnet.database[*].id
}

output "database_subnet_group_name" {
  description = "データベースサブネットグループ名"
  value       = length(aws_db_subnet_group.database) > 0 ? aws_db_subnet_group.database[0].name : null
}

output "nat_gateway_ids" {
  description = "NAT GatewayのIDリスト"
  value       = aws_nat_gateway.main[*].id
}

output "internet_gateway_id" {
  description = "Internet GatewayのID"
  value       = length(aws_internet_gateway.main) > 0 ? aws_internet_gateway.main[0].id : null
}

output "public_route_table_id" {
  description = "パブリックルートテーブルのID"
  value       = length(aws_route_table.public) > 0 ? aws_route_table.public[0].id : null
}

output "private_route_table_ids" {
  description = "プライベートルートテーブルのIDリスト"
  value       = aws_route_table.private[*].id
}

output "database_route_table_id" {
  description = "データベースルートテーブルのID"
  value       = length(aws_route_table.database) > 0 ? aws_route_table.database[0].id : null
}
