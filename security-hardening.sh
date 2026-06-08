#!/bin/bash
# Security Hardening Script — April 20, 2026
# Run with: sudo bash /path/to/workspace/security-hardening.sh
# Note: The system user account retains the original "openclaw" name
# for compatibility. Update paths as needed for your environment.
# This handles all 5 audit findings at once.

set -e

echo "========================================="
echo "  VPS Security Hardening Script"
echo "========================================="
echo ""

# ──────────────────────────────────────────
# 1. UFW Firewall
# ──────────────────────────────────────────
echo "[1/5] Setting up UFW firewall..."

apt-get install -y ufw

# Default deny all incoming
ufw default deny incoming
ufw default allow outgoing

# SSH on port 2222
ufw allow 2222/tcp comment 'SSH'

# Caddy HTTP/HTTPS
ufw allow 80/tcp comment 'HTTP'
ufw allow 443/tcp comment 'HTTPS'
ufw allow 8443/tcp comment 'Portfolio API'

# Tailscale (UDP 41641 for direct, plus the serve proxy works over the existing connection)
ufw allow in on tailscale0 comment 'Tailscale traffic'

# Enable firewall
echo "y" | ufw enable

ufw status verbose
echo "[1/5] ✅ UFW configured"
echo ""

# ──────────────────────────────────────────
# 2. qBittorrent — bind WebUI to localhost only
# ──────────────────────────────────────────
echo "[2/5] Hardening qBittorrent WebUI..."

QBIT_CONF="/home/openclaw/.config/qBittorrent/qBittorrent.conf"
# NOTE: /home/openclaw is a legacy filesystem path. The system user retains the original name for compatibility.

# Change WebUI Address from 0.0.0.0 to 127.0.0.1
# This means it's only accessible via localhost or Tailscale proxy
sed -i 's/WebUI\\Address=0.0.0.0/WebUI\\Address=127.0.0.1/' "$QBIT_CONF"

# Restart qBittorrent to apply
systemctl restart qbittorrent-nox.service

echo "  WebUI now bound to 127.0.0.1 (localhost only)"
echo "  Access via: Tailscale proxy or SSH tunnel"
echo "[2/5] ✅ qBittorrent hardened"
echo ""

# ──────────────────────────────────────────
# 3. Portfolio API — bind to localhost only
# ──────────────────────────────────────────
echo "[3/5] Hardening Portfolio Contact API..."

PORTFOLIO_ENV="/root/portfolio-contact/.env"
# NOTE: The /home/openclaw path referenced elsewhere is a legacy filesystem path.
# The system user account retains the original name for compatibility; the AI agent is Hermes.

# Check if .env exists and has a HOST variable
if [ -f "$PORTFOLIO_ENV" ]; then
    if grep -q "^HOST=" "$PORTFOLIO_ENV"; then
        sed -i 's/^HOST=.*/HOST=127.0.0.1/' "$PORTFOLIO_ENV"
    else
        echo "HOST=127.0.0.1" >> "$PORTFOLIO_ENV"
    fi
else
    echo "HOST=127.0.0.1" > "$PORTFOLIO_ENV"
fi

# Also check the server.js for a hardcoded listen address
# If it uses app.listen(PORT) without a host, the HOST env var should work
# But if it hardcodes 0.0.0.0, we need to patch it
if grep -q "0\.0\.0\.0" /root/portfolio-contact/server.js 2>/dev/null; then
    sed -i 's/0\.0\.0\.0/127.0.0.1/g' /root/portfolio-contact/server.js
    echo "  Patched server.js: 0.0.0.0 → 127.0.0.1"
fi

systemctl restart portfolio-contact.service
echo "  Portfolio API now bound to 127.0.0.1 (localhost only)"
echo "  Caddy reverse proxy still handles public TLS on :8443"
echo "[3/5] ✅ Portfolio API hardened"
echo ""

# ──────────────────────────────────────────
# 4. fail2ban — install & configure for SSH
# ──────────────────────────────────────────
echo "[4/5] Installing fail2ban..."

apt-get install -y fail2ban

# Create local config for SSH on port 2222
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

echo "  SSH jail: 5 retries → 1hr ban, port 2222"
echo "[4/5] ✅ fail2ban installed and configured"
echo ""

# ──────────────────────────────────────────
# 5. System package updates
# ──────────────────────────────────────────
echo "[5/5] Running apt upgrade..."

apt-get update
apt-get upgrade -y

echo "[5/5] ✅ Packages updated"
echo ""

# ──────────────────────────────────────────
# Summary
# ──────────────────────────────────────────
echo "========================================="
echo "  Hardening Complete!"
echo "========================================="
echo ""
echo "Changes made:"
echo "  1. UFW firewall: deny all incoming except SSH(2222), HTTP(80), HTTPS(443), API(8443), Tailscale"
echo "  2. qBittorrent WebUI: bound to 127.0.0.1 (was 0.0.0.0)"
echo "  3. Portfolio API: bound to 127.0.0.1 (was 0.0.0.0)"
echo "  4. fail2ban: installed, SSH jail on port 2222"
echo "  5. System packages updated"
echo ""
echo "Verify with:"
echo "  ufw status verbose"
echo "  fail2ban-client status sshd"
echo "  ss -tlnp | grep -E '3456|8080'"