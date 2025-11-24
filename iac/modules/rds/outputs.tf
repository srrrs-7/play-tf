output "id" {
  description = "The RDS instance ID"
  value       = aws_db_instance.this.id
}

output "arn" {
  description = "The ARN of the RDS instance"
  value       = aws_db_instance.this.arn
}

output "address" {
  description = "The address of the RDS instance"
  value       = aws_db_instance.this.address
}

output "endpoint" {
  description = "The connection endpoint"
  value       = aws_db_instance.this.endpoint
}

output "port" {
  description = "The database port"
  value       = aws_db_instance.this.port
}

output "db_name" {
  description = "The database name"
  value       = aws_db_instance.this.db_name
}

output "username" {
  description = "The master username for the database"
  value       = aws_db_instance.this.username
}
