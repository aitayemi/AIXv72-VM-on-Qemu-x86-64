#!/bin/bash
# Start AIX VM with serial console access

set -e

WIP_DIR="/wip"
DISK="$WIP_DIR/hdisk0.qcow2"
ISO_DIR="$WIP_DIR/AIX72ISOs"
MAC="be:16:43:37:16:ec"

if [ ! -f "$DISK" ]; then
    echo "Error: VM disk not found at $DISK"
    exit 1
fi

echo "Starting AIX 7.2 VM with console access..."
echo "To exit: use ~~. (tilde-tilde-dot) or close terminal"
echo ""

cd "$WIP_DIR"

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -serial stdio \
  -drive file="$DISK",if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -prom-env "boot-command=boot disk:" \
  -net nic,macaddr="$MAC" \
  -net tap,script=no,ifname=tap0,downscript=no
