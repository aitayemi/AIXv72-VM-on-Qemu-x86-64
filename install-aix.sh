#!/bin/bash
# Install AIX 7.2 from ISO (first-time setup)

set -e

WIP_DIR="/wip"
DISK="$WIP_DIR/hdisk0.qcow2"
ISO="$WIP_DIR/AIX72ISOs/aix_7200-04-02-2027_1of2_072020.iso"

if [ ! -f "$ISO" ]; then
    echo "Error: AIX ISO not found at $ISO"
    echo "Please copy the AIX installation ISO to $WIP_DIR/AIX72ISOs/"
    exit 1
fi

# Create disk if it doesn't exist
if [ ! -f "$DISK" ]; then
    echo "Creating VM disk..."
    qemu-img create -f qcow2 "$DISK" 20G
fi

echo "Starting AIX 7.2 installation..."
echo "This will take approximately 110 minutes."
echo "The VM will reboot-loop at the end - this is expected."
echo "Press CTRL+C when you see the reboot loop to exit."
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
