#!/usr/bin/env bash
# Provisions a bare-metal Ubuntu/Debian host to run the shroudb self-hosted
# GitHub Actions runner. Installs everything needed for Rust CI + release:
# build toolchain, Docker engine (if absent), buildx plugin, QEMU binfmt,
# Rust stable with clippy/rustfmt/musl target, cargo-deny, runner PATH,
# and the runner as a systemd service. Verifies the install end-to-end.
# Idempotent — safe to re-run.
#
# Run as the user that owns the runner (not root).
# Assumes the runner tarball has been unpacked and ./config.sh has registered
# the runner. If not, the service install step is skipped with a note.
#
# Env overrides:
#   RUNNER_DIR      — path to actions-runner install  (default: ~/actions-runner)
#   RUST_TOOLCHAIN  — rust toolchain to pin           (default: stable)
#   BUILDX_VERSION  — docker buildx plugin version    (default: v0.19.3)

set -euo pipefail

RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner}"
RUST_TOOLCHAIN="${RUST_TOOLCHAIN:-stable}"
BUILDX_VERSION="${BUILDX_VERSION:-v0.19.3}"

if [ "$EUID" -eq 0 ]; then
  echo "error: run as the runner user, not root" >&2
  exit 1
fi

echo "==> Priming sudo"
sudo -v

# ── System packages ────────────────────────────────────────────────
echo "==> Installing system packages"
sudo apt-get update
sudo apt-get install -y --no-install-recommends \
  build-essential cmake pkg-config libssl-dev musl-tools \
  git curl tar jq ca-certificates

# ── Docker engine ──────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  echo "==> Installing docker.io (Ubuntu's Docker packaging)"
  sudo apt-get install -y docker.io
else
  echo "==> Docker present: $(docker --version)"
fi

docker_group_added=0
if ! id -nG "$USER" | tr ' ' '\n' | grep -qx docker; then
  echo "==> Adding $USER to docker group"
  sudo usermod -aG docker "$USER"
  docker_group_added=1
fi

# ── Docker buildx plugin ───────────────────────────────────────────
# Install system-wide to /usr/libexec/docker/cli-plugins. This dir is
# honored by both docker.io and Docker CE, so the plugin works regardless
# of how the engine was installed. The apt docker-buildx-plugin package
# only exists in the Docker CE repo, so we fetch the release binary
# directly — matches .github/runner/Dockerfile's approach.
arch=$(dpkg --print-architecture)
case "$arch" in
  amd64) buildx_arch="linux-amd64" ;;
  arm64) buildx_arch="linux-arm64" ;;
  armhf) buildx_arch="linux-arm-v7" ;;
  *) echo "error: unsupported arch '$arch' for buildx" >&2; exit 1 ;;
esac

if docker buildx version 2>/dev/null | grep -qF "$BUILDX_VERSION"; then
  echo "==> Buildx $BUILDX_VERSION already installed"
else
  echo "==> Installing docker buildx plugin $BUILDX_VERSION"
  sudo mkdir -p /usr/libexec/docker/cli-plugins
  sudo curl -fsSL \
    "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.${buildx_arch}" \
    -o /usr/libexec/docker/cli-plugins/docker-buildx
  sudo chmod +x /usr/libexec/docker/cli-plugins/docker-buildx
fi

# ── QEMU binfmt (linux/arm64 emulation for buildx + cross) ─────────
echo "==> Registering QEMU binfmt handlers"
sudo docker run --privileged --rm tonistiigi/binfmt --install all >/dev/null

# ── Rust ───────────────────────────────────────────────────────────
if ! command -v rustup >/dev/null 2>&1; then
  echo "==> Installing rustup"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --default-toolchain "$RUST_TOOLCHAIN" --profile minimal
fi
# shellcheck disable=SC1091
. "$HOME/.cargo/env"

echo "==> Ensuring toolchain + components + musl target"
rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal
rustup component add rustfmt clippy --toolchain "$RUST_TOOLCHAIN"
rustup target add x86_64-unknown-linux-musl --toolchain "$RUST_TOOLCHAIN"

if ! command -v cargo-deny >/dev/null 2>&1; then
  echo "==> Installing cargo-deny"
  cargo install cargo-deny --locked
fi

# ── Runner PATH ────────────────────────────────────────────────────
# systemd services do not source ~/.bashrc. The runner sources
# $RUNNER_DIR/.env for extra env vars — put cargo on PATH via that file.
if [ -d "$RUNNER_DIR" ]; then
  runner_env="$RUNNER_DIR/.env"
  desired_path="$HOME/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  if ! grep -qxF "PATH=$desired_path" "$runner_env" 2>/dev/null; then
    echo "==> Writing PATH to $runner_env"
    tmp=$(mktemp)
    { [ -f "$runner_env" ] && grep -v '^PATH=' "$runner_env" || true; } > "$tmp"
    echo "PATH=$desired_path" >> "$tmp"
    mv "$tmp" "$runner_env"
  fi
fi

# ── Runner systemd service ─────────────────────────────────────────
shopt -s nullglob
existing_units=( /etc/systemd/system/actions.runner.*.service )
shopt -u nullglob

service_managed=0
if [ ! -d "$RUNNER_DIR" ]; then
  echo "note: $RUNNER_DIR does not exist — skipping service install"
elif [ ! -f "$RUNNER_DIR/.runner" ]; then
  echo "note: $RUNNER_DIR/.runner missing — register with ./config.sh then re-run"
elif [ "${#existing_units[@]}" -gt 0 ]; then
  echo "==> Runner service already installed (${existing_units[0]##*/}) — restarting to pick up env"
  pushd "$RUNNER_DIR" >/dev/null
  sudo ./svc.sh stop || true
  sudo ./svc.sh start
  popd >/dev/null
  service_managed=1
else
  echo "==> Installing runner as systemd service"
  pushd "$RUNNER_DIR" >/dev/null
  sudo ./svc.sh install "$USER"
  sudo ./svc.sh start
  popd >/dev/null
  service_managed=1
fi

# ── Verification ───────────────────────────────────────────────────
echo
echo "==> Verifying install"

fail=0
check() {
  local name="$1" cmd="$2"
  if eval "$cmd" >/dev/null 2>&1; then
    printf '  \u2713 %s\n' "$name"
  else
    printf '  \u2717 %s — FAILED: %s\n' "$name" "$cmd" >&2
    fail=1
  fi
}

check "cargo"                 "cargo --version"
check "cargo-deny"            "cargo-deny --version"
check "rustfmt"               "cargo fmt --version"
check "clippy"                "cargo clippy --version"
check "musl target installed" "rustup target list --installed | grep -qx x86_64-unknown-linux-musl"
check "docker CLI"            "docker --version"
check "docker buildx plugin"  "docker buildx version"
check "docker daemon (as $USER)" "sudo -u '$USER' docker ps"
check "buildx builder listing" "sudo -u '$USER' docker buildx ls"
check "arm64 emulation"       "sudo docker run --rm --platform linux/arm64 alpine true"

if [ "$service_managed" -eq 1 ]; then
  check "runner service active" "systemctl is-active --quiet 'actions.runner.*'"
fi

echo

if [ "$fail" -ne 0 ]; then
  echo "Setup incomplete — see failed checks above." >&2
  exit 1
fi

echo "All checks passed. Runner is ready."
if [ "$docker_group_added" -eq 1 ]; then
  echo
  echo "Note: your interactive shell still has the pre-usermod group set."
  echo "Run 'newgrp docker' or reopen the session to use 'docker' without"
  echo "sudo. The runner service was restarted and already has the group."
fi
