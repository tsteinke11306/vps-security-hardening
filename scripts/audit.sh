#!/bin/bash
# ============================================================================
# Security Audit Script
# Runs a comprehensive check of VPS security posture
# Designed to be called from a cron job (e.g., weekly on Monday 7:00 AM EST)
# ============================================================================

echo "========================================="
echo "  VPS Security Audit"
echo "  $(date -u '+%Y-%m-%d %H:%M UTC')"
echo "========================================="
echo ""

CRITICAL=0
HIGH=0
WARN=0

check() {
    local severity="$1"
    local label="$2"
    local status="$3"
    
    if [ "$status" = "FAIL" ]; then
        if [ "$severity" = "CRITICAL" ]; then
            ((CRITICAL++))
            echo -e "🔴 CRITICAL: $label"
        elif [ "$severity" = "HIGH" ]; then
            ((HIGH++))
            echo -e "🟠 HIGH: $label"
        else
            ((WARN++))
            echo -e "🟡 WARN: $label"
        fi
    else
        echo -e "🟢 OK: $label"
    fi
}

# ── Firewall ──
echo "── Firewall ──"
if ufw status 2>/dev/null | grep -q "active"; then
    check "INFO" "UFW firewall" "OK"
    ufw status numbered 2>/dev/null | head -20
else
    check "CRITICAL" "No firewall active" "FAIL"
fi
echo ""

# ── SSH ──
echo "── SSH Configuration ──"
SSH_CONFIG="/etc/ssh/sshd_config"

if grep -qE "^PasswordAuthentication no" "$SSH_CONFIG" 2>/dev/null; then
    check "INFO" "SSH password auth disabled" "OK"
else
    check "HIGH" "SSH password auth enabled" "FAIL"
fi

if grep -qE "^PermitRootLogin no" "$SSH_CONFIG" 2>/dev/null; then
    check "INFO" "SSH root login disabled" "OK"
else
    check "HIGH" "SSH root login enabled" "FAIL"
fi

# Failed login attempts (last 7 days)
FAILED_LOGINS=$(journalctl -u ssh --since "7 days ago" 2>/dev/null | grep -c "Failed" || echo "0")
if [ "$FAILED_LOGINS" -lt 10 ]; then
    check "INFO" "Failed SSH logins (7d): $FAILED_LOGINS" "OK"
else
    check "HIGH" "Failed SSH logins (7d): $FAILED_LOGINS — investigate!" "FAIL"
fi
echo ""

# ── fail2ban ──
echo "── Intrusion Prevention ──"
if systemctl is-active --quiet fail2ban 2>/dev/null; then
    check "INFO" "fail2ban running" "OK"
    fail2ban-client status sshd 2>/dev/null || true
else
    check "HIGH" "fail2ban not running" "FAIL"
fi
echo ""

# ── Service Binding ──
echo "── Service Binding ──"

# Check for services listening on 0.0.0.0 or :: that shouldn't be
EXPOSED=$(ss -tlnp | grep -E '0\.0\.0\.0:\*|\[::\]:' | grep -vE ':(2222|80|443|8443)\s' | grep -v '127.0.0.53')

if [ -z "$EXPOSED" ]; then
    check "INFO" "No unexpected services on 0.0.0.0" "OK"
else
    check "CRITICAL" "Services exposed on 0.0.0.0:" "FAIL"
    echo "$EXPOSED"
fi
echo ""

# ── Package Updates ──
echo "── System Updates ──"
PENDING=$(apt list --upgradable 2>/dev/null | grep -c "upgradable" || echo "0")
if [ "$PENDING" -le 5 ]; then
    check "INFO" "Pending updates: $PENDING" "OK"
elif [ "$PENDING" -le 15 ]; then
    check "WARN" "Pending updates: $PENDING" "FAIL"
else
    check "HIGH" "Pending updates: $PENDING — update soon!" "FAIL"
fi
echo ""

# ── Disk Space ──
echo "── Disk Usage ──"
DISK_PCT=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$DISK_PCT" -lt 70 ]; then
    check "INFO" "Root disk: ${DISK_PCT}% used" "OK"
elif [ "$DISK_PCT" -lt 85 ]; then
    check "WARN" "Root disk: ${DISK_PCT}% used" "FAIL"
else
    check "HIGH" "Root disk: ${DISK_PCT}% used — critical!" "FAIL"
fi
echo ""

# ── Tailscale ──
echo "── Tailscale ──"
if systemctl is-active --quiet tailscaled 2>/dev/null; then
    check "INFO" "Tailscale running" "OK"
    tailscale status 2>/dev/null | head -5 || true
else
    check "WARN" "Tailscale not running" "FAIL"
fi
echo ""

# ── Summary ──
echo "========================================="
echo "  Summary"
echo "========================================="
echo "  🔴 Critical: $CRITICAL"
echo "  🟠 High:     $HIGH"
echo "  🟡 Warnings: $WARN"
echo ""

if [ "$CRITICAL" -gt 0 ] || [ "$HIGH" -gt 0 ]; then
    echo "  ⚠️  Action required — see findings above"
    exit 1
else
    echo "  ✅ All clear — no critical or high findings"
    exit 0
fi