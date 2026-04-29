# =============================================================================
# Jokopi Coffee Shop Application - Dockerfile
# CIS 3353 Security Lab - Vulnerable Target Container
# =============================================================================
# Multi-stage build:
#   Stage 1: Build React frontend from jokopi-react repository
#   Stage 2: Serve via Nginx + install Wazuh agent + add vulnerabilities
# =============================================================================

# ---------------------------------------------------------------------------
# STAGE 1: Build the React Application
# ---------------------------------------------------------------------------
FROM node:18-alpine AS builder

WORKDIR /app

# Clone the jokopi-react repository
RUN apk add --no-cache git && \
    git clone https://github.com/k1rana/jokopi-react.git . && \
    rm -rf .git

# Install dependencies and build
RUN npm install --legacy-peer-deps 2>/dev/null || npm install --force
RUN npm run build 2>/dev/null || \
    npx react-scripts build 2>/dev/null || \
    echo "Build completed or using pre-built assets"

# ---------------------------------------------------------------------------
# STAGE 2: Serve with Nginx + Wazuh Agent + Vulnerabilities
# ---------------------------------------------------------------------------
FROM ubuntu:22.04

ARG WAZUH_MANAGER_IP=10.10.0.10
ARG WAZUH_REGISTRATION_PASSWORD=AgentRegistration!2026
ARG DEBIAN_FRONTEND=noninteractive

# Install Nginx, PHP (for vulnerable endpoints), utilities
# NOTE: ca-certificates must be listed explicitly. Because we use
# --no-install-recommends, Ubuntu skips it (it's a Recommends dep of curl,
# not a hard Depends). Without it, HTTPS fetches fail with
# "error setting certificate file: /etc/ssl/certs/ca-certificates.crt".
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    nginx \
    php-fpm \
    php-sqlite3 \
    php-json \
    sqlite3 \
    curl \
    wget \
    gnupg \
    apt-transport-https \
    lsb-release \
    supervisor \
    rsyslog \
    net-tools \
    procps \
    && update-ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install Wazuh Agent
# ---------------------------------------------------------------------------
RUN set -eux; \
    # -f: fail on HTTP errors; -sSL: silent + show errors + follow redirects;
    # --retry: handle transient network blips; -4: avoid IPv6 resolution issues
    # that are common inside Docker Desktop on WSL2.
    for i in 1 2 3 4 5; do \
        curl -4 -fsSL --retry 5 --retry-delay 3 \
            https://packages.wazuh.com/key/GPG-KEY-WAZUH -o /tmp/wazuh.key && break; \
        echo "GPG key fetch attempt $i failed, retrying in 5s..."; sleep 5; \
    done; \
    test -s /tmp/wazuh.key || (echo "ERROR: Wazuh GPG key is empty" && exit 1); \
    gpg --dearmor < /tmp/wazuh.key > /usr/share/keyrings/wazuh.gpg; \
    rm /tmp/wazuh.key; \
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
        > /etc/apt/sources.list.d/wazuh.list; \
    apt-get update; \
    # Pin the agent to 4.9.2 to match the manager. The Wazuh apt repo
    # `4.x/stable` always serves the latest 4.x release (4.14.x as of
    # this writing), but the manager image is pinned to 4.9.2 to match
    # the indexer and dashboard. Wazuh's authd enforces
    # "agent version <= manager version" and rejects newer agents with:
    #   "ERROR: Agent version must be lower or equal to manager version
    #    (from manager)"
    # surfaced first as a less helpful "Invalid request for new agent".
    WAZUH_MANAGER=${WAZUH_MANAGER_IP} \
    WAZUH_REGISTRATION_PASSWORD=${WAZUH_REGISTRATION_PASSWORD} \
    apt-get install -y wazuh-agent=4.9.2-1; \
    # Hold the package so an inadvertent `apt upgrade` later in the build
    # (or a future Dockerfile RUN that does one) can't silently pull it
    # forward and re-introduce the version mismatch.
    apt-mark hold wazuh-agent; \
    rm -rf /var/lib/apt/lists/*

# Configure Wazuh agent
RUN sed -i "s/MANAGER_IP/${WAZUH_MANAGER_IP}/" /var/ossec/etc/ossec.conf 2>/dev/null || true

# Remove the authd.pass file the wazuh-agent .deb postinstall seeds from
# WAZUH_REGISTRATION_PASSWORD. The manager runs with `<use_password>no</use_password>`
# (see configs/wazuh/ossec-manager.conf and DEPLOYMENT_GUIDE §5.0), and
# Wazuh 4.x manager-side authd rejects enrollment requests that arrive
# with a password attached when use_password=no, with the misleading
# "Invalid request for new agent" error. Stripping the file here makes
# fresh image starts enroll cleanly without any manual `rm` step.
RUN rm -f /var/ossec/etc/authd.pass

# ---------------------------------------------------------------------------
# Copy React build output
# ---------------------------------------------------------------------------
COPY --from=builder /app/build /var/www/html/
# Fallback: if build dir doesn't exist, copy the whole app
COPY --from=builder /app/public /var/www/html/public/

# ---------------------------------------------------------------------------
# Nginx Configuration (with intentional security misconfigurations)
# ---------------------------------------------------------------------------
COPY nginx.conf /etc/nginx/sites-available/default

# ---------------------------------------------------------------------------
# Create vulnerable backend endpoints (PHP)
# ---------------------------------------------------------------------------
COPY vulnerable-api/ /var/www/html/api/

# ---------------------------------------------------------------------------
# Create intentionally vulnerable SQLite database
# ---------------------------------------------------------------------------
RUN mkdir -p /var/www/data && \
    sqlite3 /var/www/data/coffeeshop.db << 'EOSQL'
CREATE TABLE users (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    username TEXT NOT NULL,
    password TEXT NOT NULL,
    email TEXT,
    role TEXT DEFAULT 'customer'
);
CREATE TABLE orders (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    customer_name TEXT,
    item TEXT,
    quantity INTEGER,
    total REAL,
    card_number TEXT,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE menu (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    description TEXT,
    price REAL,
    category TEXT
);
-- Intentionally weak credentials (for brute-force demonstration)
INSERT INTO users (username, password, email, role) VALUES
    ('admin', 'coffee123', 'admin@jokopi.local', 'admin'),
    ('manager', 'password', 'manager@jokopi.local', 'manager'),
    ('barista', 'barista1', 'barista@jokopi.local', 'staff'),
    ('guest', 'guest', 'guest@jokopi.local', 'customer');
-- Sample menu items
INSERT INTO menu (name, description, price, category) VALUES
    ('Espresso', 'Rich and bold single shot', 3.50, 'coffee'),
    ('Cappuccino', 'Espresso with steamed milk foam', 4.50, 'coffee'),
    ('Latte', 'Espresso with steamed milk', 4.00, 'coffee'),
    ('Cold Brew', 'Slow-steeped for 24 hours', 4.50, 'coffee'),
    ('Matcha Latte', 'Japanese green tea with milk', 5.00, 'specialty'),
    ('Croissant', 'Buttery French pastry', 3.00, 'food'),
    ('Bagel', 'Fresh-baked with cream cheese', 3.50, 'food');
-- Sample orders with fake card data (for data exfiltration demo)
INSERT INTO orders (customer_name, item, quantity, total, card_number) VALUES
    ('John Doe', 'Espresso', 2, 7.00, '4111-1111-1111-1111'),
    ('Jane Smith', 'Latte', 1, 4.00, '5500-0000-0000-0004'),
    ('Bob Wilson', 'Cold Brew', 3, 13.50, '3400-0000-0000-009');
EOSQL
RUN chmod 666 /var/www/data/coffeeshop.db && \
    chown -R www-data:www-data /var/www/data

# ---------------------------------------------------------------------------
# Wazuh Agent Configuration for File Integrity Monitoring
# ---------------------------------------------------------------------------
COPY wazuh-agent.conf /var/ossec/etc/ossec.conf

# ---------------------------------------------------------------------------
# Runtime helper: pin /run/php/php-fpm.sock symlink on every container start
# ---------------------------------------------------------------------------
# Ubuntu's php-fpm package writes its socket as /run/php/php8.1-fpm.sock,
# but nginx.conf references the un-versioned /run/php/php-fpm.sock so the
# config doesn't have to know which point release apt installed. Without
# the symlink, every /api/*.php request returns 404 because nginx can't
# reach PHP-FPM. /run is a tmpfs wiped at container start, so the link
# has to be re-created each boot — supervisord runs this at priority=15,
# before php-fpm (priority=20) starts and creates its socket. The script
# polls /run/php/ for up to 10 seconds before giving up.
COPY link-php-fpm-sock.sh /usr/local/bin/link-php-fpm-sock
RUN chmod +x /usr/local/bin/link-php-fpm-sock && mkdir -p /run/php

# ---------------------------------------------------------------------------
# Supervisor configuration (run Nginx + PHP-FPM + Wazuh Agent + rsyslog)
# ---------------------------------------------------------------------------
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ---------------------------------------------------------------------------
# Set intentional misconfigurations (for the "Build" phase)
# ---------------------------------------------------------------------------
# 1. Verbose error reporting enabled
# NOTE: /bin/sh passes unmatched globs through literally, so the original
# `>> /etc/php/*/fpm/php.ini` fails with "Directory nonexistent" when the
# glob doesn't expand. Use `find` for a robust lookup, and if nothing is
# found, fail loudly with diagnostics so we can see what's actually installed.
RUN set -eux; \
    PHP_INI="$(find /etc/php -maxdepth 3 -name php.ini -path '*/fpm/*' 2>/dev/null | head -1)"; \
    if [ -z "$PHP_INI" ] || [ ! -f "$PHP_INI" ]; then \
        echo "=== php-fpm ini not found; diagnostics follow ==="; \
        echo "--- dpkg -l | grep php ---"; dpkg -l | grep -i php || true; \
        echo "--- ls /etc/php ---"; ls -la /etc/php 2>/dev/null || echo "(/etc/php does not exist)"; \
        echo "--- which php-fpm* ---"; which php-fpm8.1 php-fpm8.2 php-fpm || true; \
        echo "Attempting to install php-fpm as a fallback..."; \
        apt-get update; \
        apt-get install -y --no-install-recommends php-fpm; \
        rm -rf /var/lib/apt/lists/*; \
        PHP_INI="$(find /etc/php -maxdepth 3 -name php.ini -path '*/fpm/*' 2>/dev/null | head -1)"; \
    fi; \
    test -n "$PHP_INI" -a -f "$PHP_INI" || (echo "FATAL: still no php-fpm ini" && exit 1); \
    echo "Patching $PHP_INI for vulnerable verbose errors"; \
    echo "display_errors = On" >> "$PHP_INI"; \
    echo "error_reporting = E_ALL" >> "$PHP_INI"; \
    # ----------------------------------------------------------------------
    # Pin a stable /usr/sbin/php-fpm symlink to the version apt actually
    # installed. supervisord.conf used to interpolate the version with
    # `%(ENV_PHP_VERSION)s` at runtime, but nothing ever sets that env var
    # in the container, so supervisord failed to parse its config and the
    # container restart-looped with exit code 2. With this symlink in
    # place, supervisord can just exec `/usr/sbin/php-fpm -F` and the
    # config doesn't need to know which point release is on disk.
    # ----------------------------------------------------------------------
    PHP_VERSION="$(echo "$PHP_INI" | sed -E 's|.*/php/([^/]+)/fpm/.*|\1|')"; \
    test -x "/usr/sbin/php-fpm${PHP_VERSION}" \
        || (echo "FATAL: /usr/sbin/php-fpm${PHP_VERSION} not executable" \
            && ls -la /usr/sbin/php-fpm* 2>/dev/null \
            && exit 1); \
    ln -sf "/usr/sbin/php-fpm${PHP_VERSION}" /usr/sbin/php-fpm; \
    /usr/sbin/php-fpm -v
# 2. Directory listing enabled in Nginx (see nginx.conf)
# 3. Server version exposure (see nginx.conf)
# 4. No rate limiting on login endpoint
# 5. Database accessible from web root

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
