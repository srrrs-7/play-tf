# Lambda container image for Node.js runtime
# Uses AWS Lambda base image for Node.js 20
FROM public.ecr.aws/lambda/nodejs:20

# Set working directory
WORKDIR ${LAMBDA_TASK_ROOT}

# Copy package files first for better layer caching
COPY package*.json ./

# Install production dependencies only
RUN npm ci --only=production 2>/dev/null || npm install --only=production

# Copy TypeScript config and source
COPY tsconfig.json ./
COPY *.ts ./

# Install dev dependencies, build, then remove dev dependencies
RUN npm install && \
    npm run build && \
    npm prune --production && \
    rm -rf *.ts tsconfig.json

# Set the handler
CMD ["dist/index.handler"]
