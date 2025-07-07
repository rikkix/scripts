#!/bin/bash

## Simplified Debian 12 (Bookworm) 64-bit network installer
## Creates user 'rikki' with SSH key authentication
## Disables password login and root login

[[ "$EUID" -ne '0' ]] && echo "Error: This script must be run as root!" && exit 1

# Auto-detect architecture and set configuration for Debian 12
readonly RELEASE='Debian'
readonly DIST='bookworm'
readonly SSH_PORT='22'
readonly IP_DNS='8.8.8.8'

# Detect architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)
        readonly VER='amd64'
        ;;
    aarch64)
        readonly VER='arm64'
        ;;
    *)
        echo "Error: Unsupported architecture: $ARCH"
        echo "Supported architectures: x86_64 (amd64), aarch64 (arm64)"
        exit 1
        ;;
esac

# Logging functions
log_info() {
    echo -e "\033[32m[INFO]\033[0m $(date '+%H:%M:%S') - $1"
}

log_warn() {
    echo -e "\033[33m[WARN]\033[0m $(date '+%H:%M:%S') - $1"
}

log_error() {
    echo -e "\033[31m[ERROR]\033[0m $(date '+%H:%M:%S') - $1"
}

log_step() {
    echo -e "\n\033[36m[STEP]\033[0m $(date '+%H:%M:%S') - $1"
}

log_info "Detected architecture: $ARCH -> Debian $VER"

# Check if required dependencies are installed
check_dependencies() {
    local deps="$1"
    local missing=0
    
    for dep in $(echo "$deps" | sed 's/,/\n/g'); do
        if [[ -n "$dep" ]]; then
            if command -v "$dep" >/dev/null 2>&1; then
                echo -e "[\033[32mok\033[0m]\t$dep"
            else
                missing=1
                echo -e "[\033[31mNot Install\033[0m]\t$dep"
            fi
        fi
    done
    
    if [[ "$missing" -eq 1 ]]; then
        echo -e "\n\033[31mError! \033[0mPlease install missing dependencies.\n"
        exit 1
    fi
}

# Convert CIDR to netmask
cidr_to_netmask() {
    local cidr="${1:-32}"
    local binary=""
    local mask=""
    
    for ((i=0; i<32; i++)); do
        if [[ $i -lt $cidr ]]; then
            binary="${binary}1"
        else
            binary="${binary}0"
        fi
    done
    
    for ((i=0; i<4; i++)); do
        local octet_start=$((i * 8 + 1))
        local octet_end=$(((i + 1) * 8))
        local octet_binary="${binary:$((octet_start-1)):8}"
        local octet_decimal=$((2#$octet_binary))
        
        if [[ -z "$mask" ]]; then
            mask="$octet_decimal"
        else
            mask="${mask}.${octet_decimal}"
        fi
    done
    
    echo "$mask"
}

# Get primary network interface
get_network_interface() {
    local interface=""
    local interfaces=$(cat /proc/net/dev | grep ':' | cut -d':' -f1 | sed 's/\s//g' | grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn')
    local default_route=$(ip route show default | grep "^default")
    
    for item in $interfaces; do
        [[ -n "$item" ]] || continue
        if echo "$default_route" | grep -q "$item"; then
            interface="$item"
            break
        fi
    done
    
    echo "$interface"
}

# Get primary disk
get_primary_disk() {
    local disks=$(lsblk | sed 's/[[:space:]]*$//' | grep "disk$" | cut -d' ' -f1 | grep -v "fd[0-9]*\|sr[0-9]*" | head -n1)
    
    if [[ -z "$disks" ]]; then
        echo ""
        return
    fi
    
    if echo "$disks" | grep -q "/dev"; then
        echo "$disks"
    else
        echo "/dev/$disks"
    fi
}

# Find GRUB configuration
find_grub_config() {
    local boot_dir="${1:-/boot}"
    local grub_folder=$(find "$boot_dir" -type d -name "grub*" 2>/dev/null | head -n1)
    
    [[ -n "$grub_folder" ]] || return 1
    
    local grub_file=$(ls -1 "$grub_folder" 2>/dev/null | grep '^grub.conf$\|^grub.cfg$')
    
    if [[ -z "$grub_file" ]]; then
        if ls -1 "$grub_folder" 2>/dev/null | grep -q '^grubenv$'; then
            grub_folder=$(find "$boot_dir" -type f -name "grubenv" 2>/dev/null | xargs dirname | grep -v "^$grub_folder" | head -n1)
            [[ -n "$grub_folder" ]] || return 1
            grub_file=$(ls -1 "$grub_folder" 2>/dev/null | grep '^grub.conf$\|^grub.cfg$')
        fi
    fi
    
    [[ -n "$grub_file" ]] || return 1
    
    local grub_version
    if [[ "$grub_file" == "grub.cfg" ]]; then
        grub_version="0"
    else
        grub_version="1"
    fi
    
    echo "${grub_folder}:${grub_file}:${grub_version}"
}

log_step "Checking GRUB bootloader"
grub_info=$(find_grub_config "/boot")
if [[ -z "$grub_info" ]]; then
    log_error "GRUB bootloader not found in /boot"
    exit 1
fi
log_info "GRUB bootloader found and validated"

readonly GRUB_DIR=$(echo "$grub_info" | cut -d':' -f1)
readonly GRUB_FILE=$(echo "$grub_info" | cut -d':' -f2)
readonly GRUB_VERSION=$(echo "$grub_info" | cut -d':' -f3)
log_info "GRUB details: Dir=$GRUB_DIR, File=$GRUB_FILE, Version=$GRUB_VERSION"

clear
log_step "Checking system dependencies"
check_dependencies "wget,awk,grep,sed,cut,cat,lsblk,cpio,gzip,find,dirname,basename,ip,openssl,curl"

log_step "Fetching SSH keys for user rikki"
SSH_KEYS=$(curl -s --connect-timeout 10 --max-time 30 https://github.com/rikkix.keys)
if [[ -z "$SSH_KEYS" ]]; then
    log_error "Failed to fetch SSH keys from https://github.com/rikkix.keys"
    log_error "Cannot proceed without SSH keys as password authentication will be disabled"
    exit 1
fi
log_info "Successfully fetched SSH keys for user rikki"

log_step "Detecting network configuration"
interface=$(get_network_interface)
if [[ -z "$interface" ]]; then
    log_error "No network interface found"
    exit 1
fi
log_info "Found network interface: $interface"

iAddr=$(ip addr show dev "$interface" | grep "inet.*" | head -n1 | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[0-9]\{1,2\}')
ipAddr=$(echo "${iAddr}" | cut -d'/' -f1)
ipMask=$(cidr_to_netmask "$(echo "${iAddr}" | cut -d'/' -f2)")
ipGate=$(ip route show default | grep "^default" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | head -n1)

if [[ -z "$ipAddr" || -z "$ipMask" || -z "$ipGate" ]]; then
    log_error "Invalid network configuration detected"
    log_error "IP: $ipAddr, Mask: $ipMask, Gateway: $ipGate"
    exit 1
fi
log_info "Network configuration: $ipAddr/$ipMask via $ipGate"

log_step "Detecting disk configuration"
tempDisk=$(get_primary_disk)
if [[ -n "$tempDisk" ]]; then
    IncDisk="$tempDisk"
    log_info "Found disk: $IncDisk"
else
    IncDisk="default"
    log_warn "No specific disk detected, using default"
fi

# Use default Debian mirror
readonly LINUX_MIRROR="http://deb.debian.org/debian"

clear
log_step "Preparing Debian 12 (Bookworm) $VER installation"
log_info "Network: $ipAddr/$ipMask via $ipGate"
log_info "Target disk: $IncDisk"
log_info "Mirror: $LINUX_MIRROR"

log_step "Downloading installer files"
log_info "Downloading initrd.img..."
wget --no-check-certificate -qO '/tmp/initrd.img' "${LINUX_MIRROR}/dists/${DIST}/main/installer-${VER}/current/images/netboot/debian-installer/${VER}/initrd.gz"
if [[ $? -ne 0 ]]; then
    log_error "Download initrd.img failed from ${LINUX_MIRROR}/dists/${DIST}/main/installer-${VER}/current/images/netboot/debian-installer/${VER}/initrd.gz"
    exit 1
fi
log_info "initrd.img downloaded successfully"

log_info "Downloading vmlinuz..."
wget --no-check-certificate -qO '/tmp/vmlinuz' "${LINUX_MIRROR}/dists/${DIST}/main/installer-${VER}/current/images/netboot/debian-installer/${VER}/linux"
if [[ $? -ne 0 ]]; then
    log_error "Download vmlinuz failed from ${LINUX_MIRROR}/dists/${DIST}/main/installer-${VER}/current/images/netboot/debian-installer/${VER}/linux"
    exit 1
fi
log_info "vmlinuz downloaded successfully"

log_step "Backing up and modifying GRUB configuration"
if [[ ! -f "${GRUB_DIR}/${GRUB_FILE}" ]]; then
    log_error "GRUB file not found: ${GRUB_DIR}/${GRUB_FILE}"
    exit 1
fi
log_info "Found GRUB file: ${GRUB_DIR}/${GRUB_FILE}"

# Backup GRUB configuration
if [[ ! -f "${GRUB_DIR}/${GRUB_FILE}.old" && -f "${GRUB_DIR}/${GRUB_FILE}.bak" ]]; then
    mv -f "${GRUB_DIR}/${GRUB_FILE}.bak" "${GRUB_DIR}/${GRUB_FILE}.old"
fi
mv -f "${GRUB_DIR}/${GRUB_FILE}" "${GRUB_DIR}/${GRUB_FILE}.bak"
log_info "GRUB configuration backed up to ${GRUB_DIR}/${GRUB_FILE}.bak"

# Restore GRUB configuration
if [[ -f "${GRUB_DIR}/${GRUB_FILE}.old" ]]; then
    cat "${GRUB_DIR}/${GRUB_FILE}.old" > "${GRUB_DIR}/${GRUB_FILE}"
else
    cat "${GRUB_DIR}/${GRUB_FILE}.bak" > "${GRUB_DIR}/${GRUB_FILE}"
fi

log_info "Configuring GRUB entry for Debian installer"
if [[ "$GRUB_VERSION" == '0' ]]; then
    log_info "Using GRUB 2 configuration format"
    
    readonly READGRUB='/tmp/grub.read'
    cat "$GRUB_DIR/$GRUB_FILE" | sed -n '1h;1!H;$g;s/\n/%%%%%%%/g;$p' | grep -om 1 'menuentry\ [^{]*{[^}]*}%%%%%%%' | sed 's/%%%%%%%/\n/g' > "$READGRUB"
    
    CFG0="$(awk '/menuentry /{print NR}' "$READGRUB" | head -n 1)"
    CFG1="$(awk '/}/{print NR}' "$READGRUB" | head -n 1)"
    sed -n "$CFG0,$CFG1"p "$READGRUB" > /tmp/grub.new
    
    sed -i "/menuentry.*/c\menuentry\ 'Install Debian 12 (Bookworm) $VER'\ --class debian\ --class\ gnu-linux\ --class\ gnu\ --class\ os\ \{" /tmp/grub.new
    sed -i "/echo.*Loading/d" /tmp/grub.new
    
    LinuxKernel="$(grep 'linux.*/\|kernel.*/' /tmp/grub.new | awk '{print $1}' | head -n 1)"
    LinuxIMG="$(grep 'initrd.*/' /tmp/grub.new | awk '{print $1}' | tail -n 1)"
    
    if [[ -z "$LinuxIMG" ]]; then
        sed -i "/$LinuxKernel.*\//a\\\tinitrd\ \/" /tmp/grub.new
        LinuxIMG='initrd'
    fi
    
    sed -i "/$LinuxKernel.*\//c\\\t$LinuxKernel\\t\/boot\/vmlinuz auto=true hostname=debian domain=debian quiet" /tmp/grub.new
    sed -i "/$LinuxIMG.*\//c\\\t$LinuxIMG\\t\/boot\/initrd.img" /tmp/grub.new
    
    INSERTGRUB="$(awk '/menuentry /{print NR}' "$GRUB_DIR/$GRUB_FILE" | head -n 1)"
    sed -i "${INSERTGRUB}i\\n" "$GRUB_DIR/$GRUB_FILE"
    sed -i "${INSERTGRUB}r /tmp/grub.new" "$GRUB_DIR/$GRUB_FILE"
    
    if [[ -f "$GRUB_DIR/grubenv" ]]; then
        sed -i 's/saved_entry/#saved_entry/g' "$GRUB_DIR/grubenv"
    fi
    
    log_info "GRUB entry added successfully"
else
    log_warn "GRUB version not supported for automatic configuration"
fi

log_step "Creating preseed configuration"
[[ -d /tmp/boot ]] && rm -rf /tmp/boot
mkdir -p /tmp/boot
cd /tmp/boot
log_info "Working directory: $(pwd)"

log_info "Extracting initrd.img for modification..."
gzip -d < /tmp/initrd.img | cpio --extract --make-directories --no-absolute-filenames >/dev/null 2>&1
log_info "initrd.img extracted successfully"

cat > /tmp/boot/preseed.cfg << EOF
d-i debian-installer/locale string en_US.UTF-8
d-i debian-installer/country string US
d-i debian-installer/language string en
d-i console-setup/layoutcode string us
d-i keyboard-configuration/xkb-keymap string us

d-i netcfg/choose_interface select auto
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/dhcp_failed note
d-i netcfg/dhcp_options select Configure network manually
d-i netcfg/get_ipaddress string $ipAddr
d-i netcfg/get_netmask string $ipMask
d-i netcfg/get_gateway string $ipGate
d-i netcfg/get_nameservers string $IP_DNS
d-i netcfg/no_default_route boolean true
d-i netcfg/confirm_static boolean true

d-i hw-detect/load_firmware boolean true

d-i mirror/country string manual
d-i mirror/http/hostname string deb.debian.org
d-i mirror/http/directory string /debian
d-i mirror/http/proxy string

d-i passwd/root-login boolean false
d-i passwd/make-user boolean true
d-i passwd/user-fullname string Rikki
d-i passwd/username string rikki
d-i passwd/user-password-crypted password !
d-i passwd/user-uid string 1000

d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i clock-setup/ntp boolean false

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/mount_style select uuid
d-i partman/choose_partition select finish
d-i partman-auto/method string regular
d-i partman-auto/init_automatically_partition select Guided - use entire disk
d-i partman-auto/choose_recipe select All files in one partition (recommended for new users)
d-i partman-md/device_remove_md boolean true
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

d-i debian-installer/allow_unauthenticated boolean true

tasksel tasksel/first multiselect minimal
d-i pkgsel/include string openssh-server curl wget sudo neovim
d-i pkgsel/upgrade select none
d-i apt-setup/services-select multiselect

popularity-contest popularity-contest/participate boolean false

d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string $IncDisk
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/reboot boolean true
d-i preseed/late_command string \\
sed -ri 's/^#?Port.*/Port $SSH_PORT/g' /target/etc/ssh/sshd_config || exit 10; \\
sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin no/g' /target/etc/ssh/sshd_config || exit 11; \\
sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication no/g' /target/etc/ssh/sshd_config || exit 12; \\
sed -ri 's/^#?PubkeyAuthentication.*/PubkeyAuthentication yes/g' /target/etc/ssh/sshd_config || exit 13; \\
chmod 640 /target/etc/sudoers || exit 14; \\
echo 'rikki ALL=(ALL:ALL) NOPASSWD:ALL' >> /target/etc/sudoers || exit 15; \\
chmod 440 /target/etc/sudoers || exit 16; \\
mkdir -p /target/home/rikki/.ssh || exit 17; \\
chmod 700 /target/home/rikki/.ssh || exit 18; \\
echo '$SSH_KEYS' > /target/home/rikki/.ssh/authorized_keys || exit 19; \\
chmod 600 /target/home/rikki/.ssh/authorized_keys || exit 20; \\
chroot /target chown -R rikki:rikki /home/rikki/.ssh || exit 21;
EOF

log_info "Creating preseed configuration file..."
log_info "Preseed configuration created with user 'rikki' and SSH key authentication"

log_step "Creating new initrd with preseed configuration"
find . | cpio -H newc --create | gzip -9 > /tmp/initrd.img
log_info "New initrd.img created with preseed configuration"

log_info "Copying installer files to /boot..."
cp -f /tmp/initrd.img /boot/initrd.img
cp -f /tmp/vmlinuz /boot/vmlinuz
log_info "Installer files copied to /boot successfully"

log_info "Setting GRUB file permissions..."
chown root:root "$GRUB_DIR/$GRUB_FILE"
chmod 644 "$GRUB_DIR/$GRUB_FILE"
log_info "GRUB file permissions set successfully"

log_step "Installation preparation completed successfully!"
log_info "System will reboot and install Debian 12 automatically"
log_info "Final configuration:"
log_info "  - User: rikki (with sudo privileges)"
log_info "  - SSH key authentication enabled"
log_info "  - Password authentication disabled"
log_info "  - Root login disabled"
log_info "  - SSH available on port $SSH_PORT"
log_warn "System will reboot in 5 seconds..."

sleep 5 && reboot