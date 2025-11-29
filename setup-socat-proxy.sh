#!/usr/bin/env bash
set -euo pipefail

# socat 端口转发管理脚本
# 支持：
#   1) IPv6 入 -> IPv4 出 (v6to4)
#   2) IPv4 入 -> IPv6 出 (v4to6)
#
# 用法:
#   bash setup-socat-proxy.sh install
#   bash setup-socat-proxy.sh remove
#   bash setup-socat-proxy.sh list
#   bash setup-socat-proxy.sh restart

require_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "✖ 请用 root 运行：sudo bash $0 ..." >&2
    exit 1
  fi
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

install_socat() {
  if has_cmd socat; then
    echo "✔ socat 已安装：$(command -v socat)"
    return
  fi
  echo "→ 正在安装 socat ..."
  if command -v apt-get >/dev/null 2>&1; then
    apt-get update -y && apt-get install -y socat
  elif command -v yum >/dev/null 2>&1; then
    yum install -y socat
  elif command -v dnf >/dev/null 2>&1; then
    dnf install -y socat
  else
    echo "✖ 未找到可用包管理器，请手动安装 socat" >&2
    exit 1
  fi
}

valid_port() {
  local p="$1"
  [[ "$p" =~ ^[0-9]+$ ]] && (( p > 0 && p <= 65535 ))
}

check_port_free() {
  local port="$1"
  if ss -tuln | grep -q "[:\]]$port "; then
    return 1
  fi
  return 0
}

parse_proto_input() {
  local input="${1:-tcp}"
  input="${input,,}"
  declare -ga PROTO_LIST

  case "$input" in
    1|"tcp")
      PROTO_LIST=("TCP")
      ;;
    2|"udp")
      PROTO_LIST=("UDP")
      ;;
    3|"tcp+udp"|"tcp/udp"|"udp/tcp"|"all")
      PROTO_LIST=("TCP" "UDP")
      ;;
    *)
      echo "✖ 协议输入无效。可选：1/tcp, 2/udp, 3/tcp+udp"
      return 1
      ;;
  esac
}

create_service() {
  local mode="$1" proto="$2" lport="$3" rhost="$4" rport="$5"
  local svc="socat-${mode,,}-${proto,,}-${lport}.service"
  local svcpath="/etc/systemd/system/$svc"

  local listen=""
  case "${mode}_${proto}" in
    v6to4_TCP) listen="TCP6-LISTEN:${lport},bind=[::],reuseaddr,fork" ;;
    v6to4_UDP) listen="UDP6-LISTEN:${lport},bind=[::],reuseaddr,fork" ;;
    v4to6_TCP) listen="TCP-LISTEN:${lport},bind=0.0.0.0,reuseaddr,fork" ;;
    v4to6_UDP) listen="UDP-LISTEN:${lport},bind=0.0.0.0,reuseaddr,fork" ;;
  esac

  local target_host="$rhost"
  if [[ "$rhost" == *:* && "$rhost" != \[*\] ]]; then
    target_host="[$rhost]"
  fi

  local target=""
  case "${mode}_${proto}" in
    v6to4_TCP) target="TCP4:${rhost}:${rport}" ;;
    v6to4_UDP) target="UDP4:${rhost}:${rport}" ;;
    v4to6_TCP) target="TCP6:${target_host}:${rport}" ;;
    v4to6_UDP) target="UDP6:${target_host}:${rport}" ;;
  esac

  cat >"$svcpath" <<EOF
[Unit]
Description=socat ${mode} ${proto} ${lport} -> ${rhost}:${rport}
After=network-online.target
Wants=network-online.target

[Service]
ExecStart=/usr/bin/socat -dd -v $listen $target
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable --now "$svc"
}

remove_service() {
  local mode="$1" proto="$2" lport="$3"
  local svc="socat-${mode,,}-${proto,,}-${lport}.service"
  systemctl stop "$svc" || true
  systemctl disable "$svc" || true
  rm -f "/etc/systemd/system/$svc"
  systemctl daemon-reload
}

cmd="${1:-}"

case "$cmd" in
  install)
    require_root
    install_socat

    echo "方向: 1) v6→v4  2) v4→v6"
    read -rp "选择方向 (1/2, 默认1): " mode_sel
    mode_sel=${mode_sel:-1}
    [[ "$mode_sel" == "1" ]] && mode="v6to4" || mode="v4to6"

    echo "协议: 1)TCP 2)UDP 3)TCP+UDP"
    read -rp "选择协议 (默认1): " proto_input
    proto_input=${proto_input:-1}
    parse_proto_input "$proto_input"

    read -rp "本地监听端口: " lport
    check_port_free "$lport"

    if [[ "$mode" == "v6to4" ]]; then
      read -rp "远端 IPv4: " rhost
    else
      read -rp "远端 IPv6: " rhost
    fi

    read -rp "远端端口: " rport

    for proto in "${PROTO_LIST[@]}"; do
      create_service "$mode" "$proto" "$lport" "$rhost" "$rport"
    done
    ;;
  remove)
    require_root
    read -rp "方向 (v6to4/v4to6): " mode
    read -rp "协议 (1/2/3): " proto_input
    parse_proto_input "$proto_input"
    read -rp "本地监听端口: " lport

    for proto in "${PROTO_LIST[@]}"; do
      remove_service "$mode" "$proto" "$lport"
    done
    ;;
  list)
    systemctl list-units --type=service | grep socat- || echo "No services"
    ;;
  restart)
    require_root
    read -rp "方向 (v6to4/v4to6): " mode
    read -rp "协议 (1/2/3): " proto_input
    parse_proto_input "$proto_input"
    read -rp "端口: " lport

    for proto in "${PROTO_LIST[@]}"; do
      systemctl restart "socat-${mode,,}-${proto,,}-${lport}.service"
    done
    ;;
  *)
    echo "用法: $0 {install|remove|list|restart}"
    ;;
esac
