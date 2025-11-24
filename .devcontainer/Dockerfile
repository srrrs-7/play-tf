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

# install Bun
ENV BUN_INSTALL="/home/vscode/.bun"
ENV PATH="${BUN_INSTALL}/bin:${PATH}"
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v1.3.3"
