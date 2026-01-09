#!/usr/bin/env bash
# This is a work in progress. AIO build script that retains auth.
set -euo pipefail

# Configuration
APP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="localai-fedora-gfx113:latest"
BASE_IMAGE="fedora:42" 
LOCALAI_VERSION="v3.9.0"

# Directories
MODELS_DIR="${APP_DIR}/models"
BACKENDS_DIR="${APP_DIR}/backends"
mkdir -p "${MODELS_DIR}" "${BACKENDS_DIR}"

# 1. Create the Containerfile
cat > Containerfile.localai <<EOF
FROM ${BASE_IMAGE}

# Install Fedora Mesa and Vulkan stack
RUN dnf -y upgrade --refresh && \
    dnf -y install \
    ca-certificates curl jq tar gzip \
    mesa-vulkan-drivers vulkan-loader vulkan-tools \
    mesa-dri-drivers libdrm pciutils procps-ng findutils which \
    && dnf clean all

# Download LocalAI binary
RUN set -eux; \
    arch="\$(uname -m)"; \
    [ "\$arch" = "x86_64" ] && la_arch="amd64" || la_arch="arm64"; \
    url="https://github.com/mudler/LocalAI/releases/download/${LOCALAI_VERSION}/local-ai-${LOCALAI_VERSION}-linux-\${la_arch}"; \
    mkdir -p /opt/localai; \
    curl -fL "\$url" -o /opt/localai/local-ai; \
    chmod +x /opt/localai/local-ai

# Environment to force Vulkan detection for the BC-250
# Note: LOCALAI_P2P_TOKEN will be used if the variable TOKEN is set on the host
ENV MODELS_PATH=/models \
    LOCALAI_BACKENDS_PATH=/backends \
    XDG_RUNTIME_DIR=/tmp \
    VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/radeon_icd.x86_64.json \
    LOCALAI_FORCE_META_BACKEND_CAPABILITY=vulkan \
    LOCALAI_P2P=true

EXPOSE 8080
WORKDIR /opt/localai
ENTRYPOINT ["/opt/localai/local-ai"]
# Fixed: Binding to 0.0.0.0 allows access via LAN IP (192.168.x.x)
CMD ["run", "--address", "0.0.0.0:8080", "--p2p"]
EOF

# 2. Build the image
echo "[*] Building Fedora-based LocalAI image..."
podman build -t "${IMAGE_NAME}" -f Containerfile.localai .

# 3. Run the container
echo "[*] Starting container..."
# We pass the TOKEN variable from the host into the container if it exists
podman run --replace -d --name localai --net host \
  --device /dev/dri \
  --group-add keep-groups \
  -e DEBUG=true \
  -e LOCALAI_P2P_TOKEN="${TOKEN:-}" \
  -v "${MODELS_DIR}:/models:Z" \
  -v "${BACKENDS_DIR}:/backends:Z" \
  "${IMAGE_NAME}"

# 4. Backend and Library Patch logic
# Check if backend is missing OR if the broken 'lib' folder exists
if [ ! -d "${BACKENDS_DIR}/vulkan-llama-cpp" ] || [ -d "${BACKENDS_DIR}/vulkan-llama-cpp/lib" ]; then
    echo "[*] Installing/Patching Vulkan backend..."
    
    # Only trigger install if the folder is completely missing
    if [ ! -d "${BACKENDS_DIR}/vulkan-llama-cpp" ]; then
        echo "[*] Triggering backend download via API..."
        sleep 10
        curl -X POST http://localhost:8080/api/backends/install/vulkan-llama-cpp
        echo "[*] Waiting for extraction (this takes a minute)..."
        # Wait until the run script appears
        until [ -f "${BACKENDS_DIR}/vulkan-llama-cpp/run.sh" ]; do
            sleep 5
        done
    fi

    echo "[*] Applying critical library patch (Removing bundled GLIBC)..."
    podman exec -it localai rm -rf /backends/vulkan-llama-cpp/lib || true
    echo "[*] Restarting to apply changes..."
    podman restart localai
fi

# 5. Token Display Logic
if [ -z "${TOKEN:-}" ]; then
    echo "[*] No token provided. Acting as Cluster Master."
    echo "[*] Waiting for P2P initialization..."
    sleep 15
    echo "---------------------------------------------------------------"
    echo "BC-250 CLUSTER TOKEN (Paste this into Node 2 and 3):"
    # Improved extraction: Pulls the raw text directly from the API
    curl -s http://localhost:8080/api/p2p/token || echo "API not ready. Check: podman logs localai"
    echo -e "\n---------------------------------------------------------------"
else
    echo "[*] Token provided. Joining cluster..."
fi

echo "[*] Setup Complete. Monitoring logs (Ctrl+C to exit logs, container will keep running)..."
podman logs -f localai
