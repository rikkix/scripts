# 🔀 PortForward Script

A lightweight Bash script to manage **TCP/UDP port forwarding** using `iptables`.  
Supports persistent configuration, rule verification, and optional cleanup of NAT rules.


## ✨ Features

- ✅ Forward TCP or UDP ports to external/internal IPs
- ✅ Simple config file: `port=protocol://ip:port`
- ✅ Automatic creation of a config template if missing
- ✅ `--cleanup` mode to remove previously added rules
- ✅ Colorful, human-readable logging
- ✅ Modular and maintainable script structure
- ✅ Requires only: `iptables`, `ip`, `ss`, and `bash`


## 📦 Installation

Run this one-liner to install the script system-wide to `/usr/local/bin/portforward`:

```bash
sudo curl -o /usr/local/bin/portforward https://github.com/rikkix/scripts/raw/main/portforward/portforward.sh && \
sudo chmod +x /usr/local/bin/portforward
```

Then you can use it directly with:

```bash
sudo portforward         # Apply forwarding rules
sudo portforward --cleanup   # Remove rules
```

## 🛠️ Usage

### 🔧 Forwarding Mode

```bash
sudo portforward
```

- 	Reads mappings from /usr/local/etc/portforward/config.ini
- 	Adds PREROUTING and POSTROUTING rules via iptables
- 	Automatically enables net.ipv4.ip_forward if needed

### 🧹 Cleanup Mode

```bash
sudo portforward --cleanup
```

- Removes the same PREROUTING and POSTROUTING rules defined in the config


## 📝 Configuration Format

The config file lives at:

```
/usr/local/etc/portforward/config.ini
```

If the file doesn’t exist, the script will create a template automatically.

### 📄 Example Config:

```
# Format: local_port=protocol://target_ip:target_port

# Forward local TCP 8898 to external address
8898=tcp://13.17.1.12:8898

# Forward UDP port 5000 to another machine
5000=udp://10.0.0.20:5001
```

- Comments and blank lines are ignored
- Whitespace around `=` is allowed


## ⚙️ Dependencies

Make sure the following tools are installed:
- iptables
- ip
- ss
- bash (version 4+ for associative arrays)

## 📄 License

MIT License © 2025 @rikkix
