#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ─── Color Definitions ─────────────────────────────────────────────────────
readonly RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m' BLUE='\033[0;34m' NC='\033[0m'

log()       { echo -e "${1}${2}${NC}"; }
log_info()    { log "$BLUE"   "$*"; }
log_warn()    { log "$YELLOW" "$*"; }
log_success() { log "$GREEN"  "$*"; }
log_error()   { log "$RED"    "$*"; }

# ─── Globals ────────────────────────────────────────────────────────────────
CONFIG_FILE='/usr/local/etc/portforward/config.ini'
SCRIPT_PATH="$(realpath "$0")"
SERVICE_NAME='portforward.service'
SERVICE_PATH="/etc/systemd/system/$SERVICE_NAME"
declare -A FORWARD_MAP SUCCESS_MAP FAILED_MAP

# ─── Usage ─────────────────────────────────────────────────────────────────
show_help() {
  cat <<-EOF
Usage: $(basename "$0") <command>

Commands:
  help, -h           Show this help message
  install            Install systemd service & init config
  remove-service     Disable & remove systemd service
  forward            Apply port-forwarding rules
  cleanup            Remove port-forwarding rules
EOF
}

# ─── Environment Checks ─────────────────────────────────────────────────────
require_root() {
  if [[ $EUID -ne 0 ]]; then
    log_error "Please run as root or via sudo."
    exit 1
  fi
}

require_commands() {
  local missing=()
  for cmd; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "Missing required commands: ${missing[*]}"
    exit 1
  fi
}

# ─── Sysctl Helpers ─────────────────────────────────────────────────────────
enable_sysctl() {
  local key=$1 desc=$2
  local current_value
  current_value=$(sysctl -n "$key" || echo "0")

  if [[ "$current_value" -ne 1 ]]; then
    log_warn "Enabling $desc"
    sysctl -w "$key=1" &>/dev/null
  else
    log_success "$desc already enabled"
  fi
}

# ─── Network Detection ─────────────────────────────────────────────────────
get_interface_and_ips() {
  DEFAULT_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '/dev/ {print $5; exit}')
  if [[ -z $DEFAULT_IFACE ]]; then
    log_error "Cannot detect default interface."
    exit 1
  fi

  LOCAL_IP4=$(ip -4 addr show dev "$DEFAULT_IFACE" scope global 2>/dev/null \
    | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)
  LOCAL_IP6=$(ip -6 addr show dev "$DEFAULT_IFACE" scope global 2>/dev/null \
    | awk '/inet6 /{print $2}' | cut -d/ -f1 | head -n1 || echo "")

  log_info "Interface: $DEFAULT_IFACE"
  log_info "IPv4: $LOCAL_IP4"
  if [[ -n $LOCAL_IP6 ]]; then
    log_info "IPv6: $LOCAL_IP6"
  fi
}

# ─── Service Management ────────────────────────────────────────────────────
install_service() {
  if [[ ! -f $CONFIG_FILE ]]; then
    log_warn "Creating default config at $CONFIG_FILE"
    mkdir -p "$(dirname "$CONFIG_FILE")"
    cat >"$CONFIG_FILE" <<-'EOF'
# <local_port>=<proto>://<dest_ip>:<dest_port>
# omit proto to forward both tcp+udp
# IPv6 example:
# 9090=[2001:db8::1]:6000
# tcp example:
# 8088=tcp://1.2.3.4:5000
EOF
    log_success "Default config created"
  fi

  cat >"$SERVICE_PATH" <<-EOF
[Unit]
Description=Port Forwarding Service
After=network.target

[Service]
Type=simple
ExecStart=$SCRIPT_PATH forward
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME"
  log_success "Service installed and enabled"
}

remove_service() {
  if systemctl is-enabled "$SERVICE_NAME" &>/dev/null; then
    systemctl disable "$SERVICE_NAME" &>/dev/null
  fi
  if [[ -f "$SERVICE_PATH" ]]; then
    rm -f "$SERVICE_PATH"
  fi
  systemctl daemon-reload
  log_success "Service removed"
}

# ─── Config Parsing ─────────────────────────────────────────────────────────
read_config() {
  if [[ ! -f $CONFIG_FILE ]]; then
    log_error "Config not found: $CONFIG_FILE"
    exit 1
  fi

  FORWARD_MAP=()
  while IFS='=' read -r key val; do
    key=${key//[[:space:]]/}
    val=${val//[[:space:]]/}
    if [[ -n $key && $key != \#* && -n $val ]]; then
      FORWARD_MAP["$key"]="$val"
    fi
  done <"$CONFIG_FILE"
}

# ─── IPTables Helpers ──────────────────────────────────────────────────────
add_rule() {
  local ipt=$1 table=$2 chain=$3 desc=$4
  shift 4

  if ! "$ipt" -t "$table" -C "$chain" "$@" &>/dev/null; then
    log_success "  + $desc"
    "$ipt" -t "$table" -A "$chain" "$@"
  else
    log_warn "  = $desc exists"
  fi
}

del_rule() {
  local ipt=$1 table=$2 chain=$3 desc=$4
  shift 4

  if "$ipt" -t "$table" -C "$chain" "$@" &>/dev/null; then
    if "$ipt" -t "$table" -D "$chain" "$@"; then
      log_success "  - Removed $desc"
    else
      log_error "  ! Failed remove $desc"
    fi
  else
    log_warn "  = $desc not present"
  fi
}

# ─── Port-In-Use Check ──────────────────────────────────────────────────────
port_in_use() {
  ss -ltnup 2>/dev/null | grep -q ":$1 " || return 1
}

# ─── Core Loop (forward|cleanup) ────────────────────────────────────────────
manage_rules() {
  local mode=$1
  read_config
  get_interface_and_ips
  enable_sysctl net.ipv4.ip_forward "IPv4 forwarding"
  enable_sysctl net.ipv6.conf.all.forwarding "IPv6 forwarding"

  SUCCESS_MAP=()
  FAILED_MAP=()

  for lp in "${!FORWARD_MAP[@]}"; do
    raw=${FORWARD_MAP[$lp]}

    if [[ $raw == *"://"* ]]; then
      proto=${raw%%://*}
      rest=${raw#*://}
      protocols=("$proto")
    else
      rest=$raw
      protocols=(tcp udp)
    fi

    if [[ $rest =~ ^\[(.+)\]:([0-9]+)$ ]]; then
      host=${BASH_REMATCH[1]}
      port=${BASH_REMATCH[2]}
      is6=1
    else
      host=${rest%%:*}
      port=${rest##*:}
      is6=0
      [[ $host == *:* ]] && is6=1
    fi

    for p in "${protocols[@]}"; do
      echo
      log_info "${mode^^} ${p^^} $lp → $host:$port"

      if [[ $mode == forward ]]; then
        if port_in_use "$lp"; then
          log_warn "  ! local port $lp busy, skipping"
          FAILED_MAP["$lp/$p"]=$raw
          continue
        fi
        add_rule iptables nat PREROUTING "DNAT $p $lp" -p "$p" --dport "$lp" -j DNAT --to-destination "$host:$port"
        add_rule iptables nat POSTROUTING "SNAT $p $lp" -d "$host/32" -p "$p" --dport "$port" -j SNAT --to-source "$LOCAL_IP4"
        if [[ $is6 -eq 1 && -n $LOCAL_IP6 ]]; then
          add_rule ip6tables nat PREROUTING "DNAT6 $p $lp" -p "$p" --dport "$lp" -j DNAT --to-destination "[$host]:$port"
          add_rule ip6tables nat POSTROUTING "SNAT6 $p $lp" -d "$host/128" -p "$p" --dport "$port" -j SNAT --to-source "$LOCAL_IP6"
        fi
        SUCCESS_MAP["$lp/$p"]=$raw
      else
        del_rule iptables nat PREROUTING "DNAT $p $lp" -p "$p" --dport "$lp" -j DNAT --to-destination "$host:$port"
        del_rule iptables nat POSTROUTING "SNAT $p $lp" -d "$host/32" -p "$p" --dport "$port" -j SNAT --to-source "$LOCAL_IP4"
        if [[ $is6 -eq 1 && -n $LOCAL_IP6 ]]; then
          del_rule ip6tables nat PREROUTING "DNAT6 $p $lp" -p "$p" --dport "$lp" -j DNAT --to-destination "[$host]:$port"
          del_rule ip6tables nat POSTROUTING "SNAT6 $p $lp" -d "$host/128" -p "$p" --dport "$port" -j SNAT --to-source "$LOCAL_IP6"
        fi
      fi
    done
  done

  echo
  log_info "Summary:"
  if [[ ${#SUCCESS_MAP[@]} -gt 0 ]]; then
    log_success "  Successes:"
    for k in "${!SUCCESS_MAP[@]}"; do
      echo "    - $k → ${SUCCESS_MAP[$k]}"
    done
  fi
  if [[ ${#FAILED_MAP[@]} -gt 0 ]]; then
    log_error "  Failures:"
    for k in "${!FAILED_MAP[@]}"; do
      echo "    - $k → ${FAILED_MAP[$k]}"
    done
  fi
}

# ─── Main ──────────────────────────────────────────────────────────────────
main() {
  require_root
  require_commands iptables ip6tables ss ip realpath systemctl

  local cmd="${1:-help}"
  case "$cmd" in
    help|-h|--help)    show_help ;;
    install)           install_service ;;
    remove-service)    remove_service ;;
    forward)           manage_rules forward ;;
    cleanup)           manage_rules cleanup ;;
    *)                 show_help; exit 1 ;;
  esac
}

main "$@"
