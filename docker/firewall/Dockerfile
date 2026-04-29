# =============================================================================
# Firewall Gateway Container - Dockerfile
# CIS 3353 Security Lab
# =============================================================================
# This container replicates pfSense-style firewall functionality in Docker:
#   - iptables-based stateful packet filtering
#   - NAT and port forwarding
#   - Rate limiting (DoS mitigation)
#   - Comprehensive logging (for Wazuh ingestion)
#   - Web management UI (lighttpd + PHP)
#   - Active response integration (Wazuh triggers IP blocks)
#   - Suricata IDS integration
#
# NOTE: pfSense CE does not have an official Docker image. This container
# provides equivalent functionality suitable for the Security+ lab.
# =============================================================================

FROM alpine:3.19

# Install required packages
RUN apk add --no-cache \
    iptables \
    ip6tables \
    nftables \
    iproute2 \
    iputils \
    tcpdump \
    conntrack-tools \
    lighttpd \
    php83 \
    php83-cgi \
    php83-json \
    php83-session \
    php83-sqlite3 \
    bash \
    curl \
    wget \
    jq \
    openssh-client \
    rsyslog \
    logrotate \
    supervisor \
    htop \
    net-tools \
    bind-tools \
    suricata \
    && mkdir -p /var/log/firewall \
    && mkdir -p /var/log/suricata \
    && mkdir -p /etc/firewall/rules.d \
    && mkdir -p /opt/active-response \
    && mkdir -p /var/www/html \
    && mkdir -p /run/lighttpd

# ---------------------------------------------------------------------------
# Configure rsyslog for firewall logging
# ---------------------------------------------------------------------------
COPY rsyslog-firewall.conf /etc/rsyslog.d/firewall.conf

# ---------------------------------------------------------------------------
# Firewall initialization script
# ---------------------------------------------------------------------------
COPY firewall-init.sh /opt/firewall-init.sh
COPY firewall-rules.sh /opt/firewall-rules.sh
RUN chmod +x /opt/firewall-init.sh /opt/firewall-rules.sh

# ---------------------------------------------------------------------------
# Rate limiting configuration
# ---------------------------------------------------------------------------
COPY rate-limit.sh /opt/rate-limit.sh
RUN chmod +x /opt/rate-limit.sh

# ---------------------------------------------------------------------------
# Web Management UI
# ---------------------------------------------------------------------------
COPY web-ui/ /var/www/html/
COPY lighttpd.conf /etc/lighttpd/lighttpd.conf

# ---------------------------------------------------------------------------
# Active response integration script
# ---------------------------------------------------------------------------
COPY active-response-handler.sh /opt/active-response/handler.sh
RUN chmod +x /opt/active-response/handler.sh

# ---------------------------------------------------------------------------
# Suricata IDS basic configuration
# ---------------------------------------------------------------------------
COPY suricata.yaml /etc/suricata/suricata.yaml

# ---------------------------------------------------------------------------
# Supervisor to run all services
# ---------------------------------------------------------------------------
COPY supervisord.conf /etc/supervisor.d/firewall.ini

EXPOSE 80 443 8443

HEALTHCHECK --interval=30s --timeout=10s --retries=3 \
    CMD iptables -L -n > /dev/null 2>&1

ENTRYPOINT ["/opt/firewall-init.sh"]
