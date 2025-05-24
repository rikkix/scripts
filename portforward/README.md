# 🔀 PortForward Script

A lightweight Bash script to manage **TCP/UDP port forwarding** using `iptables`.  
Supports persistent configuration, rule verification, and optional cleanup of NAT rules.


## ✨ Features

- ✅ Forward TCP or UDP ports to external/internal IPs
- ✅ Simple config file: `port=protocol://ip:port`
- ✅ Automatic creation of a config template if missing
- ✅ Colorful, human-readable logging
- ✅ Modular and maintainable script structure
- ✅ Requires only: `iptables`, `ip`, `ss`, and `bash`


## 📦 Installation

Run this one-liner to install the script system-wide to `/usr/local/bin/portforward`:

```bash
sudo curl -L -o /usr/local/bin/portforward https://cdn.jsdelivr.net/gh/rikkix/scripts@release/portforward.sh && \
sudo chmod +x /usr/local/bin/portforward
```

Then you can use it directly with:

```bash
sudo portforward         # Show help and usage
```

## ⚙️ Dependencies

Make sure the following tools are installed:
- iptables
- ip
- ss
- bash (version 4+ for associative arrays)

## 📄 License

MIT License © 2025 @rikkix
