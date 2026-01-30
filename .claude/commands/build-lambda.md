---
name: build-lambda
description: Build a TypeScript Lambda function
disable-model-invocation: true
allowed-tools: Bash, Read, Glob
argument-hint: "<path-to-lambda-dir>"
---

Build a TypeScript Lambda function.

Lambda directory: $ARGUMENTS

Steps:
1. Navigate to the Lambda function directory
2. Check for package.json and tsconfig.json
3. Run `npm install` if node_modules doesn't exist
4. Run `npm run build` to compile TypeScript
5. Verify dist/ directory was created
6. Report build status and output files

If no path specified, search for Lambda directories in:
- `iac/environments/*/`
- `cli/*/src/`

And list available Lambda functions to build.

Example usage:
- `/build-lambda iac/environments/api/api-handler`
- `/build-lambda iac/environments/s3/s3-presigned-url`
