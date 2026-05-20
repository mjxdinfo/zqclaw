#!/usr/bin/env bash
# ============================================================
#  Enable SSH server on Ubuntu Live USB
#  Usage: sudo bash enable-ssh.sh
# ============================================================
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Usage: sudo bash enable-ssh.sh"
    exit 1
fi

echo "Installing OpenSSH server..."
apt-get update -qq
apt-get install -y -qq openssh-server

systemctl enable ssh
systemctl start ssh

REAL_USER="${SUDO_USER:-$USER}"
echo ""
echo "Set a password for SSH login (user: $REAL_USER):"
passwd "$REAL_USER"

LOCAL_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)(?!127\.)\d+\.\d+\.\d+\.\d+' | head -1)
echo ""
echo "========================================"
echo "  SSH Ready!"
echo "  From Mac mini or other computer:"
echo "  ssh ${REAL_USER}@${LOCAL_IP}"
echo "========================================"
