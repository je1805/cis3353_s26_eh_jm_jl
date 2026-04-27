# =============================================================================
# Kali Linux Attacker Container - Dockerfile
# CIS 3353 Security Lab
# =============================================================================
# Pre-configured attacker machine with all tools needed for:
#   - Web application attacks (SQLi, XSS, brute-force, directory traversal)
#   - Network attacks (port scanning, SYN flood, ARP spoofing, enumeration)
#   - Traffic analysis (Wireshark/tshark, tcpdump)
#   - Documentation (screenshots, report generation)
# =============================================================================

FROM kalilinux/kali-rolling

ENV DEBIAN_FRONTEND=noninteractive

# ---------------------------------------------------------------------------
# Install attack tools in groups
# ---------------------------------------------------------------------------

# Web Application Testing Tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    sqlmap \
    nikto \
    dirb \
    gobuster \
    whatweb \
    wfuzz \
    curl \
    wget \
    httpie \
    && rm -rf /var/lib/apt/lists/*

# Network Attack & Reconnaissance Tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    hping3 \
    netcat-openbsd \
    dsniff \
    ettercap-text-only \
    arpwatch \
    arping \
    traceroute \
    whois \
    dnsutils \
    net-tools \
    iproute2 \
    iputils-ping \
    tcpdump \
    tshark \
    && rm -rf /var/lib/apt/lists/*

# Brute-Force & Password Tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    hydra \
    medusa \
    john \
    wordlists \
    seclists \
    crunch \
    && rm -rf /var/lib/apt/lists/*

# General Utilities
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    nano \
    less \
    jq \
    python3 \
    python3-pip \
    python3-requests \
    git \
    bash-completion \
    man-db \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Create working directories
# ---------------------------------------------------------------------------
RUN mkdir -p /root/results/{scans,exploits,evidence,reports} \
    && mkdir -p /opt/attacks \
    && mkdir -p /root/wordlists

# ---------------------------------------------------------------------------
# Prepare common wordlists
# ---------------------------------------------------------------------------
RUN if [ -f /usr/share/wordlists/rockyou.txt.gz ]; then \
        gunzip /usr/share/wordlists/rockyou.txt.gz 2>/dev/null || true; \
    fi && \
    # Create a small custom wordlist for quick brute-force demos
    cat > /root/wordlists/coffee-passwords.txt << 'EOF'
admin
password
123456
coffee
coffee123
barista
espresso
latte
cappuccino
jokopi
jokopi123
password1
admin123
letmein
welcome
guest
EOF

# ---------------------------------------------------------------------------
# Create a quick-reference cheat sheet
# ---------------------------------------------------------------------------
COPY attack-cheatsheet.md /root/ATTACK_CHEATSHEET.md

# ---------------------------------------------------------------------------
# Custom bash prompt for the attacker
# ---------------------------------------------------------------------------
RUN echo 'export PS1="\[\e[31m\]kali@attacker\[\e[0m\]:\[\e[34m\]\w\[\e[0m\]# "' >> /root/.bashrc && \
    echo 'echo ""' >> /root/.bashrc && \
    echo 'echo "  =================================================="' >> /root/.bashrc && \
    echo 'echo "  CIS 3353 - Kali Attacker Container"' >> /root/.bashrc && \
    echo 'echo "  Target: $TARGET_IP (Jokopi Coffee Shop)"' >> /root/.bashrc && \
    echo 'echo "  Network: $NETWORK_RANGE"' >> /root/.bashrc && \
    echo 'echo "  =================================================="' >> /root/.bashrc && \
    echo 'echo "  Attack scripts:  /opt/attacks/"' >> /root/.bashrc && \
    echo 'echo "  Results folder:  /root/results/"' >> /root/.bashrc && \
    echo 'echo "  Cheat sheet:     cat ~/ATTACK_CHEATSHEET.md"' >> /root/.bashrc && \
    echo 'echo ""' >> /root/.bashrc

WORKDIR /root

CMD ["/bin/bash"]
