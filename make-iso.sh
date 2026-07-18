#!/bin/bash
# Create an ISO image from a directory of RPM files
# Usage: ./make-iso.sh <source-dir> <output-iso-name>

set -e

if [ $# -lt 2 ]; then
    echo "Usage: $0 <source-directory> <output-iso-name>"
    echo "Example: $0 ./bash50 bash50.iso"
    exit 1
fi

SOURCE_DIR="$1"
OUTPUT_ISO="$2"

if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory '$SOURCE_DIR' not found"
    exit 1
fi

# Install genisoimage if not present
if ! command -v mkisofs &>/dev/null; then
    echo "Installing genisoimage..."
    sudo apt install -y genisoimage
fi

echo "Creating ISO from $SOURCE_DIR..."
mkisofs -max-iso9660-filenames -o "$OUTPUT_ISO" "$SOURCE_DIR"

echo "ISO created: $OUTPUT_ISO"
echo "Mount in QEMU with: -cdrom $OUTPUT_ISO"
