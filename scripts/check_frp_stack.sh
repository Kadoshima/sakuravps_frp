#!/usr/bin/env bash
set -euo pipefail

# Quick health check for FRP + Caddy stack
# - Reads values from a tfvars file (default: terraform/tftest.tfvars)
# - Verifies remote containers, frps config/logs, Caddy config, HTTP endpoints, and port 7000 reachability

TFVARS="${TFVARS:-terraform/tftest.tfvars}"
SSH_USER=""
VPS_IP=""
DOMAIN=""
IDENTITY_FILE=""

usage() {
  cat <<USAGE
Usage: $0 [-f tfvars] [-u ssh_user] [-H vps_ip] [-d domain] [-i identity_file]
  -f  Path to tfvars (default: terraform/tftest.tfvars)
  -u  SSH user (overrides tfvars)
  -H  VPS IP (overrides tfvars)
  -d  Domain (overrides tfvars)
  -i  SSH identity file (overrides tfvars private_key_path)

Examples:
  bash scripts/check_frp_stack.sh
  bash scripts/check_frp_stack.sh -f terraform/tftest.tfvars
USAGE
}

while getopts ":f:u:H:d:i:h" opt; do
  case "${opt}" in
    f) TFVARS="$OPTARG" ;;
    u) SSH_USER="$OPTARG" ;;
    H) VPS_IP="$OPTARG" ;;
    d) DOMAIN="$OPTARG" ;;
    i) IDENTITY_FILE="$OPTARG" ;;
    h) usage; exit 0 ;;
    *) usage; exit 1 ;;
  esac
done

parse_tfvar() {
  local key="$1" file="$2" line val
  [[ -f "$file" ]] || return 1
  line=$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$file" | tail -n1 || true)
  [[ -n "$line" ]] || return 1
  line="${line%%#*}"
  val=$(echo "$line" | sed -E 's/^[^=]+=[[:space:]]*//')
  val=$(echo "$val" | sed -E 's/^[[:space:]]*"(.*)"[[:space:]]*$/\1/' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//')
  echo "$val"
}

# Fill from tfvars as needed
[[ -n "$SSH_USER" ]]      || SSH_USER=$(parse_tfvar ssh_user "$TFVARS" || true)
[[ -n "$VPS_IP" ]]        || VPS_IP=$(parse_tfvar vps_ip "$TFVARS" || true)
[[ -n "$DOMAIN" ]]        || DOMAIN=$(parse_tfvar domain "$TFVARS" || true)
[[ -n "$IDENTITY_FILE" ]] || IDENTITY_FILE=$(parse_tfvar private_key_path "$TFVARS" || true)

# Expand ~ in identity file path
if [[ -n "${IDENTITY_FILE:-}" ]]; then
  IDENTITY_FILE=$(eval echo "$IDENTITY_FILE")
fi

: "${SSH_USER:?Missing ssh_user. Provide via -u or tfvars.}"
: "${VPS_IP:?Missing vps_ip. Provide via -H or tfvars.}"
: "${DOMAIN:?Missing domain. Provide via -d or tfvars.}"

SSH_BASE=(ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o ConnectTimeout=5)
if [[ -n "${IDENTITY_FILE:-}" ]]; then SSH_BASE+=(-i "$IDENTITY_FILE"); fi

ok()   { echo "[OK]  $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERR] $*"; }

FAILED=0

echo "== Remote containers =="
if "${SSH_BASE[@]}" "$SSH_USER@$VPS_IP" "docker ps --format '{{.Names}} {{.Status}}'"; then
  ok "SSH connectivity and Docker reachable"
else
  err "Cannot connect to VPS via SSH or Docker not available"
  exit 2
fi

echo "== frps config snippet =="
if "${SSH_BASE[@]}" "$SSH_USER@$VPS_IP" \
   "docker exec frps sh -c 'grep -nE "^\\[transport\\]|tls\\s*=\\s*\\{.*\\}" /etc/frp/frps.toml | sed -n "1,3p"'"; then
  ok "frps.toml readable"
else
  warn "Cannot read /etc/frp/frps.toml inside frps container"
fi

echo "== frps recent logs (check for unknown fields) =="
if "${SSH_BASE[@]}" "$SSH_USER@$VPS_IP" "docker logs frps --since 10m 2>&1 | grep -i 'unknown field' -m 1 -n || true" | grep -qi 'unknown field'; then
  err "Found 'unknown field' in recent frps logs"
  FAILED=1
else
  ok "No 'unknown field' found in last 10 minutes"
fi

echo "== Caddy config validate =="
if "${SSH_BASE[@]}" "$SSH_USER@$VPS_IP" "docker exec caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1"; then
  ok "Caddyfile validates"
else
  warn "'caddy validate' failed or unsupported; continuing"
fi

echo "== HTTP checks =="
ROOT_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$DOMAIN/")
if [[ "$ROOT_CODE" == "200" ]]; then
  ok "Root http://$DOMAIN returns 200"
else
  err "Root http://$DOMAIN returned $ROOT_CODE (expected 200)"
  FAILED=1
fi

ROOT_BODY=$(curl -s "http://$DOMAIN/" || true)
if echo "$ROOT_BODY" | grep -q "FRP edge is running"; then
  ok "Root body contains health message"
else
  warn "Root body does not contain expected message"
fi

RAND_SUB="check$(LC_ALL=C tr -dc a-z0-9 </dev/urandom | head -c 6)"
SUB_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://$RAND_SUB.$DOMAIN/" || echo "000")
if [[ "$SUB_CODE" == "404" ]]; then
  ok "$RAND_SUB.$DOMAIN returns 404 (no active route)"
elif [[ "$SUB_CODE" =~ ^2|3 ]]; then
  ok "$RAND_SUB.$DOMAIN returns $SUB_CODE (route active)"
else
  warn "$RAND_SUB.$DOMAIN returned $SUB_CODE"
fi

echo "== Port 7000 (frps) reachability =="
if command -v nc >/dev/null 2>&1; then
  if nc -vz -G 3 "$DOMAIN" 7000 >/dev/null 2>&1 || nc -vz -w 3 "$DOMAIN" 7000 >/dev/null 2>&1; then
    ok "TCP $DOMAIN:7000 reachable"
  else
    warn "Cannot reach $DOMAIN:7000 via TCP"
  fi
else
  if (echo > "/dev/tcp/$DOMAIN/7000") >/dev/null 2>&1; then
    ok "TCP $DOMAIN:7000 reachable"
  else
    warn "Cannot reach $DOMAIN:7000 via TCP"
  fi
fi

if command -v openssl >/dev/null 2>&1; then
  echo "== TLS handshake to $DOMAIN:7000 (best-effort) =="
  if echo | openssl s_client -connect "$DOMAIN:7000" -servername "$DOMAIN" -brief -quiet >/dev/null 2>&1; then
    ok "TLS handshake succeeded"
  else
    warn "TLS handshake failed (may be OK if non-HTTP protocol)"
  fi
fi

echo "== Summary =="
if [[ "$FAILED" -eq 0 ]]; then
  ok "All critical checks passed"
else
  err "Some critical checks failed"
fi

exit "$FAILED"

