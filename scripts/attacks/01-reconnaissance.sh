#!/bin/bash
# =============================================================================
# Attack Script 01: Reconnaissance & Enumeration
# CIS 3353 Security Lab - Run from Kali container
# =============================================================================
# Demonstrates: Network discovery, port scanning, service enumeration
# Module: 2 (Attack Surfaces), 8 (Infrastructure Threats)
# Expected Wazuh alerts: Port scan detection (rule 100200)
# =============================================================================

TARGET="${TARGET_IP:-10.10.0.20}"
NETWORK="${NETWORK_RANGE:-10.10.0.0/24}"
RESULTS="/root/results/scans"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================="
echo "  PHASE 1: RECONNAISSANCE"
echo "  Target: ${TARGET}"
echo "  Network: ${NETWORK}"
echo "  Time: $(date)"
echo "============================================="

mkdir -p ${RESULTS}

# Step 1: Network Discovery
echo ""
echo "[1/5] Network Discovery (ping sweep)..."
nmap -sn ${NETWORK} -oN ${RESULTS}/01_network_discovery_${TIMESTAMP}.txt
echo "  >> Saved: ${RESULTS}/01_network_discovery_${TIMESTAMP}.txt"

# Step 2: Quick Port Scan
echo ""
echo "[2/5] Quick port scan on target..."
nmap -sV -T4 ${TARGET} -oN ${RESULTS}/02_quick_scan_${TIMESTAMP}.txt
echo "  >> Saved: ${RESULTS}/02_quick_scan_${TIMESTAMP}.txt"

# Step 3: Full Port Scan
echo ""
echo "[3/5] Full port scan (all 65535 ports)..."
nmap -sV -sC -O -p- ${TARGET} -oN ${RESULTS}/03_full_scan_${TIMESTAMP}.txt
echo "  >> Saved: ${RESULTS}/03_full_scan_${TIMESTAMP}.txt"

# Step 4: Web Server Enumeration
echo ""
echo "[4/5] Web server enumeration with nikto..."
nikto -h http://${TARGET} -o ${RESULTS}/04_nikto_${TIMESTAMP}.txt 2>/dev/null
echo "  >> Saved: ${RESULTS}/04_nikto_${TIMESTAMP}.txt"

# Step 5: Directory Brute-Force
echo ""
echo "[5/5] Directory discovery with dirb..."
dirb http://${TARGET} /usr/share/dirb/wordlists/common.txt \
    -o ${RESULTS}/05_dirb_${TIMESTAMP}.txt 2>/dev/null
echo "  >> Saved: ${RESULTS}/05_dirb_${TIMESTAMP}.txt"

echo ""
echo "============================================="
echo "  RECONNAISSANCE COMPLETE"
echo "  Results saved to: ${RESULTS}/"
echo "  Check Wazuh dashboard for port scan alerts"
echo "============================================="
