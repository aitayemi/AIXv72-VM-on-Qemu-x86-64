# QEMU AIX 7.2 on Ubuntu (x86_64)

> Run IBM AIX 7.2 on x86_64 hardware using QEMU's PowerPC (ppc64) full-system emulation. Tested on AWS EC2 t3.xlarge running Ubuntu 22.04 LTS.

![Architecture Diagram](/architecture_diagram.png)

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [AIX Installation](#aix-installation)
- [Post-Installation Fixes](#post-installation-fixes)
- [Networking Setup](#networking-setup)
- [Bash Installation](#bash-installation)
- [Usage](#usage)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Overview

This project provides a complete, reproducible workflow for running **IBM AIX 7.2** on commodity x86_64 hardware using **QEMU's PowerPC (ppc64) full-system emulation**. Unlike containerized or paravirtualized solutions, this approach emulates the entire POWER8 architecture — enabling genuine AIX execution without physical IBM Power hardware.

The primary use cases include:

- **AIX learning and certification prep** without access to POWER servers
- **Legacy application testing** in environments where AIX is required
- **Cross-platform development** and build verification for AIX targets
- **Disaster recovery testing** of AIX workloads on available x86_64 infrastructure

### Why QEMU for AIX?

| Challenge | QEMU Solution |
|-----------|--------------|
| No POWER hardware available | Full-system POWER8 emulation (`pseries` machine type) |
| AIX requires ppc64 architecture | QEMU `qemu-system-ppc64` with KVM-independent emulation |
| Need isolated AIX environments | Per-VM disk images with qcow2 snapshots |
| Cost-sensitive deployments | Open-source alternative to IBM PowerVM or cloud POWER instances |

### Key Specifications

| Component | Details |
|-----------|---------|
| **Host OS** | Ubuntu 22.04 LTS (Jammy Jellyfish) |
| **Host Platform** | AWS EC2 t3.xlarge (x86_64) — or any x86_64 Linux host |
| **QEMU Version** | 7.2.0 (compiled from source with `--target-list=ppc64-softmmu`) |
| **Guest OS** | AIX 7.2 TL4 SP2 (7200-04-02-2027) |
| **Emulated CPU** | POWER8 |
| **Guest Memory** | 4GB |
| **Guest Disk** | 20GB qcow2 via virtio-scsi |
| **Guest Network** | TAP + Linux bridge (br0) with host NAT |
| **Access Methods** | Serial console, SSH, or VNC |

> **Note:** This is a full-system emulator, not a compatibility layer or container. Performance is significantly slower than native POWER hardware. This setup is intended for **development, testing, and educational use** — not production workloads.

---

## Architecture

```
+------------------------------------------------------------------+
|                        AWS Cloud                                 |
|  EC2 t3.xlarge | Ubuntu 22.04 LTS | x86_64                      |
|  Primary: 8GB EBS | Secondary: 55GB EBS (/wip)                  |
+------------------------------------------------------------------+
                              |
+-----------------------------+------------------------------------+
|                    Ubuntu 22.04 Host                             |
|                                                                  |
|  +------------------+    +------------------+                  |
|  | QEMU 7.2.0       |    | Network Bridge   |                  |
|  | (compiled)       |    | br0 + tap0       |                  |
|  | qemu-system-ppc64|    | IP Forward + NAT |                  |
|  +--------+---------+    +--------+---------+                  |
|           |                       |                            |
|  +--------+---------+    +--------+---------+                  |
|  | Storage          |    | iptables         |                  |
|  | hdisk0.qcow2     |    | MASQUERADE       |                  |
|  | AIX72 ISOs       |    | Proxy ARP        |                  |
|  +------------------+    +------------------+                  |
|                                                                  |
+-----------------------------+------------------------------------+
                              |
                              | POWER8 Emulation
                              | virtio-scsi
                              | TAP/Bridge
+-----------------------------+------------------------------------+
|                    AIX 7.2 Virtual Machine                       |
|                                                                  |
|  +------------------+    +------------------+                  |
|  | AIX 7.2 TL4 SP2  |    | en0              |                  |
|  | ppc64            |    | 10.0.2.16/24     |                  |
|  | 4GB RAM          |    | MAC: be:16:43... |                  |
|  | JFS2             |    | Gateway: 10.0.2.20|                 |
|  +------------------+    +------------------+                  |
|                                                                  |
|  +------------------+    +------------------+                  |
|  | ksh (default)    |    | OpenSSH          |                  |
|  | bash (installed) |    | RPM packages     |                  |
|  | SMIT             |    | VNC access       |                  |
|  +------------------+    +------------------+                  |
+------------------------------------------------------------------+
```

---

## Prerequisites

### Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | x86_64 with virtualization support | 4+ vCPUs |
| RAM | 6GB (2GB host + 4GB guest) | 8GB+ |
| Disk | 30GB free | 60GB+ (for build + VM + ISOs) |
| Network | Internet access | Public IP or bastion host |

### Software Requirements

- Ubuntu 22.04 LTS (or compatible Debian-based distro)
- Root or sudo access
- AIX 7.2 installation media (obtain from legal/authorized source)

### AWS-Specific Notes

If running on AWS EC2:
- Use **t3.xlarge** or larger instance type
- Attach a **secondary EBS volume** (55GB+) for VM storage
- Security Group: allow **SSH (22)**, **ICMP**, and **all outbound**
- Optional: assign an **Elastic IP** for consistent access

---

## Installation

### 1. Prepare the Ubuntu Host

```bash
# Update system
sudo apt update -y

# Install build dependencies
sudo apt install -y gcc make ninja-build libglib2.0-dev libpixman-1-dev ncurses-dev

# Install networking tools
sudo apt install -y bridge-utils
```

### 2. Compile QEMU from Source

```bash
# Download QEMU 7.2.0
cd ~
wget https://download.qemu.org/qemu-7.2.0.tar.xz
tar xvf qemu-7.2.0.tar.xz
cd qemu-7.2.0/

# Configure (all targets - takes ~85 minutes on t3.xlarge)
./configure

# OR configure for ppc64 only (faster build, ~10 minutes)
./configure --target-list=ppc64-softmmu --enable-curses --disable-gtk

# Compile and install
make
sudo make install

# Verify installation
qemu-system-ppc64 --version
```

> **Note:** The full build requires ~6GB disk space. The extracted source is ~799MB; compiled output expands significantly.

### 3. Prepare Secondary Storage (Optional)

If using a secondary EBS volume:

```bash
# Identify the new disk
lsblk
# Example output:
# nvme0n1      259:0    0    8G  0 disk   (primary)
# nvme1n1      259:4    0   55G  0 disk   (secondary)

# Partition and format
sudo fdisk /dev/nvme1n1
# Create new partition (type: Linux, default options)

sudo partprobe
sudo mkfs -t ext4 /dev/nvme1n1p1

# Get UUID for fstab
sudo blkid /dev/nvme1n1p1
# Example: UUID="a5051753-344e-43da-ba1f-cc785cab98b0"

# Add to /etc/fstab
echo 'UUID="a5051753-344e-43da-ba1f-cc785cab98b0"  /wip  ext4  defaults 0 0' | sudo tee -a /etc/fstab

# Create mount point and mount
sudo mkdir /wip
sudo mount /wip
```

### 4. Copy AIX Installation Media

```bash
# Create directory for ISOs
sudo mkdir -p /wip/AIX72ISOs
cd /wip/AIX72ISOs

# Copy AIX 7.2 ISO from a legal/authorized source
# Example: scp from another server
scp -i ~/.ssh/your-key user@source-host:/path/to/aix_7200-04-02-2027_1of2_072020.iso .

# Verify ISO is present
ls -lh
```

> **Important:** Ensure you obtain AIX media from a legal, authorized source. IBM AIX is proprietary software requiring proper licensing.

### 5. Create VM Disk

```bash
cd /wip
qemu-img create -f qcow2 hdisk0.qcow2 20G
```

---

## AIX Installation

### Start the Installation

```bash
cd /wip

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -serial stdio \
  -drive file=hdisk0.qcow2,if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -cdrom /wip/AIX72ISOs/aix_7200-04-02-2027_1of2_072020.iso \
  -prom-env "boot-command=boot cdrom:"
```

### Installation Steps

1. **Boot from CD-ROM** - The VM boots from the AIX installation ISO
2. **Select Console** - Choose option `1` to define the System Console
3. **Language** - Select `1` for English
4. **Installation Settings** - Customize as needed:
   - Ensure **SSH client and server** are selected for remote access
   - Adjust filesystem sizes if needed
5. **Begin Installation** - The process takes approximately **110 minutes**

### Post-Install Reboot Loop

After installation completes, the VM will enter a **reboot loop**. This is expected due to an `fsck64` compatibility issue.

**To exit the loop:**
```bash
# Press CTRL+C to terminate QEMU
```

---

## Post-Installation Fixes

### Fix fsck64 Reboot Loop

Boot into maintenance mode from the installation CD:

```bash
cd /wip

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -serial stdio \
  -drive file=hdisk0.qcow2,if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -cdrom /wip/AIX72ISOs/aix_7200-04-02-2027_1of2_072020.iso \
  -prom-env "boot-command=boot cdrom:"
```

**Menu selections:**
1. `1` - Define the System Console
2. `1` - English
3. `3` - Start Maintenance Mode
4. `1` - Access a Root Volume Group
5. `0` - Continue
6. `1` - Select the volume group (hdisk0)
7. `1` - Access this Volume Group and start a shell

**Inside maintenance mode:**

```bash
# Navigate to fsck64 location
cd /sbin/helpers/jfs2

# Backup original
cp fsck64 fsck64.org

# Truncate and replace with no-op script
> fsck64
cat > fsck64 << 'EOF'
#!/bin/ksh
exit 0
EOF

# Verify
cat fsck64
```

> **Warning:** No BACKSPACE key works in maintenance mode. If you make a mistake, use `CTRL+U` to clear the line. **Do NOT use CTRL+C** - it terminates the VM.

**Shutdown cleanly:**
```bash
sync; sync
halt
```

### Create a Backup Snapshot

Before first boot, create a snapshot for easy rollback:

```bash
cd /wip
qemu-img create -f qcow2 -b hdisk0.qcow2 -F qcow2 hdisk0.snap.qcow2 10G
```

### First Boot to AIX

```bash
cd /wip

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -serial stdio \
  -drive file=hdisk0.qcow2,if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -prom-env "boot-command=boot disk:"
```

**Initial Setup:**
1. Terminal type: type `vt100` and press **ENTER**
2. License acceptance: default is "no", press **TAB** to change to "yes", then **ENTER**
3. Press **Esc+0** (hold ESC, press 0) to go back
4. Accept software maintenance terms/conditions
5. Press **Esc+0** again
6. Configure additional settings:
   - Date/Time
   - Root password
   - Other preferences
7. Select **"Tasks completed - Exit to Login"**
8. Login as `root`

### Fix RPM Database

AIX's RPM database may be corrupted after installation:

```bash
cd /opt/freeware

# Backup packages
tar -chvf $(date +"%d%m%Y").rpm.packages.tar packages

# Remove lock files
rm -f /opt/freeware/packages/__*

# Rebuild database
/usr/bin/rpm --rebuilddb

# Verify
/usr/bin/rpm -qa
```

---

## Networking Setup

### Host Bridge Configuration

On the Ubuntu host, run these commands to set up networking:

```bash
# Allow QEMU to use bridge
sudo mkdir -p /usr/local/etc/qemu
echo "allow br0" | sudo tee /usr/local/etc/qemu/bridge.conf

# Create bridge
sudo ip link add name br0 type bridge
sudo ip link set dev br0 up

# Create TAP interface for VM
sudo ip tuntap add tap0 mode tap
sudo ip link set dev tap0 up
sudo ip link set dev tap0 master br0

# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1
echo 1 | sudo tee /proc/sys/net/ipv4/conf/tap0/proxy_arp

# Add route for AIX VM
sudo ip route add 10.0.2.16 dev br0
sudo arp -Ds 10.0.2.16 eth0 pub

# Configure NAT
sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
sudo iptables -I FORWARD 1 -i tap0 -j ACCEPT
sudo iptables -I FORWARD 1 -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

> **Note:** Replace `eth0` with your actual primary network interface name (check with `ip a`).

### Start VM with Networking

```bash
cd /wip

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -serial stdio \
  -drive file=hdisk0.qcow2,if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -prom-env "boot-command=boot disk:" \
  -net nic,macaddr=be:16:43:37:16:ec \
  -net tap,script=no,ifname=tap0,downscript=no
```

### Configure AIX Network

Inside AIX, assign an IP address:

```bash
# Temporary assignment (lost on reboot)
chdev -l en0 -a netaddr=10.0.2.16 -a netmask=255.255.255.0 -a state=up
```

**Make permanent using SMIT:**

```bash
smit tcpip
```

Navigate:
- **Minimum Configuration & Startup**
- Select **en0**
- Configure:
  - Hostname: `aix7vm`
  - IP Address: `10.0.2.16`
  - Network Mask: `255.255.255.0`
  - Name Server: `8.8.8.8`
  - Domain Name: `acme.com`
  - Gateway: `10.0.2.20`
- Set **"START Now"** to `yes` (press TAB to change)
- Press **ENTER** to execute

> **Note:** The gateway IP (`10.0.2.20`) should be an IP on the bridge interface. The name server and domain name are required if you want DNS resolution.

---

## Bash Installation

AIX defaults to the Korn shell (`ksh`). Bash is more familiar for most Linux users.

### 1. Expand /opt Filesystem

```bash
chfs -a size=+60M /opt
```

### 2. Download Bash RPMs

```bash
# From AIX with internet access, or create an ISO on the host
wget http://www.oss4aix.org/download/latest/aix71/libiconv-1.16-1.aix5.1.ppc.rpm
wget http://www.oss4aix.org/download/latest/aix71/bash-5.0-8.aix5.1.ppc.rpm
wget http://www.oss4aix.org/download/latest/aix71/gettext-0.19.8.1-1.aix5.1.ppc.rpm
wget http://www.oss4aix.org/download/RPMS/gcc/libgcc-6.3.0-1.aix7.2.ppc.rpm
```

### 3. Install Packages

```bash
rpm -ivh bash-5.0-8.aix5.1.ppc.rpm \
       gettext-0.19.8.1-1.aix5.1.ppc.rpm \
       libiconv-1.16-1.aix5.1.ppc.rpm \
       libgcc-6.3.0-1.aix7.2.ppc.rpm
```

### 4. Authorize Bash

```bash
export TERM=vt100

# Add bash to authorized shells
echo "/usr/bin/bash" | sudo tee -a /etc/security/login.cfg  # append to "shells =" line
echo "/usr/bin/bash" | sudo tee -a /etc/shells

# Change default shell for a user
chsh username /usr/bin/bash
```

### Create ISO with RPMs (Host Side)

If AIX doesn't have internet access, create an ISO on the Ubuntu host:

```bash
# Install genisoimage
sudo apt install -y genisoimage

# Create ISO
mkisofs -max-iso9660-filenames -o bash50.iso ./bash50/

# Mount in QEMU by adding:
# -cdrom /wip/bash50.iso
```

---

## Usage

### Normal Boot (Console Access)

```bash
cd /wip

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -serial stdio \
  -drive file=hdisk0.qcow2,if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -prom-env "boot-command=boot disk:" \
  -net nic,macaddr=be:16:43:37:16:ec \
  -net tap,script=no,ifname=tap0,downscript=no
```

### Headless Mode (Daemonize)

For background operation with SSH/VNC access:

```bash
cd /wip

qemu-system-ppc64 \
  -cpu POWER8 \
  -machine pseries \
  -m 4096 \
  -drive file=hdisk0.qcow2,if=none,id=drive-virtio-disk0 \
  -device virtio-scsi-pci,id=scsi \
  -device scsi-hd,drive=drive-virtio-disk0 \
  -prom-env "boot-command=boot disk:" \
  -net nic,macaddr=be:16:43:37:16:ec \
  -net tap,script=no,ifname=tap0,downscript=no \
  -daemonize

# VNC server will be available on 127.0.0.1:5900
# Connect with: vncviewer localhost:5900
```

> **Note:** Remove `-serial stdio` when using `-daemonize`.

### Access Methods Summary

| Method | Command / Details |
|--------|-------------------|
| **Console** | `-serial stdio` (direct terminal) |
| **SSH** | `ssh root@10.0.2.16` (after OpenSSH setup) |
| **VNC** | `vncviewer localhost:5900` (with `-daemonize`) |
| **Logout** | `~~.` (tilde-tilde-dot, same as HMC console) |

### Useful AIX Commands

```bash
# Check MAC address
entstat -d en0 | grep -i hard

# Mount CD-ROM
mount -vcdrfs -oro /dev/cd0 /mnt

# Check filesystems
df -g

# Check memory
svmon -G

# SMIT menu system
smit

# SMIT specific tasks
smit tcpip      # Network config
smit chfs       # Filesystem management
smit user       # User management
smit storage    # Storage management
```

### SMIT Navigation

| Key | Action |
|-----|--------|
| Arrow keys | Navigate menus |
| Tab | Move between fields |
| Enter | Select / Execute |
| F3 / Esc+0 | Exit / Go back |
| F1 | Help |
| F4 | List options |
| F6 | Show command |

---

## Troubleshooting

### Issue: QEMU build fails with missing dependencies

**Solution:**
```bash
sudo apt install -y gcc make ninja-build libglib2.0-dev libpixman-1-dev ncurses-dev
```

### Issue: AIX install gets stuck in reboot loop

**Solution:** This is the `fsck64` bug. Follow the [maintenance mode fix](#fix-fsck64-reboot-loop) above.

### Issue: No BACKSPACE in maintenance mode

**Solution:** Use `CTRL+U` to clear the current line. Do NOT use CTRL+C (terminates VM).

### Issue: Cannot access AIX via SSH

**Solution:**
1. Ensure OpenSSH was installed during AIX installation
2. Verify network configuration with `ifconfig en0`
3. Check host bridge and iptables rules
4. Try `ping 10.0.2.16` from the Ubuntu host

### Issue: RPM database corruption

**Solution:**
```bash
rm -f /opt/freeware/packages/__*
/usr/bin/rpm --rebuilddb
```

### Issue: Bridge not persisting after reboot

**Solution:** Create a systemd service or add bridge setup to `/etc/rc.local`:

```bash
sudo tee /etc/systemd/system/aix-bridge.service << 'EOF'
[Unit]
Description=AIX VM Bridge Setup
After=network.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aix-bridge-setup.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

sudo tee /usr/local/bin/aix-bridge-setup.sh << 'EOF'
#!/bin/bash
ip link add name br0 type bridge
ip link set dev br0 up
ip tuntap add tap0 mode tap
ip link set dev tap0 up
ip link set dev tap0 master br0
sysctl -w net.ipv4.ip_forward=1
echo 1 > /proc/sys/net/ipv4/conf/tap0/proxy_arp
ip route add 10.0.2.16 dev br0
arp -Ds 10.0.2.16 eth0 pub
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
iptables -I FORWARD 1 -i tap0 -j ACCEPT
iptables -I FORWARD 1 -o tap0 -m state --state RELATED,ESTABLISHED -j ACCEPT
EOF

sudo chmod +x /usr/local/bin/aix-bridge-setup.sh
sudo systemctl enable aix-bridge.service
```

### Issue: Performance is very slow

**Expected:** QEMU full-system emulation has significant overhead compared to native POWER hardware. This is normal. For better performance:
- Use a more powerful host (more CPU cores)
- Allocate more RAM to the VM
- Use SSD storage for the qcow2 image
- Consider using KVM acceleration if available (not possible on x86_64 for ppc64 guests)

---

## Project Structure

```
qemu-aix-on-ubuntu/
├── README.md                      # This file
├── docs/
│   └── architecture_diagram.png   # System architecture diagram
├── scripts/
│   ├── aix-bridge-setup.sh        # Bridge configuration script
│   ├── start-aix-console.sh       # Start VM with console
│   └── start-aix-headless.sh      # Start VM in background
└── .gitignore
```

---

## References

- [AIX on x86 with QEMU - AIX4Admins Blog](http://aix4admins.blogspot.com/2020/04/qemu-aix-on-x86-qemu-quick-emulator-is.html)
- [Run AIX 7.2 on x86 with QEMU - KwakouSys](https://kwakousys.wordpress.com/2020/09/06/run-aix-7-2-on-x86-with-qemu/)
- [AIX on QEMU - Worth Doing Badly](https://worthdoingbadly.com/aixqemu/)
- [RPM DB Recovery - Bobcares](https://bobcares.com/blog/rpm-db_runrecovery-errors/)
- [Bash on AIX 7.1 - Visidon](http://www.visidon.com/blog/2015/02/bash-on-aix-7-1/)
- [OSS4AIX - Open Source Packages](http://www.oss4aix.org/download/latest/aix71/)
- [IBM AIX Toolbox](https://public.dhe.ibm.com/aix/freeSoftware/aixtoolbox/RPMS/ppc/)
- [QEMU Official Documentation](https://www.qemu.org/documentation/)

---

## License

This documentation is provided for educational purposes. 

**IBM AIX** is proprietary software owned by IBM Corporation. Ensure you have proper licensing before using AIX.

**QEMU** is open-source software licensed under the GPL v2.

---

## Disclaimer

- AIX emulation via QEMU is **not supported by IBM** for production use
- Performance is significantly slower than native POWER hardware
- Some AIX features may not work correctly under emulation
- Always verify licensing compliance for AIX usage
