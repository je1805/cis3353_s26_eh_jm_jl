#!/bin/bash
# =============================================================================
# Wazuh Active Response Script - Block IP on Firewall
# CIS 3353 Security Lab
# =============================================================================
# This script is triggered by the Wazuh Manager when active response rules
# fire. It communicates with the firewall container to block the attacker IP.
#
# Integration flow:
#   1. Wazuh detects threat (custom rule triggers)
#   2. Wazuh Manager calls this script with attacker IP
#   3. Script sends block command to firewall container via Docker exec
#   4. Firewall adds iptables rule to drop traffic from attacker
#
# Arguments (standard Wazuh active response format):
#   $1 = action (add/delete)
#   $2 = user (not used)
#   $3 = srcip (attacker IP to block)
# =============================================================================

LOCAL=$(dirname $0)
LOCK_FILE="/var/ossec/var/run/block-ip-firewall.lock"
LOG_FILE="/var/ossec/logs/active-responses.log"
FIREWALL_CONTAINER="pfsense-firewall"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') block-ip-firewall: $1" >> ${LOG_FILE}
}

# Read Wazuh active response input
read INPUT_JSON
ACTION=$(echo ${INPUT_JSON} | jq -r '.command')
SRCIP=$(echo ${INPUT_JSON} | jq -r '.parameters.alert.data.srcip // .parameters.alert.srcip // empty')

# Fallback: try positional arguments (older Wazuh format)
if [ -z "${SRCIP}" ]; then
    ACTION="${1:-add}"
    SRCIP="${3}"
fi

if [ -z "${SRCIP}" ]; then
    log "ERROR: No source IP provided"
    exit 1
fi

log "Received: action=${ACTION} srcip=${SRCIP}"

case "${ACTION}" in
    add)
        log "BLOCKING IP: ${SRCIP} on firewall container ${FIREWALL_CONTAINER}"

        # Method 1: Docker exec (if running on same host)
        docker exec ${FIREWALL_CONTAINER} \
            /opt/active-response/handler.sh block "${SRCIP}" 3600 \
            2>>${LOG_FILE} && {
            log "SUCCESS: IP ${SRCIP} blocked on firewall via docker exec"
            exit 0
        }

        # Method 2: SSH to firewall container (fallback)
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 \
            root@10.10.0.1 \
            "/opt/active-response/handler.sh block ${SRCIP} 3600" \
            2>>${LOG_FILE} && {
            log "SUCCESS: IP ${SRCIP} blocked on firewall via SSH"
            exit 0
        }

        # Method 3: Direct iptables via API (last resort)
        curl -s -X POST "http://10.10.0.1:8443/index.php" \
            -d "action=block&ip=${SRCIP}&duration=3600" \
            2>>${LOG_FILE} && {
            log "SUCCESS: IP ${SRCIP} blocked on firewall via Web API"
            exit 0
        }

        log "WARNING: All methods failed to block ${SRCIP} on firewall"
        ;;

    delete)
        log "UNBLOCKING IP: ${SRCIP} on firewall container ${FIREWALL_CONTAINER}"
        docker exec ${FIREWALL_CONTAINER} \
            /opt/active-response/handler.sh unblock "${SRCIP}" 2>>${LOG_FILE} || \
        ssh -o StrictHostKeyChecking=no root@10.10.0.1 \
            "/opt/active-response/handler.sh unblock ${SRCIP}" 2>>${LOG_FILE}
        log "IP ${SRCIP} unblocked on firewall"
        ;;

    *)
        log "ERROR: Unknown action: ${ACTION}"
        exit 1
        ;;
esac

exit 0
