output "id" {
  description = "The ID of the ECR repository"
  value       = aws_ecr_repository.this.id
}

output "arn" {
  description = "The ARN of the ECR repository"
  value       = aws_ecr_repository.this.arn
}

output "name" {
  description = "The name of the ECR repository"
  value       = aws_ecr_repository.this.name
}

output "repository_url" {
  description = "The URL of the ECR repository"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "The ARN of the ECR repository (deprecated, use 'arn' instead)"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "The name of the ECR repository (deprecated, use 'name' instead)"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "Registry ID"
  value       = aws_ecr_repository.this.registry_id
}
