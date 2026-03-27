FROM myoung34/github-runner:latest

# Patch Docker init script to remove ulimit call (Railway doesn't allow it)
RUN sed -i 's/ulimit -n [0-9]*/true/' /etc/init.d/docker 2>/dev/null || true

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
      cmake build-essential pkg-config libssl-dev \
      musl-tools \
    && rm -rf /var/lib/apt/lists/*

# Install Rust stable with all components
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y \
      --default-toolchain stable \
    && rustup component add rustfmt clippy \
    && rustup target add x86_64-unknown-linux-musl \
    && cargo install cargo-deny --locked \
    && rm -rf /usr/local/cargo/registry/cache \
    && rustc --version && cargo --version && cargo deny --version

# Install buildx plugin
RUN mkdir -p /usr/local/lib/docker/cli-plugins \
    && curl -fsSL "https://github.com/docker/buildx/releases/download/v0.19.3/buildx-v0.19.3.linux-amd64" \
       -o /usr/local/lib/docker/cli-plugins/docker-buildx \
    && chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# Configure private crate registry (token injected at runtime via env vars)
COPY cargo-config.toml /usr/local/cargo/config.toml
