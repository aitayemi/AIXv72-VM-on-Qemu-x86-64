#!/bin/bash
# Start AIX VM in headless mode (background) with VNC access

set -e

WIP_DIR="/wip"
DISK="$WIP_DIR/hdisk0.qcow2"
MAC="be:16:43:37:16:ec"

if [ ! -f "$DISK" ]; then
    echo "Error: VM disk not found at $DISK"
    exit 1
fi

echo "Starting AIX 7.2 VM in headless mode..."
echo "VNC server will be available on 127.0.0.1:5900"
echo "Connect with: vncviewer localhost:5900"
echo ""

cd "$WIP_DIR"

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -drive file="$DISK",if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -prom-env "boot-command=boot disk:" \
  -net nic,macaddr="$MAC" \
  -net tap,script=no,ifname=tap0,downscript=no \
  -daemonize

echo "VM started in background."
echo "Check status: ps aux | grep qemu"
echo "Stop VM: kill $(pgrep qemu-system-ppc64)"
