#!/bin/bash
# =============================================================================
# Default Firewall Rules (loaded from configs/firewall/)
# Add custom rules to this directory as .sh files
# They will be automatically loaded on container start
# =============================================================================

# Example: Block specific IP
# iptables -I FORWARD 1 -s 192.168.1.100 -j LOG_BLOCKED_ATTACKER

echo "[custom-rules] Default rules loaded (no custom rules configured)"
