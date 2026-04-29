#!/bin/bash
# =============================================================================
# SSL Certificate Generator - CIS 3353 Security Lab
# =============================================================================
# Generates self-signed certificates for Wazuh components.
# Run this BEFORE docker compose build/up.
# =============================================================================

CERT_DIR="$(dirname $0)/../../configs/ssl"
mkdir -p "${CERT_DIR}"
cd "${CERT_DIR}"

echo "============================================="
echo "  Generating SSL Certificates"
echo "  Output: ${CERT_DIR}"
echo "============================================="

# Root CA
echo "[1/5] Generating Root CA..."
openssl req -x509 -batch -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout root-ca-key.pem \
    -out root-ca.pem \
    -subj "/C=US/ST=TX/L=SanAntonio/O=CIS3353Lab/OU=Security/CN=CIS3353-RootCA"

# Wazuh Indexer certificate
echo "[2/5] Generating Wazuh Indexer certificate..."
openssl req -nodes -newkey rsa:2048 \
    -keyout indexer-key.pem \
    -out indexer.csr \
    -subj "/C=US/ST=TX/L=SanAntonio/O=CIS3353Lab/OU=Security/CN=wazuh-indexer"
openssl x509 -req -days 365 \
    -in indexer.csr \
    -CA root-ca.pem \
    -CAkey root-ca-key.pem \
    -CAcreateserial \
    -out indexer.pem

# Wazuh Dashboard certificate
echo "[3/5] Generating Wazuh Dashboard certificate..."
openssl req -nodes -newkey rsa:2048 \
    -keyout dashboard-key.pem \
    -out dashboard.csr \
    -subj "/C=US/ST=TX/L=SanAntonio/O=CIS3353Lab/OU=Security/CN=wazuh-dashboard"
openssl x509 -req -days 365 \
    -in dashboard.csr \
    -CA root-ca.pem \
    -CAkey root-ca-key.pem \
    -CAcreateserial \
    -out dashboard.pem

# Filebeat certificate (for Manager -> Indexer)
echo "[4/5] Generating Filebeat certificate..."
openssl req -nodes -newkey rsa:2048 \
    -keyout filebeat-key.pem \
    -out filebeat.csr \
    -subj "/C=US/ST=TX/L=SanAntonio/O=CIS3353Lab/OU=Security/CN=wazuh-manager"
openssl x509 -req -days 365 \
    -in filebeat.csr \
    -CA root-ca.pem \
    -CAkey root-ca-key.pem \
    -CAcreateserial \
    -out filebeat.pem

# Cleanup CSR files
echo "[5/5] Cleaning up..."
rm -f *.csr *.srl

echo ""
echo "============================================="
echo "  Certificates generated successfully!"
echo "============================================="
ls -la "${CERT_DIR}"/*.pem
echo ""
echo "  Next steps:"
echo "    1. docker compose build"
echo "    2. docker compose up -d"
