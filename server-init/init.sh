#!/bin/bash

# Debian Server Initialization Script
# This script sets up a new Debian server with security best practices
# Run as user 'rikki' with sudo privileges

set -e

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

log_step "Starting Debian server initialization..."

# Check if running as root on bare system (reinstall.sh not run)
if [[ "$EUID" -eq 0 ]]; then
    log_warn "Running as root - checking if this is a bare system setup"
    
    # Check if user rikki exists
    if ! id "rikki" &>/dev/null; then
        log_step "Bare system detected - setting up user rikki and SSH"
        
        # Create user rikki
        log_info "Creating user rikki"
        useradd -m -s /bin/bash rikki
        
        # Create SSH directory
        mkdir -p /home/rikki/.ssh
        chmod 700 /home/rikki/.ssh
        
        # Download SSH public key from GitHub
        log_info "Downloading SSH public key for rikki"
        if ! curl -s --connect-timeout 10 --max-time 30 https://github.com/rikkix.keys > /home/rikki/.ssh/authorized_keys; then
            log_error "Failed to download SSH keys from GitHub"
            exit 1
        fi
        chmod 600 /home/rikki/.ssh/authorized_keys
        chown -R rikki:rikki /home/rikki/.ssh
        
        # Add rikki to sudo group
        log_info "Adding rikki to sudo group"
        usermod -aG sudo rikki
        echo "rikki ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rikki
        
        # Configure SSH security
        log_info "Configuring SSH security"
        sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
        sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
        sed -i 's/#PubkeyAuthentication yes/PubkeyAuthentication yes/' /etc/ssh/sshd_config
        systemctl restart ssh
        
        # Clear root password
        log_info "Disabling root password"
        passwd -d root
        
        log_step "Bare system setup completed!"
        log_warn "Please now run this script as user 'rikki' to continue with system initialization:"
        log_warn "  sudo -u rikki $0"
        log_warn "Or SSH as rikki and run: $0"
        exit 0
    else
        log_error "User rikki exists but script is running as root"
        log_error "This script should be run as user 'rikki' with sudo privileges"
        log_error "Please run: sudo -u rikki $0"
        exit 1
    fi
fi

# Check if running as rikki user
if [[ "$(whoami)" != "rikki" ]]; then
    log_error "This script must be run as user 'rikki'"
    log_error "Please run: sudo -u rikki $0"
    exit 1
fi

# Update system packages
log_step "Updating system packages"
sudo apt update && sudo apt upgrade -y

# Install necessary packages
log_step "Installing necessary packages"
sudo apt install -y \
    neovim \
    git \
    ufw \
    sudo \
    openssh-server \
    curl \
    wget \
    htop \
    unzip \
    locales \
    tzdata \
    tar \
    gzip \
    xz-utils \
    bzip2 \
    zip \
    net-tools \
    iputils-ping \
    traceroute \
    telnet \
    nmap \
    tcpdump \
    rsync \
    tree \
    less \
    grep \
    sed \
    gawk \
    vim \
    nano \
    tmux \
    screen \
    lsof \
    psmisc \
    procps \
    sysstat \
    dstat \
    iotop \
    ncdu \
    logrotate \
    cron \
    at \
    bc \
    jq \
    python3 \
    python3-pip \
    build-essential \
    ca-certificates \
    gnupg \
    lsb-release \
    dnsutils \
    zsh

# Set neovim as default editor
log_step "Setting neovim as default editor"
sudo update-alternatives --install /usr/bin/editor editor /usr/bin/nvim 60
sudo update-alternatives --set editor /usr/bin/nvim

# Set zsh as default shell for rikki
log_step "Setting zsh as default shell for rikki"
sudo chsh -s /usr/bin/zsh rikki

# Install oh-my-zsh for rikki
log_step "Installing oh-my-zsh for rikki"
if sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended; then
    sed -i 's/ZSH_THEME="robbyrussell"/ZSH_THEME="avit"/' ~/.zshrc
    log_info "Oh-my-zsh installed successfully with avit theme"
else
    log_warn "Oh-my-zsh installation failed, continuing with default shell"
fi

# Configure UFW firewall
log_step "Configuring UFW firewall"
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw --force enable

log_step "Server initialization completed successfully!"
log_info "Summary of changes:"
log_info "- System packages updated and necessary tools installed (including dig and zsh)"
log_info "- Oh-my-zsh installed for rikki with avit theme"
log_info "- Neovim set as default editor"
log_info "- UFW firewall enabled (only port 22 allowed)"
log_warn "IMPORTANT: Make sure you can SSH as 'rikki' before logging out!"