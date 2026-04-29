#!/bin/bash
# =============================================================================
# Lab Setup Script - CIS 3353 Coffee Shop Security Lab
# =============================================================================
# One-command setup for the entire lab environment.
# Usage: ./scripts/setup/lab-setup.sh
# =============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "${PROJECT_DIR}"

echo ""
echo "  ====================================================="
echo "  CIS 3353 - Coffee Shop Security Lab Setup"
echo "  ====================================================="
echo ""

# ---------------------------------------------------------------------------
# Prerequisites Check
# ---------------------------------------------------------------------------
echo "[1/6] Checking prerequisites..."

if ! command -v docker &> /dev/null; then
    echo "  ERROR: Docker is not installed. Install Docker Desktop first."
    echo "  https://docs.docker.com/get-docker/"
    exit 1
fi
echo "  Docker: $(docker --version)"

if ! command -v docker compose &> /dev/null && ! command -v docker-compose &> /dev/null; then
    echo "  ERROR: Docker Compose is not installed."
    exit 1
fi
echo "  Docker Compose: available"

# Check available memory
TOTAL_MEM=$(free -g 2>/dev/null | awk '/^Mem:/{print $2}' || sysctl -n hw.memsize 2>/dev/null | awk '{printf "%d", $1/1073741824}' || echo "unknown")
echo "  Total RAM: ${TOTAL_MEM}GB"
if [ "${TOTAL_MEM}" != "unknown" ] && [ "${TOTAL_MEM}" -lt 8 ]; then
    echo "  WARNING: Wazuh recommends at least 8GB RAM. You have ${TOTAL_MEM}GB."
    echo "  The lab may run slowly. Consider closing other applications."
fi

# Check Docker allocated memory
echo "  Docker disk usage:"
docker system df 2>/dev/null | head -5

# ---------------------------------------------------------------------------
# Generate SSL Certificates
# ---------------------------------------------------------------------------
echo ""
echo "[2/6] Generating SSL certificates..."
if [ -f "${PROJECT_DIR}/configs/ssl/root-ca.pem" ]; then
    echo "  Certificates already exist. Skipping."
else
    bash "${PROJECT_DIR}/scripts/setup/generate-certs.sh"
fi

# ---------------------------------------------------------------------------
# Make scripts executable
# ---------------------------------------------------------------------------
echo ""
echo "[3/6] Setting file permissions..."
find "${PROJECT_DIR}/scripts" -name "*.sh" -exec chmod +x {} \;
find "${PROJECT_DIR}/docker" -name "*.sh" -exec chmod +x {} \;
echo "  All .sh files are now executable."

# ---------------------------------------------------------------------------
# Build Docker Images
# ---------------------------------------------------------------------------
echo ""
echo "[4/6] Building Docker images (this may take 10-20 minutes)..."
docker compose build --no-cache 2>&1 | tail -20

# ---------------------------------------------------------------------------
# Start the Lab
# ---------------------------------------------------------------------------
echo ""
echo "[5/6] Starting all containers..."
docker compose up -d 2>&1

# ---------------------------------------------------------------------------
# Wait for services and verify
# ---------------------------------------------------------------------------
echo ""
echo "[6/6] Waiting for services to start..."
echo "  (Wazuh may take 2-3 minutes to fully initialize)"

# Wait for each service
echo -n "  Firewall: "
for i in $(seq 1 30); do
    if docker exec pfsense-firewall iptables -L -n &>/dev/null; then
        echo "READY"
        break
    fi
    sleep 2
    echo -n "."
done

echo -n "  Jokopi App: "
for i in $(seq 1 30); do
    if curl -s http://localhost:8080 &>/dev/null; then
        echo "READY"
        break
    fi
    sleep 2
    echo -n "."
done

echo -n "  Wazuh Manager: "
for i in $(seq 1 60); do
    if docker exec wazuh-manager /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "is running"; then
        echo "READY"
        break
    fi
    sleep 3
    echo -n "."
done

echo ""
echo "  ====================================================="
echo "  LAB IS READY!"
echo "  ====================================================="
echo ""
echo "  Access Points:"
echo "    Coffee Shop App:      http://localhost:8080"
echo "    Firewall Dashboard:   http://localhost:8443"
echo "    Wazuh Dashboard:      https://localhost:5601"
echo "      Username: admin"
echo "      Password: SecretPassword!123"
echo ""
echo "  Attacker Shell:"
echo "    docker exec -it kali-attacker /bin/bash"
echo ""
echo "  Quick Start:"
echo "    1. Open Wazuh Dashboard in browser"
echo "    2. Attach to Kali:  docker exec -it kali-attacker bash"
echo "    3. Run attacks:     bash /opt/attacks/01-reconnaissance.sh"
echo "    4. Watch alerts appear in Wazuh Dashboard"
echo ""
echo "  Container Status:"
docker compose ps
echo ""
