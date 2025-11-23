FROM mcr.microsoft.com/devcontainers/base:2-trixie

# Install dependencies required for Bun and uv
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    make \
    && rm -rf /var/lib/apt/lists/*

# Install Bun as vscode user
USER vscode

WORKDIR /workspace/main

# Install claude code
RUN curl -fsSL https://claude.ai/install.sh | bash

# Install uv
RUN curl -LsSf https://astral.sh/uv/install.sh | sh

# Install Python 3.12 using uv
RUN /home/vscode/.local/bin/uv python install 3.12
