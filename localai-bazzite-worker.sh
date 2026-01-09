#!/usr/bin/env bash
set -euo pipefail

# 1. Configuration
IMAGE_NAME="localai-fedora-worker:latest"
BASE_IMAGE="fedora:42" 
LOCALAI_VERSION="v3.9.0"

# --- THE STATIC TOKEN ---
RAW_TOKEN=$(cat <<EOF
b3RwOgogIGRodDoKICAgIGludGVydmFsOiAzNjAKICAgIGtleTogWEp4VGRjWmhadk94eG5Sb3UwNU42OHlsS1Q5UE5mTDdsYTJEZHI1QlhVUgogICAgbGVuZ3RoOiA0MwogIGNyeXB0bzoKICAgIGludGVydmFsOiA5MDAwCiAgICBrZXk6IHpwOUdtbmZ3UERhTVZvZUxrQmNYQ1ZQSnVWMzVLdlV6aGhYemhub2lFdU8KICAgIGxlbmd0aDogNDMKcm9vbTogRDBZNkNscWtqRFZqNjdVNXNXc3BmQU9BcENpUkUzQlJnZFJVS0xoRTJwTwpyZW5kZXp2b3VzOiBZOUxzZzBGV3BWcjVZSFRSaFgxeGxaSTVYcGxoUnVxWkpJaDM0M0lLazJCCm1kbnM6IHdqa2Y4aGhQdjlLRlpBQ1RsUDFNaTdVdEppd3BjVUNaOTg0bzdZaXluTWYKbWF4X21lc3NhZ2Vfc2l6ZTogMjA5NzE1MjAK
EOF
)
STATIC_TOKEN=$(echo "$RAW_TOKEN" | tr -d '\n ')

APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKENDS_DIR="${APP_DIR}/backends"
mkdir -p "${BACKENDS_DIR}"

# 2. Create the Containerfile
cat > Containerfile.worker <<EOF
FROM ${BASE_IMAGE}
RUN dnf -y upgrade --refresh && \
    dnf -y install ca-certificates curl jq tar gzip mesa-vulkan-drivers \
    vulkan-loader vulkan-tools mesa-dri-drivers libdrm pciutils procps-ng findutils which \
    && dnf clean all

RUN set -eux; \
    arch="\$(uname -m)"; \
    [ "\$arch" = "x86_64" ] && la_arch="amd64" || la_arch="arm64"; \
    url="https://github.com/mudler/LocalAI/releases/download/${LOCALAI_VERSION}/local-ai-${LOCALAI_VERSION}-linux-\${la_arch}"; \
    mkdir -p /opt/localai; \
    curl -fL "\$url" -o /opt/localai/local-ai; \
    chmod +x /opt/localai/local-ai

RUN mkdir -p /backends

# FORCING RPC TO BIND TO ALL INTERFACES VIA ENV VARS
ENV LOCALAI_BACKENDS_PATH=/backends \
    XDG_RUNTIME_DIR=/tmp \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json \
    LOCALAI_FORCE_META_BACKEND_CAPABILITY=vulkan \
    LOCALAI_P2P=true \
    LOCALAI_RUNNER_ADDRESS=0.0.0.0 \
    LOCALAI_RUNNER_PORT=12345

WORKDIR /opt/localai

RUN printf '#!/bin/bash\n\
if [ -d "/backends/vulkan-llama-cpp/lib" ]; then\n\
    rm -rf /backends/vulkan-llama-cpp/lib\n\
fi\n\
exec /opt/localai/local-ai "\$@"\n' > /entrypoint.sh && chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
EOF

# 3. Build and Run
echo "[*] Building worker image..."
podman build -t "${IMAGE_NAME}" -f Containerfile.worker .

echo "[*] Launching P2P Worker..."
podman run --replace -d --name localai-worker --net host \
  --device /dev/dri \
  --group-add keep-groups \
  --security-opt label=disable \
  -v "${BACKENDS_DIR}:/backends:Z" \
  -e LOCALAI_P2P_TOKEN="${STATIC_TOKEN}" \
  "${IMAGE_NAME}" worker p2p-llama-cpp-rpc
