#!/bin/bash
# =============================================================================
# Active Response Handler - Wazuh-to-Firewall Integration
# CIS 3353 Security Lab
# =============================================================================
# This script is called by the Wazuh active response system when a threat is
# detected. It adds/removes iptables rules to block attacker IPs.
#
# Usage:
#   ./handler.sh block   <IP_ADDRESS>   [duration_seconds]
#   ./handler.sh unblock <IP_ADDRESS>
#   ./handler.sh list
#   ./handler.sh flush
#
# Wazuh Active Response Integration:
#   The Wazuh Manager calls this script via SSH or API when alert thresholds
#   are exceeded. The script manages a dynamic blocklist in iptables.
# =============================================================================

BLOCKLIST_FILE="/var/log/firewall/blocklist.txt"
LOG_FILE="/var/log/firewall/active-response.log"
BLOCK_CHAIN="LOG_BLOCKED_ATTACKER"

# Initialize files
touch "${BLOCKLIST_FILE}" "${LOG_FILE}"

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "${LOG_FILE}"
    echo "$1"
}

# ---------------------------------------------------------------------------
# BLOCK an IP address
# ---------------------------------------------------------------------------
block_ip() {
    local IP="$1"
    local DURATION="${2:-3600}"  # Default: 1 hour

    # Validate IP format. The firewall container is Alpine, so the available
    # `grep` is busybox grep — which does NOT support PCRE (`-P`). Use
    # POSIX-extended (`-E`) with explicit character classes instead of `\d`.
    if ! echo "${IP}" | grep -qE '^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$'; then
        log_action "ERROR: Invalid IP format: ${IP}"
        exit 1
    fi

    # Check if already blocked
    if iptables -C FORWARD -s "${IP}" -j ${BLOCK_CHAIN} 2>/dev/null; then
        log_action "INFO: IP ${IP} is already blocked"
        exit 0
    fi

    # Add blocking rule at the TOP of FORWARD chain (before allow rules).
    # FORWARD is the meaningful one for traffic transiting the firewall to
    # jokopi; INPUT is only relevant if the attacker targets the firewall
    # itself. We tolerate INPUT failing (e.g. if LOG_BLOCKED_ATTACKER isn't
    # referenced from INPUT, or INPUT lacks the chain entirely) so the
    # script exits 0 whenever the FORWARD block lands. Otherwise the
    # manager's AR script falsely logs "All methods failed" even though
    # the attacker is in fact blocked.
    iptables -I FORWARD 1 -s "${IP}" -j ${BLOCK_CHAIN} || {
        log_action "ERROR: failed to insert FORWARD block for ${IP}"
        exit 1
    }
    iptables -I INPUT 1 -s "${IP}" -j ${BLOCK_CHAIN} 2>/dev/null \
        || log_action "INFO: INPUT block insert skipped for ${IP} (FORWARD-only)"

    # Record in blocklist
    EXPIRY=$(date -d "+${DURATION} seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
             date -v+${DURATION}S '+%Y-%m-%d %H:%M:%S' 2>/dev/null || \
             echo "permanent")
    echo "${IP}|$(date '+%Y-%m-%d %H:%M:%S')|${EXPIRY}|${DURATION}" >> "${BLOCKLIST_FILE}"

    log_action "BLOCKED: IP ${IP} for ${DURATION} seconds (expires: ${EXPIRY})"

    # Schedule automatic unblock if duration is set
    if [ "${DURATION}" -gt 0 ] 2>/dev/null; then
        (sleep "${DURATION}" && /opt/active-response/handler.sh unblock "${IP}") &
        log_action "AUTO-UNBLOCK scheduled for ${IP} in ${DURATION} seconds"
    fi
}

# ---------------------------------------------------------------------------
# UNBLOCK an IP address
# ---------------------------------------------------------------------------
unblock_ip() {
    local IP="$1"

    # Remove from iptables
    iptables -D FORWARD -s "${IP}" -j ${BLOCK_CHAIN} 2>/dev/null
    iptables -D INPUT -s "${IP}" -j ${BLOCK_CHAIN} 2>/dev/null

    # Remove from blocklist file
    sed -i "/^${IP}|/d" "${BLOCKLIST_FILE}" 2>/dev/null

    log_action "UNBLOCKED: IP ${IP}"
}

# ---------------------------------------------------------------------------
# LIST all blocked IPs
# ---------------------------------------------------------------------------
list_blocked() {
    echo "========================================="
    echo "  Currently Blocked IPs"
    echo "========================================="
    echo ""
    if [ -s "${BLOCKLIST_FILE}" ]; then
        printf "%-18s %-22s %-22s %s\n" "IP Address" "Blocked At" "Expires" "Duration"
        echo "-----------------------------------------------------------------"
        while IFS='|' read -r ip blocked expires duration; do
            printf "%-18s %-22s %-22s %ss\n" "${ip}" "${blocked}" "${expires}" "${duration}"
        done < "${BLOCKLIST_FILE}"
    else
        echo "  No IPs currently blocked."
    fi
    echo ""
    echo "Active iptables block rules:"
    iptables -L FORWARD -n --line-numbers | grep "${BLOCK_CHAIN}" || echo "  None"
}

# ---------------------------------------------------------------------------
# FLUSH all blocked IPs
# ---------------------------------------------------------------------------
flush_blocked() {
    while IFS='|' read -r ip rest; do
        iptables -D FORWARD -s "${ip}" -j ${BLOCK_CHAIN} 2>/dev/null
        iptables -D INPUT -s "${ip}" -j ${BLOCK_CHAIN} 2>/dev/null
    done < "${BLOCKLIST_FILE}"
    > "${BLOCKLIST_FILE}"
    log_action "FLUSHED: All blocked IPs removed"
}

# ---------------------------------------------------------------------------
# Main dispatcher
# ---------------------------------------------------------------------------
case "$1" in
    block)
        block_ip "$2" "$3"
        ;;
    unblock)
        unblock_ip "$2"
        ;;
    list)
        list_blocked
        ;;
    flush)
        flush_blocked
        ;;
    *)
        echo "Usage: $0 {block|unblock|list|flush} [IP] [duration_seconds]"
        echo ""
        echo "Examples:"
        echo "  $0 block 10.10.0.100 3600    # Block Kali for 1 hour"
        echo "  $0 unblock 10.10.0.100       # Remove block"
        echo "  $0 list                       # Show all blocked IPs"
        echo "  $0 flush                      # Remove all blocks"
        exit 1
        ;;
esac
