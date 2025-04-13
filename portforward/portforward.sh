#!/bin/bash
set -euo pipefail

# ─── Color Definitions ─────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
NC='\033[0m'

CONFIG_FILE="/usr/local/etc/portforward/config.ini"
declare -A FORWARD_MAP
declare -A SUCCESS_MAP
declare -A FAILED_MAP

# ─── Logging ───────────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}$*${NC}"; }
log_warn()    { echo -e "${YELLOW}$*${NC}"; }
log_success() { echo -e "${GREEN}$*${NC}"; }
log_error()   { echo -e "${RED}$*${NC}"; }

# ─── Sudo Check ────────────────────────────────────────────────────────────
check_sudo() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run with sudo or as root."
        exit 1
    fi
}

# ─── Dependency Check ──────────────────────────────────────────────────────
check_command() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then
            log_error "$cmd is not installed."
            exit 1
        fi
    done
}

# ─── Enable IPv4 Forwarding ────────────────────────────────────────────────
enable_ip_forwarding() {
    if [[ "$(sysctl -n net.ipv4.ip_forward)" -ne 1 ]]; then
        log_warn "Enabling IPv4 forwarding"
        sysctl -w net.ipv4.ip_forward=1 > /dev/null
    else
        log_success "IPv4 forwarding is already enabled"
    fi
}

# ─── Get Interface & IP ────────────────────────────────────────────────────
get_interface_and_ip() {
    DEFAULT_IFACE=$(ip route | awk '/^default/ {print $5}')
    [[ -z "$DEFAULT_IFACE" ]] && { log_error "Cannot find default interface"; exit 1; }

    LOCAL_IP=$(ip -4 addr show "$DEFAULT_IFACE" | awk '/inet / {print $2}' | cut -d/ -f1)
    [[ -z "$LOCAL_IP" ]] && { log_error "Cannot find local IP"; exit 1; }

    log_info "Default interface: $DEFAULT_IFACE"
    log_info "Local IP: $LOCAL_IP"
}

# ─── Load Configuration ────────────────────────────────────────────────────
read_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log_warn "Creating config file at $CONFIG_FILE"
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat <<EOF > "$CONFIG_FILE"
# Format: <local_port>=<proto>://<destination_ip>:<destination_port>
#8088=tcp://1.2.4.8:5000
EOF
        log_warn "Edit the config file and re-run the script."
        exit 1
    fi

    while IFS='=' read -r raw_key raw_value; do
        key=$(echo "$raw_key" | xargs)
        value=$(echo "$raw_value" | xargs)
        [[ -z "$key" || "$key" =~ ^#.*$ || -z "$value" ]] && continue
        FORWARD_MAP["$key"]="$value"
    done < "$CONFIG_FILE"
}

# ─── Iptables Rule Handling ────────────────────────────────────────────────
add_iptables_rule_if_missing() {
    local table=$1 chain=$2 desc=$3; shift 3
    if ! iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
        log_success "  - Adding $desc"
        iptables -t "$table" -A "$chain" "$@"
    else
        log_warn "  - $desc already exists"
    fi
}

delete_iptables_rule_if_exists() {
    local table=$1 chain=$2 desc=$3; shift 3
    if iptables -t "$table" -C "$chain" "$@" 2>/dev/null; then
        if iptables -t "$table" -D "$chain" "$@" 2>/dev/null; then
            log_success "  - Removed $desc"
            return 0
        else
            log_error "  - Failed to remove $desc"
        fi
    else
        log_warn "  - $desc not found"
    fi
    return 1
}

# ─── Port In Use Detection ─────────────────────────────────────────────────
is_port_in_use() {
    local port=$1
    ss -lntup 2>/dev/null | awk -v p=":$port" '$0 ~ p && $1 != "Netid"' | grep -q .
}

# ─── Apply Forwarding ──────────────────────────────────────────────────────
setup_forwarding() {
    for local_port in "${!FORWARD_MAP[@]}"; do
        dest="${FORWARD_MAP[$local_port]}"
        proto="${dest%%://*}"
        rest="${dest#*://}"
        host="${rest%%:*}"
        port="${rest##*:}"

        echo
        log_info "FORWARD ${proto^^} $local_port -> $host:$port"

        if is_port_in_use "$local_port"; then
            log_warn "  - Port $local_port is in use. Skipping."
            FAILED_MAP["$local_port"]="$dest"
            continue
        fi

        add_iptables_rule_if_missing nat PREROUTING \
            "PREROUTING rule" -p "$proto" --dport "$local_port" -j DNAT --to "$host:$port"

        add_iptables_rule_if_missing nat POSTROUTING \
            "POSTROUTING rule" -d "$host/32" -p "$proto" --dport "$port" -j SNAT --to-source "$LOCAL_IP"

        SUCCESS_MAP["$local_port"]="$dest"
    done
}

# ─── Remove Forwarding ─────────────────────────────────────────────────────
cleanup_forwarding() {
    for local_port in "${!FORWARD_MAP[@]}"; do
        dest="${FORWARD_MAP[$local_port]}"
        proto="${dest%%://*}"
        rest="${dest#*://}"
        host="${rest%%:*}"
        port="${rest##*:}"

        echo
        log_info "CLEANUP ${proto^^} $local_port -> $host:$port"

        deleted=0

        delete_iptables_rule_if_exists nat PREROUTING \
            "PREROUTING rule" -p "$proto" --dport "$local_port" -j DNAT --to "$host:$port" && deleted=1

        delete_iptables_rule_if_exists nat POSTROUTING \
            "POSTROUTING rule" -d "$host/32" -p "$proto" --dport "$port" -j SNAT --to-source "$LOCAL_IP" && deleted=1

        ((deleted)) && SUCCESS_MAP["$local_port"]="$dest" || FAILED_MAP["$local_port"]="$dest"
    done
}

# ─── Print Summary ─────────────────────────────────────────────────────────
print_summary() {
    echo
    log_info "Summary:"
    log_success "Successful:"
    for port in "${!SUCCESS_MAP[@]}"; do
        echo "  - $port -> ${SUCCESS_MAP[$port]}"
    done
    log_error "Failed:"
    for port in "${!FAILED_MAP[@]}"; do
        echo "  - $port -> ${FAILED_MAP[$port]}"
    done
}

# ─── Main ──────────────────────────────────────────────────────────────────
main() {
    check_sudo
    check_command iptables ip ss
    read_config
    get_interface_and_ip

    MODE="setup"
    [[ "${1:-}" == "--cleanup" ]] && MODE="cleanup"

    [[ "$MODE" == "setup" ]] && enable_ip_forwarding && setup_forwarding || cleanup_forwarding
    print_summary
}

main "$@"
