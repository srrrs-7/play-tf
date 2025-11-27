output "id" {
  description = "The unique ID of the Amplify app"
  value       = aws_amplify_app.this.id
}

output "arn" {
  description = "The ARN of the Amplify app"
  value       = aws_amplify_app.this.arn
}

output "name" {
  description = "The name of the Amplify app"
  value       = aws_amplify_app.this.name
}

output "default_domain" {
  description = "The default domain for the Amplify app"
  value       = aws_amplify_app.this.default_domain
}

output "production_branch" {
  description = "The production branch for the Amplify app"
  value       = aws_amplify_app.this.production_branch
}

output "branch_names" {
  description = "List of branch names"
  value       = [for branch in aws_amplify_branch.this : branch.branch_name]
}

output "branch_arns" {
  description = "Map of branch names to ARNs"
  value       = { for k, v in aws_amplify_branch.this : v.branch_name => v.arn }
}

output "branch_urls" {
  description = "Map of branch names to their display URLs"
  value = {
    for k, v in aws_amplify_branch.this : v.branch_name =>
    "https://${v.branch_name}.${aws_amplify_app.this.default_domain}"
  }
}

output "domain_association_arns" {
  description = "Map of domain names to ARNs"
  value       = { for k, v in aws_amplify_domain_association.this : v.domain_name => v.arn }
}

output "domain_association_certificate_verification_dns_records" {
  description = "Map of domain names to DNS records for certificate verification"
  value       = { for k, v in aws_amplify_domain_association.this : v.domain_name => v.certificate_verification_dns_record }
}

output "webhook_urls" {
  description = "Map of branch names to webhook URLs"
  value       = { for k, v in aws_amplify_webhook.this : v.branch_name => v.url }
}

output "webhook_arns" {
  description = "Map of branch names to webhook ARNs"
  value       = { for k, v in aws_amplify_webhook.this : v.branch_name => v.arn }
}

output "backend_environment_arns" {
  description = "Map of environment names to ARNs"
  value       = { for k, v in aws_amplify_backend_environment.this : v.environment_name => v.arn }
}
