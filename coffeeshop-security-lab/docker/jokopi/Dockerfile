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
RUN apt-get update && apt-get install -y --no-install-recommends \
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
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Install Wazuh Agent
# ---------------------------------------------------------------------------
RUN curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --dearmor -o /usr/share/keyrings/wazuh.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/wazuh.gpg] https://packages.wazuh.com/4.x/apt/ stable main" \
    > /etc/apt/sources.list.d/wazuh.list && \
    apt-get update && \
    WAZUH_MANAGER=${WAZUH_MANAGER_IP} \
    WAZUH_REGISTRATION_PASSWORD=${WAZUH_REGISTRATION_PASSWORD} \
    apt-get install -y wazuh-agent && \
    rm -rf /var/lib/apt/lists/*

# Configure Wazuh agent
RUN sed -i "s/MANAGER_IP/${WAZUH_MANAGER_IP}/" /var/ossec/etc/ossec.conf 2>/dev/null || true

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
# Supervisor configuration (run Nginx + PHP-FPM + Wazuh Agent + rsyslog)
# ---------------------------------------------------------------------------
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# ---------------------------------------------------------------------------
# Set intentional misconfigurations (for the "Build" phase)
# ---------------------------------------------------------------------------
# 1. Verbose error reporting enabled
RUN echo "display_errors = On" >> /etc/php/*/fpm/php.ini && \
    echo "error_reporting = E_ALL" >> /etc/php/*/fpm/php.ini
# 2. Directory listing enabled in Nginx (see nginx.conf)
# 3. Server version exposure (see nginx.conf)
# 4. No rate limiting on login endpoint
# 5. Database accessible from web root

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
