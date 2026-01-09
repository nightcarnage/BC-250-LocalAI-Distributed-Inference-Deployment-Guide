#!/bin/bash

# Configuration & Paths
STATE_FILE="$HOME/.install_stage"
REPO_URL="https://github.com/bazzite-org/kernel-bazzite/releases/download/6.17.7-ba22"
KERNEL_VER="6.17.7-ba22.fc43.x86_64"

# Function for logging
log() { echo -e "\e[32m[LOG]\e[0m $1"; }

# Check for root
if [[ $EUID -ne 0 ]]; then
   echo "Please run as root/sudo"
   exit 1
fi

# Determine current stage
STAGE=$(cat "$STATE_FILE" 2>/dev/null || echo "1")

# --- PHASE 1: KERNEL & GRUB ---
if [ "$STAGE" == "1" ]; then
    log "Starting Phase 1: Kernel & GRUB configuration..."

    mkdir -p ~/bazzite-kernel-update && cd ~/bazzite-kernel-update
    
    # Download Kernel Components
    files=("kernel" "kernel-core" "kernel-modules" "kernel-modules-core" "kernel-modules-extra")
    for file in "${files[@]}"; do
        wget "${REPO_URL}/${file}-${KERNEL_VER}.rpm"
    done

    dnf install -y ./*.rpm
    
    # Patch GRUB (Using sed for safety)
    sed -i 's/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="rd.lvm.lv=fedora\/root rhgb quiet mitigations=off"/' /etc/default/grub
    grub2-mkconfig -o /boot/grub2/grub.cfg

    # Lock Kernel & Clean Up
    dnf install -y 'dnf-command(versionlock)'
    dnf versionlock add kernel*${KERNEL_VER}*
    
    # Set Default Kernel
    grubby --set-default=/boot/vmlinuz-${KERNEL_VER}
    
    # Network Tuning
    echo "net.core.rmem_max=7500000" | tee /etc/sysctl.d/10-localai-p2p.conf
    echo "net.core.wmem_max=7500000" | tee /etc/sysctl.d/10-localai-p2p.conf
    sysctl --system

    log "Phase 1 Complete. System will reboot in 10 seconds. Rerun this script after login."
    echo "2" > "$STATE_FILE"
    sleep 10
    reboot
fi

# --- PHASE 2: DRIVERS & LOCALAI ---
if [ "$STAGE" == "2" ]; then
    log "Starting Phase 2: Hardware Support & Containers..."

    # XFS Resize
    lvextend -l +100%FREE /dev/mapper/fedora-root || log "Volume already extended"
    xfs_growfs /
    
    # Governor & Sensors
    dnf copr enable -y filippor/bazzite
    dnf install -y cyan-skillfish-governor-tt git cmake make gcc-c++ libdrm-devel lm_sensors vulkan-tools mesa-vulkan-drivers nvtop glxinfo
    
    systemctl enable --now cyan-skillfish-governor-tt
    
    # Sensor Module Config
    echo 'nct6683' | tee /etc/modules-load.d/99-sensors.conf
    echo 'options nct6683 force=true' | tee /etc/modprobe.d/options-sensors.conf
    dracut --regenerate-all --force

    # LocalAI Prep
    mkdir -p ~/localai && cd ~/localai
    log "Phase 2 Complete. Please upload your 'localai.sh' to ~/localai now."
    
    echo "FINISH" > "$STATE_FILE"
fi