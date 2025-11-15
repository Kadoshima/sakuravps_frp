#!/usr/bin/env bash
set -euo pipefail

# Install and configure frpc on Ubuntu
# - Defaults: device=test, localPort=8000, server=kimulabfrp.jp:7000 (wss)
# - Requires: -t|--token to match frps token
# - Optional: --proxy-url to connect via HTTP/HTTPS/SOCKS5 proxy (e.g., http://proxy:3128)

FRP_VER="0.61.0"
DEVICE="test"
LOCAL_PORT="8000"
SERVER_ADDR="kimulabfrp.jp"
SERVER_PORT="7000"
TOKEN=""
PROXY_URL=""

usage() {
  echo "Usage: $0 [-d device_id] [-p local_port] [-s server_addr] [-P server_port] -t token [--proxy-url URL]"
  echo "  Defaults: device=test, local_port=8000, server_addr=kimulabfrp.jp, server_port=7000"
  echo "  Example: sudo bash $0 -d test -p 8000 -t 'YOUR_FRP_TOKEN'"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2;;
    -p|--local-port) LOCAL_PORT="$2"; shift 2;;
    -s|--server-addr) SERVER_ADDR="$2"; shift 2;;
    -P|--server-port) SERVER_PORT="$2"; shift 2;;
    -t|--token) TOKEN="$2"; shift 2;;
    --proxy-url) PROXY_URL="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 1;;
  esac
done

if [[ -z "$TOKEN" ]]; then
  echo "[ERR] token is required (-t)"
  usage
  exit 1
fi

arch_map() {
  local uarch="$(uname -m)"
  case "$uarch" in
    x86_64) echo "amd64";;
    aarch64|arm64) echo "arm64";;
    armv7l|armv6l) echo "arm";;
    *) echo "unknown";;
  esac
}

ARCH="$(arch_map)"
if [[ "$ARCH" == "unknown" ]]; then
  echo "[ERR] Unsupported architecture: $(uname -m)"; exit 2
fi

echo "== Install frpc v${FRP_VER} (${ARCH}) =="
TMPDIR="$(mktemp -d)"
pushd "$TMPDIR" >/dev/null
TARBALL="frp_${FRP_VER}_linux_${ARCH}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/v${FRP_VER}/${TARBALL}"
curl -fsSL -o "$TARBALL" "$URL"
tar xfz "$TARBALL"
sudo install -m 0755 "frp_${FRP_VER}_linux_${ARCH}/frpc" /usr/local/bin/frpc
popd >/dev/null
rm -rf "$TMPDIR"

echo "== Write /etc/frp/frpc.toml =="
sudo mkdir -p /etc/frp
CFG_TMP="$(mktemp)"
cat > "$CFG_TMP" <<CFG
serverAddr = "${SERVER_ADDR}"
serverPort = ${SERVER_PORT}
protocol   = "wss"

[auth]
method = "token"
token  = "${TOKEN}"

[transport]
# Uncomment to tweak keepalive if必要
# tcpKeepaliveInterval = 30
CFG

if [[ -n "$PROXY_URL" ]]; then
  cat >> "$CFG_TMP" <<CFG
  proxyURL = "${PROXY_URL}"
CFG
fi

cat >> "$CFG_TMP" <<CFG

[[proxies]]
name      = "${DEVICE}"
type      = "http"
localPort = ${LOCAL_PORT}
subdomain = "${DEVICE}"
CFG

sudo mv "$CFG_TMP" /etc/frp/frpc.toml
sudo chmod 0640 /etc/frp/frpc.toml

echo "== Write systemd unit =="
UNIT_TMP="$(mktemp)"
cat > "$UNIT_TMP" <<'UNIT'
[Unit]
Description=frpc (Fast Reverse Proxy client)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frpc -c /etc/frp/frpc.toml
Restart=always
RestartSec=5s
User=root
AmbientCapabilities=
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
UNIT

sudo mv "$UNIT_TMP" /etc/systemd/system/frpc.service

echo "== Enable & Start =="
sudo systemctl daemon-reload
sudo systemctl enable --now frpc.service
sleep 2
sudo systemctl --no-pager --full status frpc.service || true

echo "== Quick checks =="
echo "- On server: docker logs frps --since 5m | grep -i 'client login'"
echo "- From anywhere: curl -I http://${DEVICE}.${SERVER_ADDR}"
echo "If 404, ensure local service on port ${LOCAL_PORT} is running and frpc is connected."

echo "Done."

