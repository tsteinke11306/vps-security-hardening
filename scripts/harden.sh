#!/bin/bash
# ============================================================================
# VPS Security Hardening Script
# Ubuntu 24.04 — Firewall, Service Isolation, Intrusion Prevention
# ============================================================================
# USAGE: sudo bash scripts/harden.sh
# 
# ⚠️  REVIEW THIS SCRIPT BEFORE RUNNING IT.
#     This is tailored to a specific VPS setup — adapt it to yours.
#     It will:
#       - Install and configure UFW (default deny incoming)
#       - Bind qBittorrent WebUI to localhost only
#       - Install and configure fail2ban for SSH
#       - Run apt upgrade
#     It will NOT modify the Portfolio API binding (manual step).
# ============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "========================================="
echo "  VPS Security Hardening Script"
echo "  Ubuntu 24.04"
echo "========================================="
echo ""
echo -e "${YELLOW}Review this script before running!${NC}"
echo -e "${YELLOW}This is tailored to a specific setup — adapt to yours.${NC}"
echo ""
read -p "Continue? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

# ──────────────────────────────────────────
# 1. UFW Firewall
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}[1/4] Setting up UFW firewall...${NC}"

apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing

# ── Whitelist ──
# SSH — key-only auth on non-standard port
ufw allow 2222/tcp comment 'SSH'

# Caddy web server
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 8443/tcp comment 'Portfolio API HTTPS'

# Tailscale mesh VPN
ufw allow in on tailscale0 comment 'Tailscale traffic'

echo "y" | ufw enable

echo -e "${GREEN}UFW configured. Status:${NC}"
ufw status verbose

# ──────────────────────────────────────────
# 2. qBittorrent — Localhost Binding
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}[2/4] Hardening qBittorrent WebUI...${NC}"

QBIT_CONF="/home/openclaw/.config/qBittorrent/qBittorrent.conf"

if [ -f "$QBIT_CONF" ]; then
    # Stop service FIRST — qBittorrent overwrites config on shutdown
    systemctl stop qbittorrent-nox.service
    
    # Replace binding
    sed -i 's/WebUI\\Address=0.0.0.0/WebUI\\Address=127.0.0.1/' "$QBIT_CONF"
    
    # Verify
    if grep -q 'WebUI\\Address=127.0.0.1' "$QBIT_CONF"; then
        echo "  WebUI binding changed to 127.0.0.1"
    else
        echo -e "${RED}  ERROR: Config change didn't stick!${NC}"
        echo "  Manually edit $QBIT_CONF and set WebUI\Address=127.0.0.1"
    fi
    
    systemctl start qbittorrent-nox.service
else
    echo -e "${YELLOW}  qBittorrent config not found at $QBIT_CONF${NC}"
    echo "  Skip this step or update the path."
fi

# ──────────────────────────────────────────
# 3. fail2ban
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}[3/4] Installing fail2ban...${NC}"

apt-get install -y fail2ban

cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
port = 2222
backend = systemd
EOF

systemctl enable fail2ban
systemctl start fail2ban

echo "  SSH jail: 5 retries within 10min → 1hr ban (port 2222)"

# ──────────────────────────────────────────
# 4. System Updates
# ──────────────────────────────────────────
echo ""
echo -e "${GREEN}[4/4] Running apt upgrade...${NC}"

apt-get update
apt-get upgrade -y

# ──────────────────────────────────────────
# Summary
# ──────────────────────────────────────────
echo ""
echo "========================================="
echo "  Hardening Complete!"
echo "========================================="
echo ""
echo "Changes made:"
echo "  1. UFW firewall — deny all incoming except SSH(2222), HTTP(80), HTTPS(443), API(8443), Tailscale"
echo "  2. qBittorrent WebUI — bound to 127.0.0.1 (was 0.0.0.0)"
echo "  3. fail2ban — installed, SSH jail on port 2222"
echo "  4. System packages updated"
echo ""
echo -e "${YELLOW}Manual steps remaining:${NC}"
echo "  - Bind Portfolio API to 127.0.0.1 (edit server.js: app.listen(PORT, '127.0.0.1', () => {...}))"
echo "  - Review Caddy config for proper TLS settings"
echo "  - Set up automated security audit cron job"
echo ""
echo "Verify with:"
echo "  ufw status verbose"
echo "  fail2ban-client status sshd"
echo "  ss -tlnp | grep -E '3456|8080'"