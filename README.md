# 🚀 Enhanced Multi-VM Manager (QEMU-Based)

A powerful, lightweight, and versatile script to manage multiple Virtual Machines (VMs) using QEMU. This tool is designed for developers, sysadmins, and enthusiasts who need to quickly spin up, manage, and monitor VMs with ease.

---

## 🌟 Key Features

- **Multi-OS Support**: Easily deploy popular Linux distributions and Windows.
  - 🐧 Ubuntu 22.04, 24.04
  - 🍎 Debian 11, 12
  - 🎩 Fedora, CentOS, AlmaLinux, Rocky Linux
  - 🪟 **New: Windows 10 & Windows 11 Support**
- **Smart Networking**:
  - Automatic SSH port forwarding.
  - **New: "All" Port Forwarding** - Easily forward a safe range of common ports (10-1000 + common high ports) automatically, or provide your own space/comma separated list of ports.
- **Enhanced Monitoring**:
  - **New: VPS Public IP Detection** - View your server's public IP directly in the VM info.
  - **New: VPS Terminal Log (Option 9)** - Attach and detach from your VM's live console using `screen`.
- **Background Execution**: VMs run in background `screen` sessions, allowing them to stay alive even after you close your terminal.
- **Disk Management**: Simple disk resizing and cloud-init based configuration.
- **Dual Mode**:
  - `vm.sh`: High-performance mode using KVM acceleration.
  - `nokvm.sh`: Compatible mode for systems without KVM support (e.g., nesting in some VPS environments).

---

## 🛠️ Prerequisites

Ensure you have the following installed on your host system:
- QEMU (`qemu-system-x86_64`)
- wget
- Cloud Image Utils (`cloud-localds`)
- screen
- curl

**On Ubuntu/Debian:**
```bash
sudo apt update
sudo apt install qemu-system cloud-image-utils wget screen curl
```

**On Nix/NixOS:**
```bash
nix-shell -p qemu cloud-utils wget screen curl iproute2
```
> [!IMPORTANT]
> If you open a **new terminal tab or window**, you MUST run the `nix-shell` command again in that new terminal before running `vm.sh`.

---

## 🌐 Public IP Setup (LXC Users)

If you are using LXC on the host and want to route a public IP to your VM, use:
```bash
lxc config device add VM_NAME pubip nic nictype=routed parent=eth0 ipv4.address=YOUR_PUBLIC_IP name=eth1
```

---

## 🔒 Firewall Setup (CRITICAL)

If you are using a cloud provider (Google Cloud, AWS, Oracle, etc.), you **MUST** open the ports manually in your provider's control panel:

1.  **SSH Port**: Open port `2025` (or whatever port you used).
2.  **All Range**: If you used "**All**" mode, open a range from `10` to `1000`.
3.  **Target**: TCP / All Instances (or specific IP).

Without this step, your computer will not be able to connect to the VM (**Connection Timed Out**).

---

## 🚀 Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/K-NIRMAL/vms-main.git
   cd vms-main
   ```

2. **Make the scripts executable**:
   ```bash
   chmod +x vm.sh nokvm.sh
   ```

3. **Run the manager**:
   - Use KVM (Recommended): `./vm.sh`
   - Use No-KVM: `./nokvm.sh`

---

## 📖 Usage Guide

1. **Create a VM**: Select option 1, choose your OS, and follow the prompts. Type **'All'** during the port forward step to enable common port exposure.
2. **Start a VM**: Select option 2 and enter the VM number.
3. **Show Info**: Select option 4 to see details like the VPS Public IP and credentials.
4. **Terminal Access**: Use **Option 9** to view the live terminal. To exit the terminal without stopping the VM, press `Ctrl+A` then `D`.
5. **Stop a VM**: Select option 3 to safely terminate the VM session.

---

## 👤 Author

**K.NIRMAL**

---

## 📜 License

This project is licensed under the MIT License. See `LICENSE.txt` for details.

> [!CAUTION]
> Always ensure you have sufficient RAM and Disk space on your host before spinning up multiple VMs. Windows VMs require at least 4GB RAM for a smooth experience.
