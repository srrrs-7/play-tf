FROM mcr.microsoft.com/devcontainers/base:2-trixie

# Codex CLIのインストール（コンテナのアーキテクチャに合わせる）
RUN set -euo pipefail \
    && ARCH="$(uname -m)" \
    && case "${ARCH}" in \
        x86_64|amd64) CODEX_TARGET="x86_64-unknown-linux-musl" ;; \
        aarch64|arm64) CODEX_TARGET="aarch64-unknown-linux-musl" ;; \
        *) echo "Unsupported architecture: ${ARCH}" >&2; exit 1 ;; \
    esac \
    && curl -L -o /tmp/codex.tar.gz "https://github.com/openai/codex/releases/latest/download/codex-${CODEX_TARGET}.tar.gz" \
    && tar -xzf /tmp/codex.tar.gz -C /tmp \
    && chmod +x "/tmp/codex-${CODEX_TARGET}" \
    && mv "/tmp/codex-${CODEX_TARGET}" /usr/local/bin/codex \
    && rm /tmp/codex.tar.gz

# Install dependencies required for Bun and uv
RUN apt-get update && apt-get install -y \
    curl \
    unzip \
    make \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI
ARG DOCKER_VERSION=24.0.7
RUN apt-get update \
    && apt-get install -y curl \
    && curl -fsSL "https://download.docker.com/linux/static/stable/$(uname -m)/docker-${DOCKER_VERSION}.tgz" | tar xz --strip-components=1 -C /usr/local/bin docker/docker \
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
