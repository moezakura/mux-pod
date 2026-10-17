#!/usr/bin/env bash
# Runs tests tagged `live-sshd` against a throwaway Docker sshd with fresh
# ed25519 host/client keys. Requires docker, ssh-keygen and ssh-keyscan.
set -euo pipefail

port="${REPRO_SSH_PORT:-2222}"
image=muxpod-live-sshd
name="muxpod-live-sshd-$$"
work="$(mktemp -d)"

# Always tear down the container and generated keys
cleanup() {
  docker rm -f "$name" >/dev/null 2>&1 || true
  rm -rf "$work"
}
trap cleanup EXIT

# Generate host key, authorized client key and an unauthorized client key
ssh-keygen -q -t ed25519 -N '' -C repro-host -f "$work/host_ed25519"
ssh-keygen -q -t ed25519 -N '' -C repro-client -f "$work/client"
ssh-keygen -q -t ed25519 -N '' -C repro-wrong -f "$work/client_wrong"

# Build a minimal sshd image with a key-only user `repro`
docker build -q -t "$image" - >/dev/null <<'EOF'
FROM debian:bookworm-slim
RUN apt-get update \
 && apt-get install -y --no-install-recommends openssh-server \
 && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* \
 && useradd -m -s /bin/bash repro && passwd -d repro && mkdir /run/sshd
CMD install -m 600 /fixture/host_ed25519 /etc/ssh/ssh_host_ed25519_key \
 && install -d -m 700 -o repro -g repro /home/repro/.ssh \
 && install -m 600 -o repro -g repro /fixture/client.pub /home/repro/.ssh/authorized_keys \
 && exec /usr/sbin/sshd -D -e -o HostKey=/etc/ssh/ssh_host_ed25519_key -o PasswordAuthentication=no
EOF

# Start sshd with the generated keys mounted read-only
docker run -d --name "$name" -p "127.0.0.1:$port:22" -v "$work:/fixture:ro" "$image" >/dev/null

# Wait until sshd serves the expected host key
for _ in $(seq 1 50); do
  ssh-keyscan -p "$port" -t ed25519 127.0.0.1 2>/dev/null | grep -q ssh-ed25519 && break
  sleep 0.2
done
ssh-keyscan -p "$port" -t ed25519 127.0.0.1 2>/dev/null | grep -q ssh-ed25519 || {
  docker logs "$name" >&2
  echo "sshd did not become ready on port $port" >&2
  exit 1
}

# Run the live tests against the fixture
REPRO_SSH_HOST=127.0.0.1 \
REPRO_SSH_PORT="$port" \
REPRO_SSH_USER=repro \
REPRO_SSH_HOST_KEY_PUB="$work/host_ed25519.pub" \
REPRO_SSH_KEY="$work/client" \
REPRO_SSH_WRONG_KEY="$work/client_wrong" \
  flutter test --tags live-sshd "$@"
