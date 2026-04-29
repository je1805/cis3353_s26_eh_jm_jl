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

# Read Wazuh active response input. Wazuh 4.2+ sends a single-line JSON
# document on stdin; older versions passed positional args ($1=action,
# $3=srcip). We support both, and log the raw stdin for forensics so a
# future "No source IP provided" failure can be diagnosed without guessing.
INPUT_JSON="$(cat)"
log "RAW INPUT: ${INPUT_JSON:-<empty>} | ARGV: $*"

ACTION=""
SRCIP=""

if [ -n "${INPUT_JSON}" ] && command -v jq >/dev/null 2>&1; then
    ACTION=$(printf '%s' "${INPUT_JSON}" | jq -r '.command // empty' 2>/dev/null)
    SRCIP=$(printf '%s' "${INPUT_JSON}" | jq -r '
        .parameters.alert.data.srcip //
        .parameters.alert.srcip      //
        .parameters.srcip            //
        .srcip                       //
        empty' 2>/dev/null)
fi

# jq missing? Fall back to a grep that pulls the first IPv4 after "srcip":"
if [ -z "${SRCIP}" ] && [ -n "${INPUT_JSON}" ]; then
    SRCIP=$(printf '%s' "${INPUT_JSON}" \
        | grep -oE '"srcip":"[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+"' \
        | head -1 | cut -d'"' -f4)
fi

# Last resort: positional args (legacy Wazuh AR format)
if [ -z "${SRCIP}" ]; then
    ACTION="${ACTION:-${1:-add}}"
    SRCIP="${3}"
fi

ACTION="${ACTION:-add}"

if [ -z "${SRCIP}" ]; then
    log "ERROR: No source IP provided (stdin len=${#INPUT_JSON}, argc=$#)"
    exit 1
fi

log "Received: action=${ACTION} srcip=${SRCIP}"

case "${ACTION}" in
    add)
        log "BLOCKING IP: ${SRCIP} on firewall container ${FIREWALL_CONTAINER}"

        # Method 1: Docker exec (if running on same host).
        # `</dev/null` is important: this script reads its own stdin via
        # `INPUT_JSON="$(cat)"`, which leaves stdin closed/at EOF. Without
        # an explicit redirect, `docker exec` inherits that closed stdin
        # and can return a non-zero exit code (SIGPIPE / read error)
        # even though handler.sh inside the firewall container ran fine
        # and the iptables rule was added. That false failure is what
        # made this method drop through to SSH/HTTP fallbacks and emit
        # a misleading "All methods failed" warning.
        #
        # NOTE on enforcement: this command adds an iptables rule INSIDE
        # the pfsense-firewall container's network namespace. Because
        # all lab containers share a single docker bridge
        # (coffeeshop-net), inter-container packets are L2-forwarded by
        # the host bridge and never enter the firewall container's
        # netns — so the rule below is technically a no-op for traffic
        # enforcement. We keep it because it (a) drives the dashboard
        # widgets and the "view blocklist" view inside the firewall and
        # (b) demonstrates what a real firewall would have configured.
        # The actual packet drop is done by the host-level rule below.
        docker exec ${FIREWALL_CONTAINER} \
            /opt/active-response/handler.sh block "${SRCIP}" 3600 \
            </dev/null 2>>${LOG_FILE} && {
            log "SUCCESS: IP ${SRCIP} blocked on firewall (config layer) via docker exec"
        }

        # Method 1B (ENFORCEMENT): Add a DROP rule to the host's
        # DOCKER-USER chain. DOCKER-USER is jumped to from FORWARD on
        # the host's iptables, and (provided net.bridge.bridge-nf-call-iptables=1)
        # this is the only place where a rule sees inter-container
        # traffic on a shared bridge. Without this step, blocking is
        # cosmetic; with this step the packet count on the rule
        # actually goes up and curl from the attacker hangs/fails.
        #
        # We use a one-shot alpine container with --net=host so the
        # iptables binary writes into the host's network namespace.
        # Image is pulled once and cached; subsequent invocations
        # reuse the layer.
        docker run --rm --net=host --cap-add=NET_ADMIN \
            alpine:3.19 sh -c "
                apk add --no-cache --quiet iptables >/dev/null 2>&1
                iptables -C DOCKER-USER -s ${SRCIP} -j DROP 2>/dev/null \
                    || iptables -I DOCKER-USER 1 -s ${SRCIP} -j DROP
            " </dev/null 2>>${LOG_FILE} && {
            log "ENFORCEMENT: IP ${SRCIP} dropped at host DOCKER-USER chain"
            exit 0
        } || {
            log "WARNING: host-level DOCKER-USER rule failed for ${SRCIP}"
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
            /opt/active-response/handler.sh unblock "${SRCIP}" \
            </dev/null 2>>${LOG_FILE} || true

        # Also remove the host-level DOCKER-USER rule that does the
        # actual enforcement. Without this, an "unblock" only clears
        # the cosmetic rule inside the firewall container while real
        # traffic stays dropped at the host bridge.
        docker run --rm --net=host --cap-add=NET_ADMIN \
            alpine:3.19 sh -c "
                apk add --no-cache --quiet iptables >/dev/null 2>&1
                while iptables -C DOCKER-USER -s ${SRCIP} -j DROP 2>/dev/null; do
                    iptables -D DOCKER-USER -s ${SRCIP} -j DROP
                done
            " </dev/null 2>>${LOG_FILE} && {
            log "ENFORCEMENT: removed host DOCKER-USER rule(s) for ${SRCIP}"
        }

        log "IP ${SRCIP} unblocked on firewall (config + enforcement layers)"
        ;;

    *)
        log "ERROR: Unknown action: ${ACTION}"
        exit 1
        ;;
esac

exit 0
