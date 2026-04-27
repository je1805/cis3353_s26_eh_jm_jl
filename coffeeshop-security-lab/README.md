# CIS 3353 - Secure Coffee Shop Security Lab

**University of the Incarnate Word | Spring 2026**

A fully containerized cybersecurity lab that simulates a vulnerable coffee shop web application monitored by Wazuh SIEM and protected by a pfSense-style firewall. Built for the CIS 3353 Computer Systems Security group project.

---

## Table of Contents

1. [What This Project Does](#what-this-project-does)
2. [Key Concepts for Beginners](#key-concepts-for-beginners)
3. [Architecture Overview](#architecture-overview)
4. [How the Components Connect](#how-the-components-connect)
5. [Prerequisites](#prerequisites)
6. [Step-by-Step Setup](#step-by-step-setup)
7. [Accessing the Lab](#accessing-the-lab)
8. [Running the Attack Demonstrations](#running-the-attack-demonstrations)
9. [Understanding the Defenses](#understanding-the-defenses)
10. [Project File Map](#project-file-map)
11. [Common Commands Reference](#common-commands-reference)
12. [Troubleshooting](#troubleshooting)
13. [Course Module Mapping](#course-module-mapping)
14. [Team Members](#team-members)

---

## What This Project Does

Imagine a small coffee shop called "Jokopi" that runs a website where customers can browse the menu, place orders, and leave reviews. Like many small businesses, Jokopi's website has security problems: weak passwords, no input validation, and no monitoring. An attacker could steal customer data, bring down the website, or deface it — and nobody would even know.

This project builds that entire scenario in Docker containers on your computer. You will:

1. **Build** the coffee shop's environment (the website, network, and infrastructure)
2. **Attack** it using real penetration testing tools from a Kali Linux container, demonstrating how vulnerable it is
3. **Defend** it by deploying a SIEM (Wazuh) that watches everything and a firewall (pfSense-style) that blocks attackers automatically

The key moment is when Wazuh detects an attack and tells the firewall to block the attacker's IP address without any human intervention. That is the automated incident response pipeline this project demonstrates.

---

## Key Concepts for Beginners

### What is Docker?

Docker is a tool that lets you run applications in isolated "containers." Think of a container like a lightweight virtual machine — it has its own operating system, its own files, and its own network address, but it shares the host computer's resources. Instead of installing 6 separate virtual machines in VirtualBox (which would use 30+ GB of RAM), Docker lets us run all 6 services using a fraction of the resources.

Key Docker terms you will see in this project:

- **Container**: A running instance of an application. Each box in our architecture (Jokopi app, Wazuh, firewall, Kali) is a container.
- **Image**: A blueprint for a container. A Dockerfile defines how to build an image.
- **Dockerfile**: A text file with instructions to build an image. It lists what operating system to use, what software to install, and what files to copy.
- **Docker Compose**: A tool that lets you define and run multiple containers together. Our `docker-compose.yml` file defines all 6 containers, their network, and how they connect.
- **Volume**: Persistent storage for a container. When a container stops, its data normally disappears. Volumes keep data around.
- **Network**: Docker can create virtual networks that containers connect to. Our `coffeeshop-net` network gives every container a static IP address.

### What is Wazuh?

Wazuh is an open-source Security Information and Event Management (SIEM) platform. In plain English, it is a security guard that watches everything happening on your systems and alerts you when something suspicious occurs.

Wazuh has three parts in our setup:

- **Wazuh Manager** (10.10.0.10): The brain. It receives log data from agents installed on monitored systems, analyzes it against detection rules, and triggers responses when threats are found.
- **Wazuh Indexer** (10.10.0.12): The memory. It stores all the security events in a searchable database (built on OpenSearch, a fork of Elasticsearch).
- **Wazuh Dashboard** (10.10.0.11): The eyes. A web interface where you can see alerts, build dashboards, and investigate incidents. You access it in your browser.

Wazuh also has **agents** — small programs installed on the systems you want to monitor. We install a Wazuh agent inside the Jokopi coffee shop container so that Wazuh can see its web server logs, file changes, and system events.

### What is pfSense (and our Firewall Container)?

pfSense is a popular open-source firewall and router. It controls what network traffic is allowed and what is blocked. In a real office, pfSense would sit between the internet and the internal network, inspecting every packet.

Since pfSense does not have an official Docker image, our project uses an Alpine Linux container configured with `iptables` (the Linux firewall tool) to provide the same functionality. For your project presentation, you can describe it as a "pfSense-style firewall gateway" because it implements the same core features:

- Stateful packet filtering (tracks connections, not just individual packets)
- Default-deny policy (blocks everything unless explicitly allowed)
- NAT and port forwarding
- Rate limiting (prevents flood attacks)
- Logging (sends firewall events to Wazuh)
- Web management UI (a dashboard to manage rules)
- Active response integration (Wazuh can tell it to block IPs)

### What is Kali Linux?

Kali Linux is a Linux distribution designed for penetration testing and security auditing. It comes pre-loaded with hundreds of hacking tools. In our lab, the Kali container acts as the attacker. You will open a shell inside it and use tools like `nmap` (port scanner), `sqlmap` (SQL injection automation), `hydra` (password brute-forcer), and `hping3` (packet crafter for DoS attacks).

---

## Architecture Overview

All six containers live on a single Docker network called `coffeeshop-net` with subnet `10.10.0.0/24`. Each container has a fixed IP address so they can always find each other.

```
                        YOUR COMPUTER (Host)
                    ┌────────────────────────────────────────────────────────┐
                    │                                                        │
  localhost:8080 ───┤──► [pfSense Firewall]  10.10.0.1                      │
  localhost:8443 ───┤      │  Gateway for all containers                    │
  localhost:5601 ───┤      │  Stateful firewall + rate limiting             │
                    │      │  Active response (auto-blocks attackers)       │
                    │      │                                                 │
                    │      ├──── coffeeshop-net (10.10.0.0/24) ────────┐   │
                    │      │                                            │   │
                    │      ▼                                            │   │
                    │  [Jokopi Coffee Shop]  10.10.0.20                │   │
                    │      │  React website + vulnerable PHP API       │   │
                    │      │  SQLite database with fake customer data  │   │
                    │      │  Wazuh Agent installed (reports to SIEM)  │   │
                    │      │                                            │   │
                    │      ▼                                            │   │
                    │  [Wazuh Manager]  10.10.0.10                     │   │
                    │      │  Receives agent data                      │   │
                    │      │  Processes 30+ custom detection rules     │   │
                    │      │  Triggers active response (blocks IPs)    │   │
                    │      │                                            │   │
                    │      ├──► [Wazuh Indexer]   10.10.0.12           │   │
                    │      │     Stores all security events            │   │
                    │      │                                            │   │
                    │      └──► [Wazuh Dashboard] 10.10.0.11           │   │
                    │            Web UI for monitoring & investigation  │   │
                    │                                                   │   │
                    │  [Kali Linux Attacker]  10.10.0.100              │   │
                    │      Penetration testing tools                    │   │
                    │      nmap, sqlmap, hydra, hping3, nikto          │   │
                    │      Pre-built attack scripts                    │   │
                    └────────────────────────────────────────────────────┘
```

| Container | Role | IP Address | Ports on Host |
|---|---|---|---|
| pfsense-firewall | Firewall & Gateway | 10.10.0.1 | 8443 (mgmt UI), 8080 (→app), 5601 (→Wazuh) |
| wazuh-manager | SIEM Engine | 10.10.0.10 | 1514 (agent), 1515 (enrollment), 55000 (API) |
| wazuh-dashboard | SIEM Web UI | 10.10.0.11 | via firewall on 5601 |
| wazuh-indexer | Log Storage (OpenSearch) | 10.10.0.12 | 9200 (internal) |
| jokopi-coffeeshop | Vulnerable Coffee Shop | 10.10.0.20 | via firewall on 8080 |
| kali-attacker | Attacker Machine | 10.10.0.100 | none (interactive shell only) |

---

## How the Components Connect

Understanding the data flow is critical for your project presentation. Here is what happens during a typical attack-and-defend cycle:

### Normal Traffic Flow
1. A user (or attacker) sends an HTTP request to `localhost:8080`
2. Docker maps port 8080 on your computer to port 80 on the **firewall container**
3. The firewall applies its rules (allow HTTP to Jokopi, log the connection)
4. The firewall forwards the request to the **Jokopi app** at 10.10.0.20:80
5. Nginx inside Jokopi serves the React frontend or routes to the PHP API
6. The response travels back through the firewall to the user

### Attack Detection Flow
1. The **Kali attacker** (10.10.0.100) sends a SQL injection payload to Jokopi's search API
2. Nginx on **Jokopi** logs the request to `/var/log/nginx/access.log`
3. The **Wazuh agent** on Jokopi reads the log entry in real time
4. The agent sends it to the **Wazuh Manager** (10.10.0.10) over port 1514
5. The Manager checks the log against its detection rules
6. Custom rule `100100` matches the SQL injection pattern and generates a level-12 alert
7. The alert appears in the **Wazuh Dashboard** (viewable at `localhost:5601`)
8. If the automated tool `sqlmap` is detected (rule `100102`), it triggers rule `100301`

### Active Response Flow (Automated Defense)
1. Rule `100301` is configured to trigger the `block-ip-firewall` active response
2. The Wazuh Manager runs the `/var/ossec/active-response/bin/block-ip-firewall.sh` script
3. That script connects to the **firewall container** and runs:
   `/opt/active-response/handler.sh block 10.10.0.100 7200`
4. The firewall inserts an `iptables` rule at the top of the FORWARD chain:
   `iptables -I FORWARD 1 -s 10.10.0.100 -j LOG_BLOCKED_ATTACKER`
5. All future traffic from Kali (10.10.0.100) is now **dropped and logged**
6. After the timeout (7200 seconds = 2 hours), the block is automatically removed

This is the "Wazuh detects → pfSense blocks" automated pipeline that is the core of the project.

---

## Prerequisites

Before you begin, make sure you have:

1. **Docker Desktop** installed and running
   - Download from [https://docs.docker.com/get-docker/](https://docs.docker.com/get-docker/)
   - Windows: Use WSL 2 backend (Docker Desktop will prompt you)
   - Mac: Works on both Intel and Apple Silicon
   - Linux: Install Docker Engine + Docker Compose plugin

2. **At least 8 GB of RAM allocated to Docker**
   - Wazuh is memory-intensive. With less than 8 GB, the indexer may crash.
   - In Docker Desktop: Settings → Resources → Memory → set to 8 GB or more
   - If your computer has only 8 GB total, close all other applications before running

3. **At least 15 GB of free disk space**
   - The Kali image alone is ~2 GB; Wazuh images are ~1.5 GB total; built images add more

4. **A terminal / command line**
   - Windows: PowerShell or WSL 2 terminal
   - Mac: Terminal.app
   - Linux: Any terminal

5. **openssl** (for certificate generation)
   - Usually pre-installed on Mac/Linux
   - On Windows, use Git Bash (comes with Git for Windows) or WSL

---

## Step-by-Step Setup

### Step 1: Download the Project

Copy the `coffeeshop-security-lab` folder to your computer, or clone it from your GitHub repository.

```bash
cd ~/Desktop  # or wherever you want the project
# If using git:
# git clone https://github.com/YOUR_REPO/cis3353_s26_XX_XX_XX.git
# cd cis3353_s26_XX_XX_XX
```

### Step 2: Make Scripts Executable

```bash
cd coffeeshop-security-lab
chmod +x scripts/setup/*.sh
chmod +x scripts/attacks/*.sh
chmod +x scripts/active-response/*.sh
chmod +x docker/firewall/*.sh
```

On Windows (PowerShell), this step is not needed — Docker handles it inside Linux containers.

### Step 3: Generate SSL Certificates

Wazuh components communicate over TLS. We need to generate self-signed certificates before building.

```bash
bash scripts/setup/generate-certs.sh
```

This creates certificate files in `configs/ssl/`. You should see:
- `root-ca.pem` and `root-ca-key.pem` (Certificate Authority)
- `indexer.pem` and `indexer-key.pem` (Wazuh Indexer)
- `dashboard.pem` and `dashboard-key.pem` (Wazuh Dashboard)
- `filebeat.pem` and `filebeat-key.pem` (Manager → Indexer connection)

### Step 4: Build All Docker Images

```bash
docker compose build
```

This will take **10-20 minutes** the first time because it downloads base images and installs packages. Subsequent builds are faster thanks to Docker's layer caching.

What happens during the build:
- **Jokopi**: Downloads Node.js, clones the React app, builds it, installs Nginx + PHP + Wazuh agent, creates the vulnerable database
- **Firewall**: Downloads Alpine Linux, installs iptables + Suricata + lighttpd, copies firewall rules and the web UI
- **Kali**: Downloads kali-rolling image (~2 GB), installs nmap, sqlmap, hydra, nikto, hping3, and other tools

The Wazuh containers (manager, indexer, dashboard) use pre-built official images, so they are pulled directly — no build step needed.

### Step 5: Start the Lab

```bash
docker compose up -d
```

The `-d` flag runs containers in the background (detached mode). Docker will:
1. Create the `coffeeshop-net` bridge network
2. Start the Wazuh Indexer first (other services depend on it)
3. Start the Wazuh Manager (depends on indexer being healthy)
4. Start the Wazuh Dashboard (depends on both manager and indexer)
5. Start the Firewall, Jokopi app, and Kali attacker

### Step 6: Wait for Services to Initialize

Wazuh takes 2-3 minutes to fully start. Check the status with:

```bash
docker compose ps
```

All containers should show `Up` or `Up (healthy)`. If the Wazuh manager shows `Up (health: starting)`, wait another minute and check again.

You can also watch the logs in real time:
```bash
docker compose logs -f wazuh-manager
```

Press `Ctrl+C` to stop following logs.

### Step 7: Verify Everything Works

```bash
# Test the coffee shop app
curl http://localhost:8080

# Test the firewall UI
curl http://localhost:8443

# Test Wazuh Dashboard (will show HTML)
curl -sk https://localhost:5601
```

If all three return HTML content, your lab is ready.

---

## Accessing the Lab

### Coffee Shop Website
- **URL**: [http://localhost:8080](http://localhost:8080)
- This is the Jokopi React app served through the firewall
- The vulnerable API endpoints are at `/api/login.php`, `/api/search.php`, `/api/orders.php`, `/api/comment.php`

### Wazuh SIEM Dashboard
- **URL**: [https://localhost:5601](https://localhost:5601)
- **Username**: `admin`
- **Password**: `SecretPassword!123`
- Your browser will show a certificate warning (because we use self-signed certs). Click "Advanced" → "Proceed" to continue.
- Navigate to **Security Events** to see alerts, or **Dashboards** to build visualizations.

### Firewall Management UI
- **URL**: [http://localhost:8443](http://localhost:8443)
- Shows current iptables rules, blocked IPs, and active response logs
- You can manually block/unblock IPs from this interface

### Kali Attacker Shell
```bash
docker exec -it kali-attacker bash
```
This drops you into a root shell inside the Kali container. From here you can run all attack tools. Type `cat ~/ATTACK_CHEATSHEET.md` for a quick reference of attack commands.

---

## Running the Attack Demonstrations

The attack scripts are designed to be run in order. Each script is well-commented and prints what it is doing.

### From inside the Kali container:

```bash
# Step into Kali
docker exec -it kali-attacker bash

# Phase 1: Reconnaissance (discover the network and services)
bash /opt/attacks/01-reconnaissance.sh

# Phase 2: Web application attacks (SQLi, XSS, directory traversal)
bash /opt/attacks/02-web-attacks.sh

# Phase 3: Brute-force the login page
bash /opt/attacks/03-brute-force.sh

# Phase 4: Network-level attacks (SYN flood, HTTP flood)
bash /opt/attacks/04-network-attacks.sh

# Phase 5: Verify that defenses are working
bash /opt/attacks/05-verify-defenses.sh
```

### What to watch while attacks run:

Open the **Wazuh Dashboard** ([https://localhost:5601](https://localhost:5601)) in your browser. Navigate to **Security Events** and watch alerts appear in real time as the attack scripts execute. You will see:

- Rule 100100-100102: SQL injection detections
- Rule 100110-100111: XSS detections
- Rule 100121-100123: Brute-force detections
- Rule 100200: Port scan detections
- Rule 100210-100212: DoS detections
- Rule 100300-100303: Active response triggers (auto-blocks)

Also check the **Firewall UI** ([http://localhost:8443](http://localhost:8443)) to see when IPs get blocked by the active response system.

---

## Understanding the Defenses

### Wazuh Detection Rules

Our custom rules are defined in `configs/wazuh/rules/local_rules.xml`. Each rule has:

- **ID**: A unique number (100100-100303)
- **Level**: Severity from 0-15 (higher = more severe). Level 12+ triggers attention; level 15 triggers active response.
- **Pattern Match**: Regular expressions that match known attack signatures in log entries
- **Group Tags**: Categories like `sqli`, `brute-force`, `dos` for organizing alerts

Example: Rule 100122 fires when it sees 5 events matching rule 100121 (individual failed login) from the same source IP within 60 seconds. This is a frequency-based correlation rule — a core SIEM concept.

### Firewall Rules

The firewall implements a **default-deny** policy, meaning all traffic is blocked unless an explicit rule allows it. Key rules include:

- Allow HTTP (port 80) to the Jokopi app (so the website is accessible)
- Allow Jokopi to talk to Wazuh Manager on ports 1514/1515 (agent communication)
- Allow internal LAN-to-LAN traffic (so containers can communicate)
- Rate limit: max 25 SYN packets/second, 30 HTTP requests/second, 100 concurrent connections per IP
- Log everything that gets dropped (for Wazuh to analyze)

### Active Response Pipeline

When Wazuh detects a severe threat (level 15), it automatically:
1. Runs the `block-ip-firewall.sh` script
2. The script tells the firewall container to block the attacker's IP
3. The firewall adds an iptables DROP rule for that IP
4. After a timeout (1-24 hours depending on the attack type), the block expires

This is configured in `configs/wazuh/ossec-manager.conf` under the `<active-response>` sections.

---

## Project File Map

```
coffeeshop-security-lab/
│
├── docker-compose.yml              # Main orchestration file (defines all 6 containers)
├── .env                            # Environment variables (IPs, passwords, ports)
├── README.md                       # This file
│
├── docker/                         # Dockerfiles and container-specific configs
│   ├── jokopi/                     # Coffee shop application
│   │   ├── Dockerfile              # Multi-stage: build React → serve with Nginx
│   │   ├── nginx.conf              # Web server config (intentionally vulnerable)
│   │   ├── supervisord.conf        # Process manager (runs Nginx + PHP + Wazuh agent)
│   │   ├── wazuh-agent.conf        # Wazuh agent config (FIM, log monitoring)
│   │   └── vulnerable-api/         # PHP endpoints with intentional vulnerabilities
│   │       ├── login.php           # SQL injection + brute-force target
│   │       ├── search.php          # SQL injection + reflected XSS target
│   │       ├── orders.php          # IDOR + data exposure target
│   │       ├── comment.php         # Stored XSS target
│   │       └── info.php            # phpinfo() disclosure
│   │
│   ├── firewall/                   # pfSense-style firewall gateway
│   │   ├── Dockerfile              # Alpine + iptables + Suricata + Web UI
│   │   ├── firewall-init.sh        # Startup script (loads rules, starts services)
│   │   ├── firewall-rules.sh       # Core iptables rules (default-deny, NAT, zones)
│   │   ├── rate-limit.sh           # Rate limiting rules (SYN/HTTP flood protection)
│   │   ├── active-response-handler.sh  # Block/unblock IP management
│   │   ├── supervisord.conf        # Process manager
│   │   ├── lighttpd.conf           # Web UI server config
│   │   ├── suricata.yaml           # IDS configuration
│   │   ├── rsyslog-firewall.conf   # Log routing for iptables
│   │   └── web-ui/
│   │       └── index.php           # Firewall dashboard (pfSense-style)
│   │
│   └── kali/                       # Attacker container
│       ├── Dockerfile              # Kali rolling + attack tools
│       └── attack-cheatsheet.md    # Quick reference for attack commands
│
├── configs/                        # Configuration files mounted into containers
│   ├── ssl/                        # SSL certificates (generated by setup script)
│   ├── wazuh/
│   │   ├── ossec-manager.conf      # Wazuh Manager configuration
│   │   ├── rules/
│   │   │   └── local_rules.xml     # 30+ custom detection rules
│   │   └── decoders/
│   │       └── local_decoder.xml   # Custom log format decoders
│   └── firewall/
│       └── default-rules.sh        # Custom firewall rules (add your own here)
│
├── scripts/
│   ├── setup/
│   │   ├── generate-certs.sh       # SSL certificate generator
│   │   └── lab-setup.sh            # One-command full setup script
│   ├── attacks/                    # Numbered attack scripts (run from Kali)
│   │   ├── 01-reconnaissance.sh    # nmap, nikto, dirb
│   │   ├── 02-web-attacks.sh       # SQLi, XSS, traversal, data exfiltration
│   │   ├── 03-brute-force.sh       # Failed logins + hydra
│   │   ├── 04-network-attacks.sh   # SYN flood, HTTP flood, enumeration
│   │   └── 05-verify-defenses.sh   # Re-test after defenses are active
│   └── active-response/
│       └── block-ip-firewall.sh    # Wazuh→Firewall integration script
│
├── docs/                           # Architecture diagrams, sprint notes
├── evidence/                       # Attack evidence (hashes and links only)
└── reports/                        # Report drafts
```

---

## Common Commands Reference

### Docker Compose Commands

```bash
# Start all containers
docker compose up -d

# Stop all containers (keeps data)
docker compose down

# Stop and remove all data (fresh start)
docker compose down -v

# Rebuild a specific container after changes
docker compose build jokopi-app
docker compose up -d jokopi-app

# View running containers
docker compose ps

# View logs for a specific container
docker compose logs -f wazuh-manager
docker compose logs -f jokopi-app

# Restart a single container
docker compose restart firewall
```

### Accessing Container Shells

```bash
# Kali attacker
docker exec -it kali-attacker bash

# Jokopi coffee shop
docker exec -it jokopi-coffeeshop bash

# Firewall
docker exec -it pfsense-firewall sh

# Wazuh Manager
docker exec -it wazuh-manager bash
```

### Firewall Management (from host)

```bash
# View current firewall rules
docker exec pfsense-firewall iptables -L -v -n --line-numbers

# Manually block an IP
docker exec pfsense-firewall /opt/active-response/handler.sh block 10.10.0.100 3600

# Unblock an IP
docker exec pfsense-firewall /opt/active-response/handler.sh unblock 10.10.0.100

# List all blocked IPs
docker exec pfsense-firewall /opt/active-response/handler.sh list

# Remove all blocks
docker exec pfsense-firewall /opt/active-response/handler.sh flush
```

### Wazuh Commands (from host)

```bash
# Check Wazuh Manager status
docker exec wazuh-manager /var/ossec/bin/wazuh-control status

# List connected agents
docker exec wazuh-manager /var/ossec/bin/agent_control -l

# View recent alerts
docker exec wazuh-manager tail -20 /var/ossec/logs/alerts/alerts.json | jq .

# Test a custom rule
docker exec wazuh-manager /var/ossec/bin/wazuh-logtest
```

---

## Troubleshooting

### "Wazuh Dashboard shows 'Wazuh is not ready yet'"
This is normal during startup. Wazuh takes 2-3 minutes to initialize. Wait and refresh the page. If it persists after 5 minutes, check:
```bash
docker compose logs wazuh-manager | tail -30
docker compose logs wazuh-indexer | tail -30
```

### "Container keeps restarting"
Check the container logs:
```bash
docker compose logs <container-name> | tail -50
```
Common cause: certificate files are missing. Make sure you ran `generate-certs.sh` first.

### "Wazuh Indexer crashes with 'max virtual memory areas' error"
On Linux, you may need to increase the virtual memory limit:
```bash
sudo sysctl -w vm.max_map_count=262144
```
To make it permanent, add `vm.max_map_count=262144` to `/etc/sysctl.conf`.

### "Kali container exits immediately"
The Kali container needs `stdin_open: true` and `tty: true` in docker-compose.yml (already configured). Access it with:
```bash
docker exec -it kali-attacker bash
```
Do NOT use `docker compose run` — use `docker exec` to attach to the already-running container.

### "Cannot connect to localhost:8080"
Check that the firewall container is running and healthy:
```bash
docker compose ps firewall
docker exec pfsense-firewall iptables -L -n | head -20
```

### "Port already in use"
Another application is using port 8080, 5601, or 8443. Either stop that application or change the ports in `.env` and `docker-compose.yml`.

### "Build fails for Jokopi Dockerfile"
The Jokopi build clones a GitHub repository. If you are behind a proxy or have no internet access, the `git clone` step will fail. You can manually download the repository and place it in `docker/jokopi/app/` then modify the Dockerfile to use `COPY` instead of `git clone`.

### "Active response is not blocking IPs"
Check the active response log:
```bash
docker exec wazuh-manager cat /var/ossec/logs/active-responses.log
```
Common causes: the firewall container name does not match, or Docker socket is not accessible from the Wazuh Manager container. Test manually:
```bash
docker exec pfsense-firewall /opt/active-response/handler.sh block 10.10.0.100 300
```

### Starting Fresh
If something is badly broken, remove everything and start over:
```bash
docker compose down -v
docker compose build --no-cache
docker compose up -d
```

---

## Course Module Mapping

| Module | Title | SY0-701 Domain | How This Project Covers It |
|---|---|---|---|
| Mod 2 | Pervasive Attack Surfaces and Controls | Threats, Vulns & Mitigations (2.0) | The Jokopi app exposes attack surfaces: open ports, web forms without validation, exposed database files, server version leaks. We document these before and after hardening. |
| Mod 5 | Endpoint Vulnerabilities, Attacks, and Defenses | Threats, Vulns & Mitigations (2.0) | We demonstrate SQL injection, XSS, brute-force, and directory traversal against the app. Wazuh agent provides endpoint-level detection. |
| Mod 8 | Infrastructure Threats and Security Monitoring | Security Operations (4.0) | Wazuh SIEM monitors all containers with custom rules, file integrity monitoring, log correlation, and dashboards. 30+ custom detection rules cover web and network attacks. |
| Mod 9 | Infrastructure Security | Security Architecture (3.0) | pfSense-style firewall with default-deny policy, NAT, rate limiting, Suricata IDS, and automated Wazuh-triggered blocking. |

---

## Team Members

- [Member 1 Name] - [Role: Project Lead / System Architect / Security Analyst]
- [Member 2 Name] - [Role]
- [Member 3 Name] - [Role]
