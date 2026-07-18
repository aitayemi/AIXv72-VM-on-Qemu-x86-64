#!/bin/bash
# Boot AIX into maintenance mode from ISO (for fsck64 fix)

set -e

WIP_DIR="/wip"
DISK="$WIP_DIR/hdisk0.qcow2"
ISO="$WIP_DIR/AIX72ISOs/aix_7200-04-02-2027_1of2_072020.iso"

if [ ! -f "$ISO" ]; then
    echo "Error: AIX ISO not found at $ISO"
    exit 1
fi

if [ ! -f "$DISK" ]; then
    echo "Error: VM disk not found at $DISK"
    exit 1
fi

echo "Booting AIX into maintenance mode..."
echo "Menu selections: 1 > 1 > 3 > 1 > 0 > 1 > 1"
echo ""
echo "WARNING: No BACKSPACE key in maintenance mode!"
echo "Use CTRL+U to clear line. DO NOT use CTRL+C (terminates VM)!"
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
  -cdrom "$ISO" \
  -prom-env "boot-command=boot cdrom:"
