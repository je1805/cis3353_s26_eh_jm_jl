#!/bin/bash
# =============================================================================
# Firewall Gateway - Initialization Script
# CIS 3353 Security Lab
# =============================================================================
# This script initializes the firewall container on startup:
#   1. Enables IP forwarding
#   2. Loads base iptables rules
#   3. Configures NAT and port forwarding
#   4. Starts services (rsyslog, lighttpd, suricata)
# =============================================================================

set -e

echo "============================================="
echo "  CIS 3353 - Firewall Gateway Starting"
echo "============================================="

# ---------------------------------------------------------------------------
# Enable IP forwarding
# ---------------------------------------------------------------------------
echo "[*] Enabling IP forwarding..."
echo 1 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true
echo 1 > /proc/sys/net/ipv4/conf/all/forwarding 2>/dev/null || true

# ---------------------------------------------------------------------------
# Load firewall rules
# ---------------------------------------------------------------------------
echo "[*] Loading firewall rules..."
/opt/firewall-rules.sh

# ---------------------------------------------------------------------------
# Load rate limiting rules
# ---------------------------------------------------------------------------
echo "[*] Configuring rate limiting..."
/opt/rate-limit.sh

# ---------------------------------------------------------------------------
# Load any custom rules from the rules.d directory
# ---------------------------------------------------------------------------
if [ -d /etc/firewall/rules.d ]; then
    for f in /etc/firewall/rules.d/*.sh; do
        if [ -f "$f" ]; then
            echo "[*] Loading custom rule: $f"
            bash "$f"
        fi
    done
fi

# ---------------------------------------------------------------------------
# Log current iptables state
# ---------------------------------------------------------------------------
echo "[*] Current iptables rules:"
iptables -L -v -n --line-numbers | tee /var/log/firewall/rules-loaded.log

echo ""
echo "============================================="
echo "  Firewall Gateway Ready"
echo "  Management UI: https://localhost:8443"
echo "============================================="

# Start supervisor (manages all services)
exec /usr/bin/supervisord -c /etc/supervisor.d/firewall.ini
