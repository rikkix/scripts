# Debian Server Initialization Scripts

⚠️ **CRITICAL WARNING: These scripts are DESTRUCTIVE and will COMPLETELY WIPE your system!** ⚠️

## 🚨 DANGER - READ BEFORE USE 🚨

**DO NOT RUN THESE SCRIPTS unless you:**
- Fully understand what they do
- Have tested them in a safe environment first
- Are prepared to lose ALL data on the target system
- Have proper backups of any important data
- Are working on a system you can afford to completely reinstall

**These scripts are designed for experienced system administrators who understand the risks involved.**

## Overview

This repository contains two complementary scripts for setting up Debian 12 (Bookworm) servers:

### 1. `reinstall.sh` - OS Reinstaller (DESTRUCTIVE)
**⚠️ THIS WILL COMPLETELY WIPE AND REINSTALL YOUR OPERATING SYSTEM**

- Automatically reinstalls Debian 12 via network installation
- **DESTROYS ALL EXISTING DATA** on the target disk
- Creates user 'rikki' with SSH key authentication from GitHub
- Configures secure SSH settings (no password auth, no root login)
- Sets timezone to UTC and locale to en_US.UTF-8
- Installs minimal packages: openssh-server, curl, wget, sudo, neovim

### 2. `init.sh` - Post-Installation Setup
**Safer but still requires caution**

- Dual-mode operation:
  - **Root mode**: Sets up basic user and SSH on bare systems
  - **User mode**: Comprehensive system configuration as user 'rikki'
- Installs comprehensive development and administration tools
- Configures zsh with oh-my-zsh and avit theme
- Sets up neovim as default editor
- Configures UFW firewall with secure defaults

## Prerequisites

### For `reinstall.sh`:
- Must be run as root
- Requires network connectivity
- System must have GRUB bootloader
- **Will completely destroy existing system**

### For `init.sh`:
- Can be run as root (bare system) or as user 'rikki'
- Requires sudo privileges
- Network connectivity for package downloads

## Usage

### STEP 1: OS Installation (DESTRUCTIVE)
```bash
# ⚠️ WARNING: This will WIPE your entire system!
# Only run this if you want to completely reinstall the OS
sudo ./reinstall.sh
```

This will:
1. Download Debian installer files
2. Configure GRUB to boot the installer
3. **REBOOT and AUTOMATICALLY REINSTALL the entire OS**
4. Create user 'rikki' with your SSH keys

### STEP 2: System Configuration
After the system reboots and Debian is installed:

```bash
# SSH as the rikki user and run:
./init.sh
```

Or if running on a bare system as root:
```bash
# This will set up the user, then ask you to re-run as rikki
sudo ./init.sh
```

## What Gets Installed

### Minimal (via reinstall.sh):
- openssh-server, curl, wget, sudo, neovim

### Full (via init.sh):
- Development tools: git, python3, build-essential
- System utilities: htop, tmux, screen, tree, rsync
- Network tools: nmap, tcpdump, traceroute, telnet
- Compression tools: tar, gzip, zip, unzip, xz-utils
- Text editors: neovim (default), vim, nano
- Shell: zsh with oh-my-zsh and avit theme
- Monitoring: sysstat, iotop, lsof
- And many more...

## Security Features

- SSH key-only authentication (passwords disabled)
- Root login disabled
- User 'rikki' with passwordless sudo
- UFW firewall enabled (only SSH port 22 allowed)
- Root password cleared

## Customization

### SSH Keys
The scripts fetch SSH keys from `https://github.com/rikkix.keys`. To use your own keys:
1. Upload your public keys to your GitHub account
2. Modify the GitHub username in both scripts

### User Account
To use a different username:
1. Update the username in both scripts
2. Update the SSH key URL accordingly
3. Modify sudoers configuration

### Package Selection
Edit the package list in `init.sh` to add/remove software as needed.

## Troubleshooting

### If reinstall.sh fails:
- Check network connectivity
- Verify GRUB configuration exists
- Ensure running as root
- Check available disk space

### If init.sh fails:
- Verify you have sudo privileges
- Check network connectivity for downloads
- Ensure SSH keys are accessible from GitHub

### System won't boot after reinstall:
- Boot from rescue media
- Check GRUB configuration
- Verify disk partitioning completed successfully

## Testing

**NEVER test these scripts on production systems!**

Recommended testing approach:
1. Use virtual machines (VirtualBox, VMware, etc.)
2. Test on disposable cloud instances
3. Verify functionality in isolated environments
4. Only use on production after thorough testing

## Support

These scripts are provided as-is for educational and personal use. 

**Use at your own risk. The authors are not responsible for any data loss or system damage.**

## License

These scripts are personal tools. Use responsibly and at your own risk.

---

## 🚨 FINAL WARNING 🚨

**These scripts will PERMANENTLY DESTROY data and COMPLETELY REINSTALL your operating system. Make sure you understand the consequences before running them. Always test in a safe environment first!**