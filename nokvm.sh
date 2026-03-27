#!/bin/bash
set -euo pipefail

# Auto-Nix-Shell: If dependencies are missing but nix-shell is available, reload via nix-shell
if ! command -v qemu-system-x86_64 &> /dev/null || ! command -v cloud-localds &> /dev/null || ! command -v screen &> /dev/null; then
    if command -v nix-shell &> /dev/null && [[ -z "${IN_NIX_SHELL:-}" ]]; then
        echo -e "\033[1;34m[INFO]\033[0m Missing dependencies. Auto-loading nix-shell environment..."
        export IN_NIX_SHELL=1
        exec nix-shell -p qemu cloud-utils wget screen curl iproute2 --run "bash $0 $*"
    fi
fi

# =============================
# Enhanced Multi-VM Manager
# =============================

# Function to display header
display_header() {
    clear
    cat << "EOF"
========================================================================

$$\   $$\ $$$$$$\ $$$$$$$\  $$\      $$\  $$$$$$\  $$\              $$$$$$\ $$\     $$\ 
$$$\  $$ |\_$$  _|$$  __$$\ $$$\    $$$ |$$  __$$\ $$ |            $$  __$$\\$$\   $$  |
$$$$\ $$ |  $$ |  $$ |  $$ |$$$$\  $$$$ |$$ /  $$ |$$ |            $$ /  \__|\$$\ $$  / 
$$ $$\$$ |  $$ |  $$$$$$$  |$$\$$\$$ $$ |$$$$$$$$ |$$ |            $$ |       \$$$$  /  
$$ \$$$$ |  $$ |  $$  __$$< $$ \$$$  $$ |$$  __$$ |$$ |            $$ |        \$$  /   
$$ |\$$$ |  $$ |  $$ |  $$ |$$ |\$  /$$ |$$ |  $$ |$$ |            $$ |  $$\    $$ |    
$$ | \$$ |$$$$$$\ $$ |  $$ |$$ | \_/ $$ |$$ |  $$ |$$$$$$$$\       \$$$$$$  |   $$ |    
\__|  \__|\______|\__|  \__|\__|     \__|\__|  \__|\________|       \______/    \__|    
                                                                                        
                                                                                        
                                                                                        
                                                                  
                    POWERED BY K.NIRMAL
========================================================================
EOF
    echo
}

# Function to display colored output
print_status() {
    local type=$1
    local message=$2
    
    case $type in
        "INFO") echo -e "\033[1;34m[INFO]\033[0m $message" ;;
        "WARN") echo -e "\033[1;33m[WARN]\033[0m $message" ;;
        "ERROR") echo -e "\033[1;31m[ERROR]\033[0m $message" ;;
        "SUCCESS") echo -e "\033[1;32m[SUCCESS]\033[0m $message" ;;
        "INPUT") echo -e "\033[1;36m[INPUT]\033[0m $message" ;;
        *) echo "[$type] $message" ;;
    esac
}

# Function to validate input
validate_input() {
    local type=$1
    local value=$2
    
    case $type in
        "number")
            if ! [[ "$value" =~ ^[0-9]+$ ]]; then
                print_status "ERROR" "Must be a number"
                return 1
            fi
            ;;
        "memory")
            if [[ "$value" =~ ^[0-9]+$ ]]; then
                return 0
            fi
            print_status "ERROR" "Must be a number (MB) or GB value"
            return 1
            ;;
        "size")
            if [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" =~ ^[0-9]+[GgMm]$ ]]; then
                return 0
            fi
            print_status "ERROR" "Must be a size with unit (e.g., 20G, 512M) or just a number (assumed in GB)"
            return 1
            ;;
        "port")
            if ! [[ "$value" =~ ^[0-9]+$ ]] || [ "$value" -lt 23 ] || [ "$value" -gt 65535 ]; then
                print_status "ERROR" "Must be a valid port number (23-65535)"
                return 1
            fi
            ;;
        "name")
            if ! [[ "$value" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                print_status "ERROR" "VM name can only contain letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
        "username")
            if ! [[ "$value" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
                print_status "ERROR" "Username must start with a letter or underscore, and contain only letters, numbers, hyphens, and underscores"
                return 1
            fi
            ;;
    esac
    return 0
}

# Function to check dependencies
check_dependencies() {
    local deps=("qemu-system-x86_64" "wget" "cloud-localds" "qemu-img" "screen" "curl" "ss")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            # Special case for 'ss' which might be in /sbin or /usr/sbin
            if [[ "$dep" == "ss" ]] && [[ -x "/sbin/ss" || -x "/usr/sbin/ss" ]]; then
                continue
            fi
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_status "ERROR" "Missing dependencies: ${missing_deps[*]}"
        print_status "INFO" "On Ubuntu/Debian: sudo apt install qemu-system cloud-image-utils wget screen curl iproute2"
        print_status "INFO" "On Nix/NixOS: nix-shell -p qemu cloud-utils wget screen curl iproute2"
        print_status "WARN" "IMPORTANT: If you open a new terminal, you MUST run the nix-shell command again in that terminal!"
        exit 1
    fi
}

# Function to cleanup temporary files
cleanup() {
    if [ -f "user-data" ]; then rm -f "user-data"; fi
    if [ -f "meta-data" ]; then rm -f "meta-data"; fi
}

# Function to get all VM configurations
get_vm_list() {
    find "$VM_DIR" -name "*.conf" -exec basename {} .conf \; 2>/dev/null | sort
}

# Function to load VM configuration
load_vm_config() {
    local vm_name=$1
    local config_file="$VM_DIR/$vm_name.conf"
    
    if [[ -f "$config_file" ]]; then
        # Clear previous variables
        unset VM_NAME OS_TYPE CODENAME IMG_URL HOSTNAME USERNAME PASSWORD
        unset DISK_SIZE MEMORY CPUS SSH_PORT GUI_MODE PORT_FORWARDS IMG_FILE SEED_FILE CREATED
        
        source "$config_file"
        return 0
    else
        print_status "ERROR" "Configuration for VM '$vm_name' not found"
        return 1
    fi
}

# Function to save VM configuration
save_vm_config() {
    local config_file="$VM_DIR/$VM_NAME.conf"
    
    cat > "$config_file" <<EOF
VM_NAME="$VM_NAME"
OS_TYPE="$OS_TYPE"
CODENAME="$CODENAME"
IMG_URL="$IMG_URL"
HOSTNAME="$HOSTNAME"
USERNAME="$USERNAME"
PASSWORD="$PASSWORD"
DISK_SIZE="$DISK_SIZE"
MEMORY="$MEMORY"
CPUS="$CPUS"
SSH_PORT="$SSH_PORT"
GUI_MODE="$GUI_MODE"
PORT_FORWARDS="$PORT_FORWARDS"
IMG_FILE="$IMG_FILE"
SEED_FILE="$SEED_FILE"
CREATED="$CREATED"
EOF
    
    print_status "SUCCESS" "Configuration saved to $config_file"
}

# Function to create new VM
create_new_vm() {
    print_status "INFO" "Creating a new VM"
    
    # OS Selection
    print_status "INFO" "Select an OS to set up:"
    local os_options=()
    local i=1
    for os in "${!OS_OPTIONS[@]}"; do
        echo "  $i) $os"
        os_options[$i]="$os"
        ((i++))
    done
    
    while true; do
        read -p "$(print_status "INPUT" "Enter your choice (1-${#OS_OPTIONS[@]}): ")" choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#OS_OPTIONS[@]} ]; then
            local os="${os_options[$choice]}"
            IFS='|' read -r OS_TYPE CODENAME IMG_URL DEFAULT_HOSTNAME DEFAULT_USERNAME DEFAULT_PASSWORD <<< "${OS_OPTIONS[$os]}"
            break
        else
            print_status "ERROR" "Invalid selection. Try again."
        fi
    done

    # Custom Inputs with validation
    while true; do
        read -p "$(print_status "INPUT" "Enter VM name (default: $DEFAULT_HOSTNAME): ")" VM_NAME
        VM_NAME="${VM_NAME:-$DEFAULT_HOSTNAME}"
        if validate_input "name" "$VM_NAME"; then
            # Check if VM name already exists
            if [[ -f "$VM_DIR/$VM_NAME.conf" ]]; then
                print_status "ERROR" "VM with name '$VM_NAME' already exists"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter hostname (default: $VM_NAME): ")" HOSTNAME
        HOSTNAME="${HOSTNAME:-$VM_NAME}"
        if validate_input "name" "$HOSTNAME"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enter username (default: $DEFAULT_USERNAME): ")" USERNAME
        USERNAME="${USERNAME:-$DEFAULT_USERNAME}"
        if validate_input "username" "$USERNAME"; then
            break
        fi
    done

    while true; do
        read -s -p "$(print_status "INPUT" "Enter password (default: $DEFAULT_PASSWORD): ")" PASSWORD
        PASSWORD="${PASSWORD:-$DEFAULT_PASSWORD}"
        echo
        if [ -n "$PASSWORD" ]; then
            break
        else
            print_status "ERROR" "Password cannot be empty"
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Disk size (default: 20G): ")" DISK_SIZE
        DISK_SIZE="${DISK_SIZE:-20G}"
        # Automatically append 'G' if only a number is provided
        if [[ "$DISK_SIZE" =~ ^[0-9]+$ ]]; then
            DISK_SIZE="${DISK_SIZE}G"
        fi
        if validate_input "size" "$DISK_SIZE"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Memory (e.g., 2048 for 2G, or just 6 for 6G): ")" MEMORY
        MEMORY="${MEMORY:-2048}"
        # Process memory input
        if [[ "$MEMORY" =~ ^[0-9]+$ ]]; then
            if [ "$MEMORY" -lt 100 ]; then
                MEMORY=$((MEMORY * 1024))
            fi
        elif [[ "$MEMORY" =~ ^([0-9]+)[Gg]$ ]]; then
            MEMORY=$((${BASH_REMATCH[1]} * 1024))
        elif [[ "$MEMORY" =~ ^([0-9]+)[Mm]$ ]]; then
            MEMORY=${BASH_REMATCH[1]}
        fi
        
        if validate_input "memory" "$MEMORY"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Number of CPUs (default: 2): ")" CPUS
        CPUS="${CPUS:-2}"
        if validate_input "number" "$CPUS"; then
            break
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "SSH Port (default: 2222): ")" SSH_PORT
        SSH_PORT="${SSH_PORT:-2222}"
        if validate_input "port" "$SSH_PORT"; then
            # Check if port is already in use
            if ss -tln 2>/dev/null | grep -q ":$SSH_PORT "; then
                print_status "ERROR" "Port $SSH_PORT is already in use"
            else
                break
            fi
        fi
    done

    while true; do
        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, default: n): ")" gui_input
        GUI_MODE=false
        gui_input="${gui_input:-n}"
        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
            GUI_MODE=true
            break
        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
            break
        else
            print_status "ERROR" "Please answer y or n"
        fi
    done

    # Additional network options
    # Additional network options
    read -p "$(print_status "INPUT" "Additional port forwards (e.g., 8080:80, type 'All' for common ports, press Enter for none): ")" PORT_FORWARDS

    IMG_FILE="$VM_DIR/$VM_NAME.img"
    SEED_FILE="$VM_DIR/$VM_NAME-seed.iso"
    CREATED="$(date)"

    # Download and setup VM image
    setup_vm_image
    
    # Save configuration
    save_vm_config
}

# Function to setup VM image
setup_vm_image() {
    print_status "INFO" "Downloading and preparing image..."
    
    # Create VM directory if it doesn't exist
    mkdir -p "$VM_DIR"
    
    # Check if this is an ISO installer (Windows) or a disk image (Linux)
    local is_iso=false
    if [[ "$IMG_URL" =~ \.iso$ ]]; then
        is_iso=true
    fi

    if [[ "$is_iso" == true ]]; then
        local iso_path="$VM_DIR/$VM_NAME-install.iso"
        # Download ISO if it doesn't exist
        if [[ ! -f "$iso_path" ]]; then
            print_status "INFO" "Downloading ISO installer from $IMG_URL..."
            if ! wget --progress=bar:force "$IMG_URL" -O "$iso_path.tmp"; then
                print_status "ERROR" "Failed to download ISO"
                exit 1
            fi
            mv "$iso_path.tmp" "$iso_path"
        fi
        
        # Create a blank qcow2 disk if it doesn't exist
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "INFO" "Creating blank $DISK_SIZE virtual disk..."
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
        fi
    else
        # Standard cloud image (Linux)
        if [[ -f "$IMG_FILE" ]]; then
            print_status "INFO" "Image file already exists. Skipping download."
        else
            print_status "INFO" "Downloading image from $IMG_URL..."
            if ! wget --progress=bar:force "$IMG_URL" -O "$IMG_FILE.tmp"; then
                print_status "ERROR" "Failed to download image from $IMG_URL"
                exit 1
            fi
            mv "$IMG_FILE.tmp" "$IMG_FILE"
        fi
        
        # Resize the disk image if needed (Linux cloud images only)
        if ! qemu-img resize "$IMG_FILE" "$DISK_SIZE" 2>/dev/null; then
            print_status "WARN" "Failed to resize disk image. Creating new image with specified size..."
            # Create a new image with the specified size
            rm -f "$IMG_FILE"
            qemu-img create -f qcow2 -F qcow2 -b "$IMG_FILE" "$IMG_FILE.tmp" "$DISK_SIZE" 2>/dev/null || \
            qemu-img create -f qcow2 "$IMG_FILE" "$DISK_SIZE"
            if [ -f "$IMG_FILE.tmp" ]; then
                mv "$IMG_FILE.tmp" "$IMG_FILE"
            fi
        fi
    fi

    # cloud-init configuration
    cat > user-data <<EOF
#cloud-config
hostname: $HOSTNAME
ssh_pwauth: true
disable_root: false
users:
  - name: $USERNAME
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    password: $(openssl passwd -6 "$PASSWORD" | tr -d '\n')
chpasswd:
  list: |
    root:$PASSWORD
    $USERNAME:$PASSWORD
  expire: false
runcmd:
  - bash -c 'cat <<EOF > /etc/ssh/sshd_config
# SSH LOGIN SETTINGS (Configured by K.NIRMAL)
PasswordAuthentication yes
PermitRootLogin yes
PubkeyAuthentication no
ChallengeResponseAuthentication no
UsePAM yes
# SFTP SETTINGS
Subsystem sftp /usr/lib/openssh/sftp-server
EOF'
  - systemctl restart ssh 2>/dev/null || service ssh restart
  - echo "root:$PASSWORD" | chpasswd
EOF

    cat > meta-data <<EOF
instance-id: iid-$VM_NAME
local-hostname: $HOSTNAME
EOF

    if ! cloud-localds "$SEED_FILE" user-data meta-data; then
        print_status "ERROR" "Failed to create cloud-init seed image"
        exit 1
    fi
    
    print_status "SUCCESS" "VM '$VM_NAME' created successfully."
}

# Function to start a VM
start_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Starting VM: $vm_name"
        print_status "INFO" "SSH: ssh -p $SSH_PORT $USERNAME@localhost"
        print_status "INFO" "Password: $PASSWORD"
        
        # Check if image file exists
        if [[ ! -f "$IMG_FILE" ]]; then
            print_status "ERROR" "VM image file not found: $IMG_FILE"
            return 1
        fi
        
        # Check if seed file exists
        if [[ ! -f "$SEED_FILE" ]]; then
            print_status "WARN" "Seed file not found, recreating..."
            setup_vm_image
        fi
        
        # Base QEMU command
        local qemu_cmd=(
            qemu-system-x86_64
            -m "$MEMORY"
            -smp "$CPUS"
            -cpu qemu64
            -boot order=c
        )

        # Storage & Setup configuration
        if [[ "$OS_TYPE" == "windows" ]]; then
            # Windows needs IDE/SATA and a CDROM for installer
            qemu_cmd+=(
                -drive "file=$IMG_FILE,format=qcow2,if=ide"
            )
            local iso_path="$VM_DIR/$vm_name-install.iso"
            if [[ -f "$iso_path" ]]; then
                qemu_cmd+=(-drive "file=$iso_path,media=cdrom")
                qemu_cmd+=(-boot order=dc) # Try CDROM first if ISO is present
            fi
        else
            # Linux uses VirtIO and Cloud-Init seed
            qemu_cmd+=(
                -drive "file=$IMG_FILE,format=qcow2,if=virtio"
                -drive "file=$SEED_FILE,format=raw,if=virtio"
            )
        fi

        qemu_cmd+=(-device virtio-net-pci,netdev=n1)

        # Network configuration
        local slirp_options="user,id=n1,hostfwd=tcp::$SSH_PORT-:22"
        
        # Helper to add hostfwd safely without duplicates
        add_hostfwd() {
            local port=$1
            local guest=$2
            if [[ "$slirp_options" != *",hostfwd=tcp::$port-:"* ]]; then
                slirp_options+=",hostfwd=tcp::$port-:$guest"
            fi
        }

        if [[ "$OS_TYPE" == "windows" ]]; then
            add_hostfwd 3389 3389
        fi

        if [[ "$PORT_FORWARDS" =~ ^[Aa][Ll][Ll]$ ]]; then
            print_status "INFO" "Forwarding free ports in range 10-1000 (All mode)..."
            # Get list of busy ports to skip them
            local busy_ports=$(ss -tln | grep -oP '(?<=:)[0-9]+(?= )' | sort -u)
            
            # Forward 10-1000
            for port in {10..1000}; do
                if [[ "$port" -ne "$SSH_PORT" ]] && ! echo "$busy_ports" | grep -qwx "$port"; then
                    add_hostfwd "$port" "$port"
                fi
            done
            # Forward common high ports
            local high_ports=(3000 5000 8000 8080 3389 9000 9090)
            for port in "${high_ports[@]}"; do
                if [[ "$port" -gt 1000 && "$port" -ne "$SSH_PORT" ]] && ! echo "$busy_ports" | grep -qwx "$port"; then
                    add_hostfwd "$port" "$port"
                fi
            done
        elif [[ -n "$PORT_FORWARDS" ]]; then
            # Support both space and comma separation
            local cleaned_forwards=$(echo "$PORT_FORWARDS" | tr ' ' ',')
            IFS=',' read -ra forwards <<< "$cleaned_forwards"
            for forward in "${forwards[@]}"; do
                if [[ -n "$forward" ]]; then
                    if [[ "$forward" =~ ^[0-9]+$ ]]; then
                        add_hostfwd "$forward" "$forward"
                    elif [[ "$forward" =~ ^[0-9]+:[0-9]+$ ]]; then
                        add_hostfwd "${forward%%:*}" "${forward##*:}"
                    fi
                fi
            done
        fi
        qemu_cmd+=(-netdev "$slirp_options")

        # Add GUI or console mode
        if [[ "$GUI_MODE" == true ]]; then
            # Find VM index to assign unique VNC port
            local vms=($(get_vm_list))
            local vm_idx=0
            for i in "${!vms[@]}"; do
                if [[ "${vms[$i]}" == "$vm_name" ]]; then
                    vm_idx=$((i+1))
                    break
                fi
            done
            local vnc_port=$((vm_idx + 50)) # e.g., 5951, 5952
            print_status "INFO" "GUI enabled via VNC. Display: :$vnc_port (Port: $((5900 + vnc_port)))"
            qemu_cmd+=(-vga std -vnc 0.0.0.0:$vnc_port)
        else
            qemu_cmd+=(-nographic -serial mon:stdio)
        fi

        # Add performance enhancements
        qemu_cmd+=(
            -device virtio-balloon-pci
            -object rng-random,filename=/dev/urandom,id=rng0
            -device virtio-rng-pci,rng=rng0
        )

        # Windows-specific enhancements
        if [[ "$OS_TYPE" == "windows" ]]; then
            qemu_cmd+=(
                -rtc base=localtime,clock=host
                -usb
                -device usb-tablet
                -vga std
            )
        fi

        print_status "INFO" "Starting VM in background screen session 'vm_$vm_name'..."
        if is_vm_running "$vm_name"; then
            print_status "WARN" "VM is already running."
        else
            local log_file="$VM_DIR/$vm_name.log"
            screen -dmS "vm_$vm_name" bash -c "${qemu_cmd[*]} 2>&1 | tee $log_file"
            sleep 2
            if is_vm_running "$vm_name"; then
                print_status "SUCCESS" "VM $vm_name started in background."
                print_status "INFO" "Use option 9 to access terminal or 'screen -r vm_$vm_name' manually."
            else
                print_status "ERROR" "VM failed to start. Check log: $log_file"
                if [[ -f "$log_file" ]]; then
                    echo "--- Last few lines of log ---"
                    tail -n 10 "$log_file"
                    echo "----------------------------"
                fi
            fi
        fi
    fi
}

# Function to delete a VM
delete_vm() {
    local vm_name=$1
    
    print_status "WARN" "This will permanently delete VM '$vm_name' and all its data!"
    read -p "$(print_status "INPUT" "Are you sure? (y/N): ")" -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if load_vm_config "$vm_name"; then
            rm -f "$IMG_FILE" "$SEED_FILE" "$VM_DIR/$vm_name.conf"
            print_status "SUCCESS" "VM '$vm_name' has been deleted"
        fi
    else
        print_status "INFO" "Deletion cancelled"
    fi
}

# Function to show VM info
show_vm_info() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        local public_ip=$(curl -s https://api.ipify.org || echo "Unknown")
        echo
        print_status "INFO" "VM Information: $vm_name"
        echo "=========================================="
        echo "VPS Public IP: $public_ip"
        echo "OS: $OS_TYPE"
        echo "Hostname: $HOSTNAME"
        echo "Username: $USERNAME"
        echo "Password: $PASSWORD"
        echo "SSH Port: $SSH_PORT"
        echo "Memory: $MEMORY MB"
        echo "CPUs: $CPUS"
        echo "Disk: $DISK_SIZE"
        echo "GUI Mode: $GUI_MODE"
        if [[ "$GUI_MODE" == true ]]; then
            # Find VM index again
            local vms=($(get_vm_list))
            local vm_idx=0
            for i in "${!vms[@]}"; do
                if [[ "${vms[$i]}" == "$vm_name" ]]; then
                    vm_idx=$((i+1))
                    break
                fi
            done
            local vnc_port=$((vm_idx + 50))
            echo "VNC Connection: $VPS_IP:$((5900 + vnc_port))"
        fi
        echo "Port Forwards: ${PORT_FORWARDS:-None}"
        echo "Created: $CREATED"
        echo "Image File: $IMG_FILE"
        echo "Seed File: $SEED_FILE"
        echo "=========================================="
        if [[ "$OS_TYPE" == "windows" ]]; then
            print_status "SUCCESS" "RDP is automatically forwarded to port 3389."
            print_status "INFO" "Login with: $VPS_IP:3389"
            print_status "TIP" "To enable RDP inside Windows: Settings > System > Remote Desktop > Enable."
        fi
        print_status "TIP" "If you cannot connect, ensure port $SSH_PORT (and 3389 for Windows) is allowed in your VPS Firewall."
        echo
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Function to check if VM is running
is_vm_running() {
    local vm_name=$1
    if screen -list | grep -q "\.vm_$vm_name\b"; then
        return 0
    else
        return 1
    fi
}

# Function to show VM terminal log
show_vps_log() {
    local vm_name=$1
    if is_vm_running "$vm_name"; then
        print_status "INFO" "Attaching to VM terminal. Press Ctrl+A followed by D to detach."
        screen -x "vm_$vm_name"
    else
        print_status "ERROR" "VM $vm_name is not running."
    fi
}

# Function to stop a running VM
stop_vm() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Stopping VM: $vm_name"
            screen -S "vm_$vm_name" -X quit
            print_status "SUCCESS" "VM $vm_name stopped"
        else
            print_status "INFO" "VM $vm_name is not running"
        fi
    fi
}

# Function to restart a VM
restart_vm() {
    local vm_name=$1
    if is_vm_running "$vm_name"; then
        stop_vm "$vm_name"
        sleep 2
    fi
    start_vm "$vm_name"
}

# Function to edit VM configuration
edit_vm_config() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Editing VM: $vm_name"
        
        while true; do
            echo "What would you like to edit?"
            echo "  1) Hostname"
            echo "  2) Username"
            echo "  3) Password"
            echo "  4) SSH Port"
            echo "  5) GUI Mode"
            echo "  6) Port Forwards"
            echo "  7) Memory (RAM)"
            echo "  8) CPU Count"
            echo "  9) Disk Size"
            echo "  0) Back to main menu"
            
            read -p "$(print_status "INPUT" "Enter your choice: ")" edit_choice
            
            case $edit_choice in
                1)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new hostname (current: $HOSTNAME): ")" new_hostname
                        new_hostname="${new_hostname:-$HOSTNAME}"
                        if validate_input "name" "$new_hostname"; then
                            HOSTNAME="$new_hostname"
                            break
                        fi
                    done
                    ;;
                2)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new username (current: $USERNAME): ")" new_username
                        new_username="${new_username:-$USERNAME}"
                        if validate_input "username" "$new_username"; then
                            USERNAME="$new_username"
                            break
                        fi
                    done
                    ;;
                3)
                    while true; do
                        read -s -p "$(print_status "INPUT" "Enter new password (current: ****): ")" new_password
                        new_password="${new_password:-$PASSWORD}"
                        echo
                        if [ -n "$new_password" ]; then
                            PASSWORD="$new_password"
                            break
                        else
                            print_status "ERROR" "Password cannot be empty"
                        fi
                    done
                    ;;
                4)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new SSH port (current: $SSH_PORT): ")" new_ssh_port
                        new_ssh_port="${new_ssh_port:-$SSH_PORT}"
                        if validate_input "port" "$new_ssh_port"; then
                            # Check if port is already in use
                            if [ "$new_ssh_port" != "$SSH_PORT" ] && ss -tln 2>/dev/null | grep -q ":$new_ssh_port "; then
                                print_status "ERROR" "Port $new_ssh_port is already in use"
                            else
                                SSH_PORT="$new_ssh_port"
                                break
                            fi
                        fi
                    done
                    ;;
                5)
                    while true; do
                        read -p "$(print_status "INPUT" "Enable GUI mode? (y/n, current: $GUI_MODE): ")" gui_input
                        gui_input="${gui_input:-}"
                        if [[ "$gui_input" =~ ^[Yy]$ ]]; then 
                            GUI_MODE=true
                            break
                        elif [[ "$gui_input" =~ ^[Nn]$ ]]; then
                            GUI_MODE=false
                            break
                        elif [ -z "$gui_input" ]; then
                            # Keep current value if user just pressed Enter
                            break
                        else
                            print_status "ERROR" "Please answer y or n"
                        fi
                    done
                    ;;
                6)
                    read -p "$(print_status "INPUT" "Additional port forwards (current: ${PORT_FORWARDS:-None}): ")" new_port_forwards
                    PORT_FORWARDS="${new_port_forwards:-$PORT_FORWARDS}"
                    ;;
                7)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new memory (current: $MEMORY MB): ")" new_memory
                        new_memory="${new_memory:-$MEMORY}"
                        # Process memory input
                        if [[ "$new_memory" =~ ^[0-9]+$ ]]; then
                            if [ "$new_memory" -lt 100 ]; then
                                new_memory=$((new_memory * 1024))
                            fi
                        elif [[ "$new_memory" =~ ^([0-9]+)[Gg]$ ]]; then
                            new_memory=$((${BASH_REMATCH[1]} * 1024))
                        elif [[ "$new_memory" =~ ^([0-9]+)[Mm]$ ]]; then
                            new_memory=${BASH_REMATCH[1]}
                        fi

                        if validate_input "memory" "$new_memory"; then
                            MEMORY="$new_memory"
                            break
                        fi
                    done
                    ;;
                8)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new CPU count (current: $CPUS): ")" new_cpus
                        new_cpus="${new_cpus:-$CPUS}"
                        if validate_input "number" "$new_cpus"; then
                            CPUS="$new_cpus"
                            break
                        fi
                    done
                    ;;
                9)
                    while true; do
                        read -p "$(print_status "INPUT" "Enter new disk size (current: $DISK_SIZE): ")" new_disk_size
                        new_disk_size="${new_disk_size:-$DISK_SIZE}"
                        # Automatically append 'G' if only a number is provided
                        if [[ "$new_disk_size" =~ ^[0-9]+$ ]]; then
                            new_disk_size="${new_disk_size}G"
                        fi
                        if validate_input "size" "$new_disk_size"; then
                            DISK_SIZE="$new_disk_size"
                            break
                        fi
                    done
                    ;;
                0)
                    return 0
                    ;;
                *)
                    print_status "ERROR" "Invalid selection"
                    continue
                    ;;
            esac
            
            # Recreate seed image with new configuration if user/password/hostname changed
            if [[ "$edit_choice" -eq 1 || "$edit_choice" -eq 2 || "$edit_choice" -eq 3 ]]; then
                print_status "INFO" "Updating cloud-init configuration..."
                setup_vm_image
            fi
            
            # Save configuration
            save_vm_config
            
            read -p "$(print_status "INPUT" "Continue editing? (y/N): ")" continue_editing
            if [[ ! "$continue_editing" =~ ^[Yy]$ ]]; then
                break
            fi
        done
    fi
}

# Function to resize VM disk
resize_vm_disk() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        print_status "INFO" "Current disk size: $DISK_SIZE"
        
        while true; do
            read -p "$(print_status "INPUT" "Enter new disk size (e.g., 50G): ")" new_disk_size
            # Automatically append 'G' if only a number is provided
            if [[ "$new_disk_size" =~ ^[0-9]+$ ]]; then
                new_disk_size="${new_disk_size}G"
            fi
            if validate_input "size" "$new_disk_size"; then
                if [[ "$new_disk_size" == "$DISK_SIZE" ]]; then
                    print_status "INFO" "New disk size is the same as current size. No changes made."
                    return 0
                fi
                
                # Check if new size is smaller than current (not recommended)
                local current_size_num=${DISK_SIZE%[GgMm]}
                local new_size_num=${new_disk_size%[GgMm]}
                local current_unit=${DISK_SIZE: -1}
                local new_unit=${new_disk_size: -1}
                
                # Convert both to MB for comparison
                if [[ "$current_unit" =~ [Gg] ]]; then
                    current_size_num=$((current_size_num * 1024))
                fi
                if [[ "$new_unit" =~ [Gg] ]]; then
                    new_size_num=$((new_size_num * 1024))
                fi
                
                if [[ $new_size_num -lt $current_size_num ]]; then
                    print_status "WARN" "Shrinking disk size is not recommended and may cause data loss!"
                    read -p "$(print_status "INPUT" "Are you sure you want to continue? (y/N): ")" confirm_shrink
                    if [[ ! "$confirm_shrink" =~ ^[Yy]$ ]]; then
                        print_status "INFO" "Disk resize cancelled."
                        return 0
                    fi
                fi
                
                # Resize the disk
                print_status "INFO" "Resizing disk to $new_disk_size..."
                if qemu-img resize "$IMG_FILE" "$new_disk_size"; then
                    DISK_SIZE="$new_disk_size"
                    save_vm_config
                    print_status "SUCCESS" "Disk resized successfully to $new_disk_size"
                else
                    print_status "ERROR" "Failed to resize disk"
                    return 1
                fi
                break
            fi
        done
    fi
}

# Function to show VM performance metrics
show_vm_performance() {
    local vm_name=$1
    
    if load_vm_config "$vm_name"; then
        if is_vm_running "$vm_name"; then
            print_status "INFO" "Performance metrics for VM: $vm_name"
            echo "=========================================="
            
            # Get QEMU process ID
            local qemu_pid=$(pgrep -f "qemu-system-x86_64.*$IMG_FILE")
            if [[ -n "$qemu_pid" ]]; then
                # Show process stats
                echo "QEMU Process Stats:"
                ps -p "$qemu_pid" -o pid,%cpu,%mem,sz,rss,vsz,cmd --no-headers
                echo
                
                # Show memory usage
                echo "Memory Usage:"
                free -h
                echo
                
                # Show disk usage
                echo "Disk Usage:"
                df -h "$IMG_FILE" 2>/dev/null || du -h "$IMG_FILE"
            else
                print_status "ERROR" "Could not find QEMU process for VM $vm_name"
            fi
        else
            print_status "INFO" "VM $vm_name is not running"
            echo "Configuration:"
            echo "  Memory: $MEMORY MB"
            echo "  CPUs: $CPUS"
            echo "  Disk: $DISK_SIZE"
        fi
        echo "=========================================="
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    fi
}

# Main menu function
main_menu() {
    while true; do
        display_header
        
        local vms=($(get_vm_list))
        local vm_count=${#vms[@]}
        
        if [ $vm_count -gt 0 ]; then
            print_status "INFO" "Found $vm_count existing VM(s):"
            for i in "${!vms[@]}"; do
                local status="Stopped"
                if is_vm_running "${vms[$i]}"; then
                    status="Running"
                fi
                printf "  %2d) %s (%s)\n" $((i+1)) "${vms[$i]}" "$status"
            done
            echo
        fi
        
        echo "Main Menu:"
        echo "  1) Create a new VM"
        if [ $vm_count -gt 0 ]; then
            echo "  2) Start a VM"
            echo "  3) Stop a VM"
            echo "  4) Show VM performance"
            echo "  5) Restart a VM"
            echo "  6) Edit VM configuration"
            echo "  7) Delete a VM"
            echo "  8) Resize VM disk"
            echo "  9) Show VM info"
            echo "  10) VPS Terminal Log"
        fi
        echo "  0) Exit"
        echo
        
        read -p "$(print_status "INPUT" "Enter your choice: ")" choice
        
        case $choice in
            1)
                create_new_vm
                ;;
            2)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to start: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        start_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            3)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to stop: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        stop_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            4)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show performance: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_performance "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            5)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to restart: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        restart_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            6)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to edit: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        edit_vm_config "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            7)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to delete: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        delete_vm "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            8)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to resize disk: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        resize_vm_disk "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            9)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to show info: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vm_info "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            10)
                if [ $vm_count -gt 0 ]; then
                    read -p "$(print_status "INPUT" "Enter VM number to access terminal log: ")" vm_num
                    if [[ "$vm_num" =~ ^[0-9]+$ ]] && [ "$vm_num" -ge 1 ] && [ "$vm_num" -le $vm_count ]; then
                        show_vps_log "${vms[$((vm_num-1))]}"
                    else
                        print_status "ERROR" "Invalid selection"
                    fi
                fi
                ;;
            0)
                print_status "INFO" "Goodbye!"
                exit 0
                ;;
            *)
                print_status "ERROR" "Invalid option"
                ;;
        esac
        
        read -p "$(print_status "INPUT" "Press Enter to continue...")"
    done
}

# Set trap to cleanup on exit
trap cleanup EXIT

# Check dependencies
check_dependencies

# Initialize paths
VM_DIR="${VM_DIR:-$HOME/vms}"
mkdir -p "$VM_DIR"

# Supported OS list
declare -A OS_OPTIONS=(
    ["Ubuntu 22.04"]="ubuntu|jammy|https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img|ubuntu22|ubuntu|ubuntu"
    ["Ubuntu 24.04"]="ubuntu|noble|https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img|ubuntu24|ubuntu|ubuntu"
    ["Debian 11"]="debian|bullseye|https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2|debian11|debian|debian"
    ["Debian 12"]="debian|bookworm|https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2|debian12|debian|debian"
    ["Fedora 40"]="fedora|40|https://download.fedoraproject.org/pub/fedora/linux/releases/40/Cloud/x86_64/images/Fedora-Cloud-Base-40-1.14.x86_64.qcow2|fedora40|fedora|fedora"
    ["CentOS Stream 9"]="centos|stream9|https://cloud.centos.org/centos/9-stream/x86_64/images/CentOS-Stream-GenericCloud-9-latest.x86_64.qcow2|centos9|centos|centos"
    ["AlmaLinux 9"]="almalinux|9|https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2|almalinux9|alma|alma"
    ["Rocky Linux 9"]="rockylinux|9|https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud.latest.x86_64.qcow2|rocky9|rocky|rocky"
    ["Windows 10"]="windows|10|https://software-static.download.prss.microsoft.com/dblo/MSDL/ESRP/Win10_22H2_English_x64v1.iso|win10|admin|password"
    ["Windows 11"]="windows|11|https://software-static.download.prss.microsoft.com/dblo/MSDL/ESRP/Win11_23H2_English_x64v2.iso|win11|admin|password"
)

# Start the main menu
main_menu
