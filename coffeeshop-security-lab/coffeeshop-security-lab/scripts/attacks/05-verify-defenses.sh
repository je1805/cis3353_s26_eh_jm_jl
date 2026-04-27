#!/bin/bash
# =============================================================================
# Attack Script 05: Defense Verification
# CIS 3353 Security Lab - Run AFTER defenses are deployed
# =============================================================================
# Re-runs all attacks and checks if defenses are working:
#   - Are attacks detected in Wazuh? (check dashboard)
#   - Is the attacker IP blocked by active response?
#   - Does rate limiting prevent DoS?
#   - Are firewall rules enforced?
# =============================================================================

TARGET="${TARGET_IP:-10.10.0.20}"
FIREWALL="${FIREWALL_IP:-10.10.0.1}"
RESULTS="/root/results/verification"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================="
echo "  DEFENSE VERIFICATION PHASE"
echo "  Testing defenses on: ${TARGET}"
echo "  Time: $(date)"
echo "============================================="

mkdir -p ${RESULTS}

# -----------------------------------------------
# Test 1: SQLi should be detected
# -----------------------------------------------
echo ""
echo "[TEST 1] SQL Injection Detection"
echo -n "  Sending SQLi payload... "
RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" \
    "http://${TARGET}/api/search.php?q=' OR 1=1 --")
echo "HTTP ${RESPONSE}"
echo "  >> Check Wazuh: Alert 100100 should fire within 60 seconds"
echo "  RESULT: " | tee -a ${RESULTS}/verification_${TIMESTAMP}.txt
echo "  [ ] Wazuh alert generated for SQLi (rule 100100)" >> ${RESULTS}/verification_${TIMESTAMP}.txt

sleep 2

# -----------------------------------------------
# Test 2: Brute-force should trigger auto-block
# -----------------------------------------------
echo ""
echo "[TEST 2] Brute-Force Auto-Block"
echo "  Sending 10 failed login attempts..."
for i in $(seq 1 10); do
    curl -s -X POST "http://${TARGET}/api/login.php" \
        -H "Content-Type: application/json" \
        -d "{\"username\":\"admin\",\"password\":\"wrong${i}\"}" > /dev/null
    sleep 0.3
done
echo "  Waiting 10 seconds for active response..."
sleep 10
echo -n "  Checking if we're blocked: "
if curl -s --connect-timeout 5 "http://${TARGET}/" > /dev/null 2>&1; then
    echo "NOT BLOCKED (active response may not have triggered yet)"
else
    echo "BLOCKED! Active response is working."
fi
echo "  [ ] Brute-force detected (rule 100122)" >> ${RESULTS}/verification_${TIMESTAMP}.txt
echo "  [ ] Active response blocked attacker IP (rule 100300)" >> ${RESULTS}/verification_${TIMESTAMP}.txt

# -----------------------------------------------
# Test 3: Rate limiting should mitigate DoS
# -----------------------------------------------
echo ""
echo "[TEST 3] Rate Limiting Effectiveness"
echo "  Sending 100 rapid requests..."
SUCCESS=0
FAIL=0
for i in $(seq 1 100); do
    if curl -s --connect-timeout 2 "http://${TARGET}/" > /dev/null 2>&1; then
        ((SUCCESS++))
    else
        ((FAIL++))
    fi
done
echo "  Results: ${SUCCESS} succeeded, ${FAIL} blocked"
echo "  Rate limiting test: ${SUCCESS}/100 requests succeeded, ${FAIL} blocked" >> ${RESULTS}/verification_${TIMESTAMP}.txt

# -----------------------------------------------
# Test 4: Firewall rules check
# -----------------------------------------------
echo ""
echo "[TEST 4] Firewall Rule Verification"
echo "  Checking blocked ports..."
echo -n "  SSH (22): "
if nc -z -w 2 ${TARGET} 22 2>/dev/null; then echo "OPEN (should be blocked!)"; else echo "BLOCKED (correct)"; fi
echo -n "  HTTP (80): "
if nc -z -w 2 ${TARGET} 80 2>/dev/null; then echo "OPEN (expected)"; else echo "BLOCKED"; fi

echo ""
echo "============================================="
echo "  VERIFICATION CHECKLIST"
echo "  File: ${RESULTS}/verification_${TIMESTAMP}.txt"
echo "============================================="
cat ${RESULTS}/verification_${TIMESTAMP}.txt
echo ""
echo "  Complete the checklist above by checking the"
echo "  Wazuh Dashboard at https://localhost:5601"
echo "============================================="
