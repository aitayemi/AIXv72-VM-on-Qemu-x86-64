#!/bin/bash
# AIX VM Bridge Setup Script
# Run this on the Ubuntu host to configure networking for the AIX VM

set -e

PRIMARY_IF="eth0"
AIX_IP="10.0.2.16"
BRIDGE_IP="10.0.2.20"

# Detect primary interface if eth0 doesn't exist
if ! ip link show "$PRIMARY_IF" &>/dev/null; then
    PRIMARY_IF=$(ip route | grep default | awk '{print $5}' | head -n1)
    echo "Detected primary interface: $PRIMARY_IF"
fi

echo "Setting up bridge for AIX VM..."

# Allow QEMU to use bridge
sudo mkdir -p /usr/local/etc/qemu
if [ ! -f /usr/local/etc/qemu/bridge.conf ]; then
    echo "allow br0" | sudo tee /usr/local/etc/qemu/bridge.conf
fi

# Create bridge if not exists
if ! ip link show br0 &>/dev/null; then
    sudo ip link add name br0 type bridge
fi
sudo ip link set dev br0 up

# Create TAP interface if not exists
if ! ip link show tap0 &>/dev/null; then
    sudo ip tuntap add tap0 mode tap
fi
sudo ip link set dev tap0 up
sudo ip link set dev tap0 master br0

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo 1 | sudo tee /proc/sys/net/ipv4/conf/tap0/proxy_arp

# Add route for AIX VM
sudo ip route add "$AIX_IP" dev br0 2>/dev/null || true
sudo arp -Ds "$AIX_IP" "$PRIMARY_IF" pub 2>/dev/null || true

# Configure NAT
sudo iptables -t nat -C POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE 2>/dev/null || \
    sudo iptables -t nat -A POSTROUTING -o "$PRIMARY_IF" -j MASQUERADE

sudo iptables -C FORWARD -i tap0 -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD 1 -i tap0 -j ACCEPT

sudo iptables -C FORWARD -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    sudo iptables -I FORWARD 1 -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "Bridge setup complete!"
echo "Bridge: br0"
echo "TAP: tap0"
echo "AIX IP: $AIX_IP"
echo "Gateway: $BRIDGE_IP"
