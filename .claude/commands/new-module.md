---
name: new-module
description: Create a new Terraform module from template
disable-model-invocation: true
allowed-tools: Bash, Read, Write, Glob
argument-hint: "<module-name>"
---

Create a new Terraform module from the template.

Module name: $ARGUMENTS

Steps:
1. Copy `iac/modules/__template__/` to `iac/modules/$ARGUMENTS/`
2. Update main.tf with placeholder AWS resources for the service
3. Define appropriate variables in variables.tf
4. Define useful outputs in outputs.tf
5. Add README.md with usage instructions

Follow project conventions:
- Use Japanese comments for resource descriptions
- Use `this` for primary resource naming
- Accept `tags` variable of type `map(string)`
- Use conditional resources with `count`
- Use `dynamic` blocks for repeatable configurations
- Block public access and enable encryption by default

Example usage:
- `/new-module cognito` - Create Cognito module
- `/new-module waf` - Create WAF module
