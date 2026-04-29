#!/bin/bash
# =============================================================================
# Firewall Rules - iptables Configuration
# CIS 3353 Security Lab
# =============================================================================
# Implements pfSense-equivalent firewall policies:
#   - Default DENY policy (all chains)
#   - Stateful packet inspection
#   - Zone-based rules (WAN/LAN)
#   - NAT and port forwarding
#   - Logging for all blocked traffic
#   - Specific allow rules for required services
# =============================================================================

# Environment variables (set by docker-compose)
JOKOPI_IP="${JOKOPI_IP:-10.10.0.20}"
WAZUH_MANAGER_IP="${WAZUH_MANAGER_IP:-10.10.0.10}"
WAZUH_DASHBOARD_IP="${WAZUH_DASHBOARD_IP:-10.10.0.11}"
LAN_SUBNET="${LAN_SUBNET:-10.10.0.0/24}"

echo "[firewall] Configuring iptables rules..."

# ---------------------------------------------------------------------------
# Flush existing rules
# ---------------------------------------------------------------------------
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

# ---------------------------------------------------------------------------
# DEFAULT POLICIES - Deny all by default
# This implements the "default deny" security principle (Module 9)
# ---------------------------------------------------------------------------
iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

# ---------------------------------------------------------------------------
# LOGGING CHAINS (for Wazuh ingestion)
# ---------------------------------------------------------------------------
# Create logging chains for different traffic types
iptables -N LOG_DROP
iptables -A LOG_DROP -j LOG --log-prefix "[FW-DROP] " --log-level 4
iptables -A LOG_DROP -j DROP

iptables -N LOG_ACCEPT
iptables -A LOG_ACCEPT -j LOG --log-prefix "[FW-ACCEPT] " --log-level 6
iptables -A LOG_ACCEPT -j ACCEPT

iptables -N LOG_BLOCKED_ATTACKER
iptables -A LOG_BLOCKED_ATTACKER -j LOG --log-prefix "[FW-BLOCKED-ATTACKER] " --log-level 4
iptables -A LOG_BLOCKED_ATTACKER -j DROP

# ---------------------------------------------------------------------------
# STATEFUL INSPECTION - Allow established/related connections
# ---------------------------------------------------------------------------
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Drop invalid packets
iptables -A INPUT -m conntrack --ctstate INVALID -j LOG_DROP
iptables -A FORWARD -m conntrack --ctstate INVALID -j LOG_DROP

# ---------------------------------------------------------------------------
# LOOPBACK - Allow localhost traffic
# ---------------------------------------------------------------------------
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# ---------------------------------------------------------------------------
# INPUT RULES - Traffic destined for the firewall itself
# ---------------------------------------------------------------------------
# Allow ICMP (ping) from LAN
iptables -A INPUT -s ${LAN_SUBNET} -p icmp -j ACCEPT

# Allow SSH from LAN only (management)
iptables -A INPUT -s ${LAN_SUBNET} -p tcp --dport 22 -j LOG_ACCEPT

# Allow management web UI from LAN only
iptables -A INPUT -s ${LAN_SUBNET} -p tcp --dport 8443 -j LOG_ACCEPT

# Allow DNS from LAN
iptables -A INPUT -s ${LAN_SUBNET} -p udp --dport 53 -j ACCEPT
iptables -A INPUT -s ${LAN_SUBNET} -p tcp --dport 53 -j ACCEPT

# Log and drop everything else to INPUT
iptables -A INPUT -j LOG_DROP

# ---------------------------------------------------------------------------
# FORWARD RULES - Traffic passing through the firewall
# ---------------------------------------------------------------------------

# Rule 1: Allow LAN-to-LAN (internal communication)
iptables -A FORWARD -s ${LAN_SUBNET} -d ${LAN_SUBNET} -j ACCEPT

# Rule 2: Allow Jokopi -> Wazuh Manager (agent communication)
iptables -A FORWARD -s ${JOKOPI_IP} -d ${WAZUH_MANAGER_IP} -p tcp --dport 1514 -j ACCEPT
iptables -A FORWARD -s ${JOKOPI_IP} -d ${WAZUH_MANAGER_IP} -p tcp --dport 1515 -j ACCEPT

# Rule 3: Allow external access to Jokopi web app (HTTP/HTTPS only)
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp --dport 80 -j LOG_ACCEPT
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp --dport 443 -j LOG_ACCEPT

# Rule 4: Allow LAN to Internet (outbound)
iptables -A FORWARD -s ${LAN_SUBNET} ! -d ${LAN_SUBNET} -j ACCEPT

# Rule 5: Log and drop all other forwarded traffic
iptables -A FORWARD -j LOG_DROP

# ---------------------------------------------------------------------------
# NAT RULES - Network Address Translation
# ---------------------------------------------------------------------------
# Masquerade outbound traffic
iptables -t nat -A POSTROUTING -s ${LAN_SUBNET} ! -d ${LAN_SUBNET} -j MASQUERADE

# Port forwarding: External port 80 -> Jokopi app
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination ${JOKOPI_IP}:80

# Port forwarding: External port 5601 -> Wazuh Dashboard
iptables -t nat -A PREROUTING -p tcp --dport 5601 -j DNAT --to-destination ${WAZUH_DASHBOARD_IP}:5601

# ---------------------------------------------------------------------------
# ANTI-SPOOFING
# ---------------------------------------------------------------------------
# Drop packets with impossible source addresses
iptables -A INPUT -s 127.0.0.0/8 ! -i lo -j LOG_DROP
iptables -A FORWARD -s 127.0.0.0/8 -j LOG_DROP

echo "[firewall] iptables rules loaded successfully."
echo "[firewall] Default policy: DROP (INPUT), DROP (FORWARD), ACCEPT (OUTPUT)"
echo "[firewall] Logging enabled with prefixes: [FW-DROP], [FW-ACCEPT], [FW-BLOCKED-ATTACKER]"
