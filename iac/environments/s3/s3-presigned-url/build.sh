#!/bin/bash

set -e

# Color codes for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building S3 Presigned URL Lambda function...${NC}"

# Install dependencies
echo -e "${YELLOW}Installing dependencies...${NC}"
npm install

# Build TypeScript
echo -e "${YELLOW}Compiling TypeScript...${NC}"
npm run build

echo -e "${GREEN}Build completed successfully!${NC}"
echo -e "${GREEN}Compiled files are in: dist/${NC}"
