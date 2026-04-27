#!/bin/bash
# =============================================================================
# Rate Limiting Rules - DoS Mitigation
# CIS 3353 Security Lab
# =============================================================================
# Implements connection rate limiting to mitigate:
#   - SYN flood attacks
#   - HTTP flood attacks
#   - Brute-force attempts
#   - Port scan detection
# =============================================================================

JOKOPI_IP="${JOKOPI_IP:-10.10.0.20}"

echo "[rate-limit] Configuring rate limiting rules..."

# ---------------------------------------------------------------------------
# SYN Flood Protection
# ---------------------------------------------------------------------------
# Limit new TCP connections to 25 per second per source IP
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp --syn \
    -m hashlimit \
    --hashlimit-name syn_flood \
    --hashlimit-above 25/sec \
    --hashlimit-burst 50 \
    --hashlimit-mode srcip \
    -j LOG --log-prefix "[FW-SYNFLOOD] " --log-level 4
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp --syn \
    -m hashlimit \
    --hashlimit-name syn_flood2 \
    --hashlimit-above 25/sec \
    --hashlimit-burst 50 \
    --hashlimit-mode srcip \
    -j DROP

# ---------------------------------------------------------------------------
# HTTP Connection Rate Limiting
# ---------------------------------------------------------------------------
# Limit HTTP requests to 30 per second per source IP
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp --dport 80 \
    -m hashlimit \
    --hashlimit-name http_limit \
    --hashlimit-above 30/sec \
    --hashlimit-burst 60 \
    --hashlimit-mode srcip \
    -j LOG --log-prefix "[FW-HTTPFLOOD] " --log-level 4
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp --dport 80 \
    -m hashlimit \
    --hashlimit-name http_limit2 \
    --hashlimit-above 30/sec \
    --hashlimit-burst 60 \
    --hashlimit-mode srcip \
    -j DROP

# ---------------------------------------------------------------------------
# Port Scan Detection
# ---------------------------------------------------------------------------
# Detect and log rapid port scanning (more than 10 different ports in 60s)
iptables -A FORWARD -p tcp --tcp-flags SYN,ACK,FIN,RST RST \
    -m limit --limit 1/s --limit-burst 4 \
    -j LOG --log-prefix "[FW-PORTSCAN] " --log-level 4

# ---------------------------------------------------------------------------
# ICMP Rate Limiting (Ping Flood Protection)
# ---------------------------------------------------------------------------
iptables -A FORWARD -p icmp --icmp-type echo-request \
    -m limit --limit 5/sec --limit-burst 10 -j ACCEPT
iptables -A FORWARD -p icmp --icmp-type echo-request -j DROP

# ---------------------------------------------------------------------------
# Connection Tracking Limits
# ---------------------------------------------------------------------------
# Limit total connections per source IP to prevent resource exhaustion
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp \
    -m connlimit --connlimit-above 100 --connlimit-mask 32 \
    -j LOG --log-prefix "[FW-CONNLIMIT] " --log-level 4
iptables -A FORWARD -d ${JOKOPI_IP} -p tcp \
    -m connlimit --connlimit-above 100 --connlimit-mask 32 \
    -j DROP

echo "[rate-limit] Rate limiting rules applied."
echo "[rate-limit] SYN flood: 25/sec, HTTP: 30/sec, ICMP: 5/sec, Max conn: 100/IP"
