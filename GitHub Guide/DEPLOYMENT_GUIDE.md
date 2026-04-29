# CIS 3353 Coffee Shop Security Lab — Deployment Guide

**Target host:** Windows 11 (Home or Pro/Education)
**Stack:** Docker Desktop + WSL2, 5 containers on a custom bridge network (`coffeeshop-net`, 10.10.0.0/24)
**Audience:** Team members standing up the lab for the first time, or rebuilding after a clean wipe.

This document assumes you are inside the project root (the folder that contains `docker-compose.yml` and `.env`). All relative paths are given from that root.

---

## 1. Host Prerequisites (Windows 11)

The Wazuh Indexer (OpenSearch) is the resource floor for this lab. Under-allocating memory is the single most common reason the stack fails to come up, so treat the numbers below as hard minimums, not targets.

### 1.1 Hardware floor

| Resource        | Minimum                       | Recommended                  |
|-----------------|-------------------------------|------------------------------|
| CPU             | 4 logical cores               | 6–8 logical cores            |
| RAM             | 12 GB physical (8 GB to Docker) | 16 GB physical (10 GB to Docker) |
| Free disk       | 40 GB                         | 60 GB (SSD)                  |
| Virtualization  | VT-x or AMD-V enabled in UEFI | Same                         |

If your machine has only 8 GB of physical RAM, expect the Indexer to OOM-kill itself the first time it does a heavy ingest. Close Chrome/Slack/Teams before `docker compose up` and you may squeak by, but plan on 16 GB if you can.

### 1.2 Windows features

Open an **Administrator PowerShell** and run:

```powershell
# Enable Windows subsystem for Linux + VM platform (both are required by WSL2)
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

# Reboot once, then:
wsl --update
wsl --set-default-version 2
wsl --install -d Ubuntu-22.04      # optional, but useful for editing from a Linux shell
```

Confirm:

```powershell
wsl --status        # Default Version should be 2
systeminfo | Select-String "Hyper-V"   # Should list VM Monitor Mode Extensions: Yes
```

If `Hyper-V Requirements` reports `A hypervisor has been detected`, that's fine — it means WSL2 is already running on the hypervisor platform.

### 1.3 Docker Desktop configuration

Install Docker Desktop 4.30+ from docker.com. After install, open **Settings** and apply the following:

**Settings → General**
- [x] Use the WSL 2 based engine
- [x] Start Docker Desktop when you sign in
- [ ] Send usage statistics (optional)

**Settings → Resources → WSL Integration**
- [x] Enable integration with my default WSL distro
- [x] Enable integration for Ubuntu-22.04 (if you installed it)

**Settings → Resources → Advanced** *(only appears if you are NOT using the WSL backend; with WSL the backend is sized via `.wslconfig`, see next section)*
- CPUs: 6
- Memory: 10 GB
- Swap: 2 GB
- Disk image size: 60 GB

### 1.4 `.wslconfig` — the part most guides skip

Because you're using the WSL2 backend, Docker's memory slider is replaced by a global WSL setting. Create (or edit) `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
memory=10GB
processors=6
swap=4GB
localhostForwarding=true
# Required for the Wazuh Indexer (OpenSearch) — mmap-based index storage
kernelCommandLine=sysctl.vm.max_map_count=262144
```

Then from an Administrator PowerShell:

```powershell
wsl --shutdown
# Start Docker Desktop again from the system tray
```

Verify inside any WSL shell (or `docker run --rm alpine sysctl vm.max_map_count`) that the value is at least `262144`. If it's still `65530`, the setting didn't take — re-check the file path and line format.

### 1.5 One last sanity check

```powershell
docker version
docker compose version
docker run --rm hello-world
docker run --rm alpine nslookup google.com
```

All four should succeed before you touch the lab repo.

---

## 2. Project Initialization

The repo is already scaffolded at the root of this folder. You don't need to re-create the structure — you need to understand it, populate `.env` with team-appropriate secrets, and generate the Wazuh SSL material.

### 2.1 Folder layout (what exists, and why)

```
coffeeshop-security-lab/
├── docker-compose.yml            # Orchestrates all 5 services
├── .env                          # IPs, passwords, hostnames (git-ignored in real repos)
├── .dockerignore
├── configs/
│   ├── firewall/                 # iptables rule exports → mounted into firewall container
│   ├── wazuh/                    # ossec.conf, custom rules & decoders for Manager
│   └── ssl/                      # Indexer/Dashboard/Filebeat PEMs (generated, not committed)
├── docker/
│   ├── firewall/                 # Alpine + iptables + lighttpd admin UI (pfSense-equivalent)
│   ├── jokopi/                   # Multi-stage React build + Nginx + Wazuh agent + PHP vulns
│   └── kali/                     # kalilinux/kali-rolling + nmap/sqlmap/hydra/hping3/nikto
├── scripts/
│   ├── setup/                    # lab-setup.sh, generate-certs.sh
│   ├── attacks/                  # 01-reconnaissance.sh … 05-verify-defenses.sh
│   └── active-response/          # block-ip-firewall.sh (Wazuh → firewall pivot)
├── docs/
├── evidence/                     # Screenshots / PCAPs from attack runs
└── reports/
```

### 2.2 The `coffeeshop-net` network

The network is declared at the bottom of `docker-compose.yml`:

```yaml
networks:
  coffeeshop-net:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: ${NETWORK_SUBNET}    # 10.10.0.0/24
          gateway: ${NETWORK_GATEWAY}  # 10.10.0.1
    driver_opts:
      com.docker.network.bridge.name: coffeeshop-br0
```

Three things worth knowing:

1. The `bridge` driver creates a Linux bridge on the WSL2 VM named `coffeeshop-br0` (handy for `tcpdump -i coffeeshop-br0` from inside Docker Desktop's debug shell).
2. Every service declares a static IP via `networks.coffeeshop-net.ipv4_address: ${SERVICE_IP}`. That's what lets Wazuh rules reference `10.10.0.100` as "the attacker" and the firewall's active-response script target specific IPs.
3. **The gateway at 10.10.0.1 is a legitimate IP, not a ghost.** Docker normally reserves `.1` for itself; here we've explicitly pinned the firewall container to `.1` so it *is* the gateway. Other containers' default routes still point at Docker's bridge, so traffic to the internet doesn't literally traverse the firewall container — but all container-to-container traffic on the LAN does, and that's what Wazuh's active response manipulates via `iptables` on the firewall.

### 2.3 Populate `.env`

The file already exists with sane defaults. Review it once and change any password that will end up in screenshots for your final report:

```bash
# .env
NETWORK_SUBNET=10.10.0.0/24
NETWORK_GATEWAY=10.10.0.1

FIREWALL_IP=10.10.0.1
WAZUH_MANAGER_IP=10.10.0.10
WAZUH_DASHBOARD_IP=10.10.0.11
WAZUH_INDEXER_IP=10.10.0.12
JOKOPI_APP_IP=10.10.0.20
KALI_IP=10.10.0.100

WAZUH_API_USER=wazuh-wui
WAZUH_API_PASSWORD=MyS3cr3tP4ssw0rd!
INDEXER_USERNAME=admin
INDEXER_PASSWORD=SecretPassword!123

JOKOPI_ADMIN_USER=admin
JOKOPI_ADMIN_PASS=coffee123         # Intentionally weak for the brute-force demo

FIREWALL_ADMIN_USER=admin
FIREWALL_ADMIN_PASS=pfsense!2026

WAZUH_REGISTRATION_PASSWORD=AgentRegistration!2026
```

> **Tip for the final report**: keep one copy of `.env` with demo-friendly passwords (these) and a second `.env.production-example` with strong passwords, to show the grader that you understand the difference.

### 2.4 Generate the Wazuh SSL material

The Indexer will not start without its certs. The generator script wraps Wazuh's official `certs.yml` approach:

```bash
# From WSL or Git Bash, inside the project root:
bash scripts/setup/generate-certs.sh
ls configs/ssl/
#   root-ca.pem  root-ca-key.pem  indexer.pem  indexer-key.pem
#   dashboard.pem  dashboard-key.pem  filebeat.pem  filebeat-key.pem
```

Run this **once per clone**. The files are not committed to git. If you wipe volumes (`docker compose down -v`), you do not need to regenerate the certs — they live on the host, not in the volumes.

---

## 3. Step-by-Step Deployment

The compose file already encodes the dependency graph with `depends_on` + healthchecks, so `docker compose up -d` is *technically* enough. In practice you want to stage the bring-up because (a) the Indexer is slow, and (b) if the firewall comes up broken, no traffic flows and every other healthcheck fails for the wrong reason.

### 3.1 The dependency graph

```
                ┌─────────────────┐
                │ wazuh-indexer   │  (must be healthy before anything else starts)
                │ 10.10.0.12      │
                └────────┬────────┘
                         │
                 ┌───────┴────────┐
                 ▼                ▼
       ┌─────────────────┐  ┌─────────────────┐
       │ wazuh-manager   │  │ wazuh-dashboard │
       │ 10.10.0.10      │  │ 10.10.0.11      │
       └────────┬────────┘  └─────────────────┘
                │
        ┌───────┴────────┐
        ▼                ▼
 ┌─────────────────┐  ┌─────────────────┐
 │ jokopi-app      │  │ firewall        │   (firewall has no Wazuh dependency;
 │ + Wazuh agent   │  │ 10.10.0.1       │    it can start in parallel with the
 │ 10.10.0.20      │  └─────────────────┘    Indexer)
 └─────────────────┘
                                            ┌─────────────────┐
                                            │ kali-attacker   │   (last — we don't
                                            │ 10.10.0.100     │    want it firing
                                            └─────────────────┘    before alerts
                                                                   are wired up)
```

### 3.2 First-time bring-up (staged)

Run each block, wait for it to finish, then move on. The whole sequence takes **10–20 minutes on first build** (image pulls + React build + Wazuh agent install) and **~90 seconds on subsequent runs**.

```bash
# [A] Build all custom images (firewall, jokopi, kali)
docker compose build

# [B] Start the firewall + the Indexer
docker compose up -d firewall wazuh-indexer

# [C] Wait until the Indexer is healthy (usually 45–90s)
docker compose ps wazuh-indexer
# Repeat until STATUS shows (healthy)

# [D] Start the Manager
docker compose up -d wazuh-manager
docker compose logs -f wazuh-manager   # Ctrl-C when you see "Started ossec-remoted"

# [E] Start the Dashboard
docker compose up -d wazuh-dashboard
# Browse to https://localhost:5601 — should show the Wazuh login after ~60s
#   user: admin  /  pass: SecretPassword!123

# [F] Start the app (agent auto-registers with the Manager on first boot)
docker compose up -d jokopi-app

# [G] Start the attacker last
docker compose up -d kali-attacker

# [H] Final status
docker compose ps
```

### 3.3 Alternative: one-shot bring-up

Once you trust the stack on your machine, `scripts/setup/lab-setup.sh` does A–H in a single invocation and polls healthchecks for you:

```bash
bash scripts/setup/lab-setup.sh
```

The script prints the dashboard URLs and the Kali attach command at the end.

### 3.4 Verifying the deployment

Four checks, in order. If any fails, stop and fix before moving on.

```bash
# 1. All six containers are "Up" and three have "(healthy)"
docker compose ps

# 2. The agent on Jokopi registered with the Manager
docker exec wazuh-manager /var/ossec/bin/agent_control -l
#   Should list "jokopi" with status "Active"

# 3. The firewall is actually forwarding packets
docker exec pfsense-firewall iptables -L FORWARD -n -v | head

# 4. Kali can reach the target
docker exec kali-attacker curl -s -o /dev/null -w "%{http_code}\n" http://10.10.0.20
#   Expect: 200
```

### 3.5 Tear-down / reset

```bash
# Stop but keep volumes (fast restart, logs preserved)
docker compose stop

# Full teardown + fresh volumes (use between demos to reset Wazuh alert history)
docker compose down -v

# Nuclear option (also removes built images — you'll pay the 10-min build again)
docker compose down -v --rmi local
```

---

## 4. Interactive Access

This is the "how do I actually get in and drive" section. Each container has its own expected workflow.

### 4.1 Kali — the attacker shell

This is the one you'll use most. The container is started with `stdin_open: true` and `tty: true`, so it's already waiting for you.

```bash
# Primary: attach with an interactive bash shell
docker exec -it kali-attacker /bin/bash

# Inside Kali, attack scripts are bind-mounted at /opt/attacks
ls /opt/attacks/
#   01-reconnaissance.sh  02-web-attacks.sh  03-brute-force.sh
#   04-network-attacks.sh  05-verify-defenses.sh

# Quick smoke test
nmap -sV 10.10.0.20
sqlmap -u "http://10.10.0.20/api/search.php?q=coffee" --batch --dbs
```

Useful variants:

```bash
# Open a second shell without disturbing the first (good for a tmux-free split)
docker exec -it kali-attacker /bin/bash

# Run a one-shot command without attaching
docker exec kali-attacker nmap -sS -T4 10.10.0.0/24

# Copy results out of Kali to your host (PowerShell):
docker cp kali-attacker:/root/results ./evidence/run-$(Get-Date -Format yyyyMMdd-HHmm)
```

### 4.2 Jokopi — the target app

Jokopi is `ubuntu:22.04`-based (Stage 2 of its Dockerfile), so `bash` is available.

```bash
# Main shell
docker exec -it jokopi-coffeeshop /bin/bash

# Where things live inside the container
#   /var/www/html              React build artifacts (Nginx docroot)
#   /var/www/html/api          PHP vulnerable endpoints (login, search, comment, orders, info)
#   /etc/nginx/nginx.conf      Nginx config
#   /var/log/nginx/            Access + error logs (Wazuh reads these)
#   /var/ossec/                Wazuh agent — do NOT touch in demo mode

# Useful one-liners from the host (no need to attach)
docker exec jokopi-coffeeshop tail -f /var/log/nginx/access.log
docker exec jokopi-coffeeshop /var/ossec/bin/wazuh-control status
```

**Web access from your host browser:**

| Service            | URL                          | Credentials                        |
|--------------------|------------------------------|------------------------------------|
| Jokopi app         | http://localhost:8080        | admin / coffee123 (intentionally weak) |
| Wazuh Dashboard    | https://localhost:5601       | admin / SecretPassword!123         |
| Firewall admin UI  | http://localhost:8443        | admin / pfsense!2026               |

These ports are published by the **firewall** container (see `firewall.ports` in compose) — traffic reaches the app *through* the firewall, which is how you demonstrate zone policy and pfSense-style port forwarding later.

### 4.3 The Wazuh stack — read-only for most work

Most of your interaction is through the Dashboard. When you do need a shell:

```bash
# Manager (for adding rules on the fly or tailing the archive)
docker exec -it wazuh-manager /bin/bash
tail -f /var/ossec/logs/alerts/alerts.json
/var/ossec/bin/wazuh-control status

# Indexer (almost never — use the Dev Tools pane in the Dashboard instead)
docker exec -it wazuh-indexer /bin/bash

# Dashboard (essentially never — the UI is the point)
docker exec -it wazuh-dashboard /bin/bash
```

If you edit `configs/wazuh/rules/local_rules.xml` or `ossec-manager.conf` from the host, apply it with:

```bash
docker exec wazuh-manager /var/ossec/bin/wazuh-control restart
```

### 4.4 Firewall — Alpine + iptables

The "pfSense" container is an Alpine image running iptables + lighttpd for the web UI. It is not literally pfSense (no public Netgate Docker image exists; see §4.3 of the project plan for the rationale), but it replicates the behaviors you need to demonstrate: stateful filtering, rate limiting, logging to rsyslog, and a management UI.

```bash
docker exec -it pfsense-firewall /bin/sh

# Inspect the live rule set
iptables -L -n -v --line-numbers
iptables -t nat -L -n -v

# Tail the firewall log (also mounted at host ./firewall-logs via the named volume)
tail -f /var/log/firewall/iptables.log

# Apply a manual rule (simulates what Wazuh's active response does)
iptables -I FORWARD -s 10.10.0.100 -j DROP   # block Kali
iptables -D FORWARD -s 10.10.0.100 -j DROP   # unblock Kali
```

To edit the persistent ruleset (not an ad-hoc test), modify `configs/firewall/default-rules.sh` on the host and restart the container — the file is bind-mounted into `/etc/firewall/rules.d/`.

### 4.5 Cheat sheet — everything you'll type

Pin this somewhere in your terminal:

```bash
# Attach shells
docker exec -it kali-attacker bash
docker exec -it jokopi-coffeeshop bash
docker exec -it pfsense-firewall sh
docker exec -it wazuh-manager bash

# Tail alerts
docker exec wazuh-manager tail -f /var/ossec/logs/alerts/alerts.json

# Container IPs (as Docker sees them)
docker inspect -f '{{.Name}} → {{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' \
  pfsense-firewall wazuh-manager wazuh-indexer wazuh-dashboard jokopi-coffeeshop kali-attacker

# Full restart of one service
docker compose restart jokopi-app

# Clean slate (Wazuh alert history + app data gone)
docker compose down -v && bash scripts/setup/lab-setup.sh
```

---

## 5. Common failure modes (read before you file a bug)

| Symptom                                         | Root cause                                     | Fix                                                                 |
|-------------------------------------------------|------------------------------------------------|---------------------------------------------------------------------|
| `wazuh-indexer` exits with `max virtual memory areas too low` | `vm.max_map_count` not set in WSL2             | Fix `.wslconfig` (§1.4), then `wsl --shutdown`                      |
| `wazuh-indexer` OOMKilled                       | Docker RAM < 8 GB                              | Raise memory in `.wslconfig`; close Chrome/Teams                    |
| Dashboard hangs on "Waiting for Wazuh API"      | Manager not healthy yet                        | Wait 2–3 min on first boot; check `docker compose logs wazuh-manager` |
| Agent on Jokopi shows "Never connected"         | Registration password mismatch                 | `.env:WAZUH_REGISTRATION_PASSWORD` must match Manager's `authd.pass` |
| `docker compose up` fails with `address already in use` | Something on the host owns 5601/8080/8443       | `netstat -ano | findstr :5601` then stop that process, or change host ports in compose |
| Kali can't resolve `jokopi` by name             | DNS not yet propagated on compose restart      | Wait 30s, or use `10.10.0.20` directly                              |
| Firewall rules revert after a restart          | Changes made live via `iptables` aren't persisted | Edit `configs/firewall/default-rules.sh` on the host instead        |
| `docker compose build` errors with `error getting credentials ... docker-credential-desktop.exe: exec format error` | Running `docker` from `/mnt/c/...` so WSL picks up Docker Desktop's Windows credential helper | In WSL: `sed -i 's/"credsStore": *"[^"]*"/"credsStore": ""/' ~/.docker/config.json`. Ideally also move the repo out of `/mnt/c/` into `~/` for speed. |
| `up` fails with `failed to set up container networking: Address already in use` on the firewall | Docker's bridge already owns `10.10.0.1` as the network's gateway IP, so the firewall container can't claim it | In `.env`, set `NETWORK_GATEWAY=10.10.0.254` (or any unused `.254`-style address), leave `FIREWALL_IP=10.10.0.1`. Then `docker compose down && docker compose up -d`. |
| `curl: (77) error setting certificate file` inside the Jokopi build | `ca-certificates` not pulled in because `--no-install-recommends` skips it for `curl` | Already fixed: `ca-certificates` added to the first apt-get block + `update-ca-certificates` after install |
| Jokopi build fails with `Directory nonexistent` on `/etc/php/*/fpm/php.ini` | `/bin/sh` passes unmatched globs through literally | Already fixed: `find` is used to locate the ini, with diagnostics + a fallback install if missing |
| `wazuh-indexer` restart-loops with `java.security.AccessControlException` / `java.io.FilePermission ... /etc/wazuh-indexer/certs/indexer.pem read` | The image's baked-in `opensearch.yml` points at absolute paths (`/etc/wazuh-indexer/certs/*.pem`), but the JVM actually runs with `-Dopensearch.path.conf=/usr/share/wazuh-indexer`. SecurityManager only permits reads under `path.conf`, so the certs can't be loaded no matter where they're mounted. | Lab workaround (already applied): mount `configs/wazuh/opensearch-indexer.yml` over `/usr/share/wazuh-indexer/opensearch.yml` with `plugins.security.disabled: true`, and set the manager/dashboard to reach the indexer over plain `http://` with auth off. This is **lab-only** — call it out in the final report; production would keep the security plugin on and use relative cert paths that resolve under `path.conf`. |
| Any port `0.0.0.0:XXXX already allocated`                | Leftover container from another project (common: `docker-elk-kibana-1` holds 5601) | `docker ps -a | grep <port>`, then `docker stop <name>` or `docker rm -f <name>` |

---

## 6. What to show the grader

A demo run that hits every verification-matrix row (plan §7.3) is roughly:

1. Fresh bring-up: `docker compose down -v && bash scripts/setup/lab-setup.sh`.
2. Open the Wazuh Dashboard, show the Jokopi agent as "Active".
3. `docker exec -it kali-attacker bash` → `bash /opt/attacks/01-reconnaissance.sh`.
4. Flip to the Dashboard, filter on `data.srcip: 10.10.0.100`, show the nmap signature alert within 60 s.
5. Run `02-web-attacks.sh` and `03-brute-force.sh`, point at the corresponding alerts.
6. Enable active response, re-run `03-brute-force.sh`, show the `iptables` rule appearing on the firewall via `docker exec pfsense-firewall iptables -L FORWARD -n`.
7. Re-run `05-verify-defenses.sh` to prove the attacker is now blocked.

If your demo machine can't carry the full stack, pre-record each attack → alert pair to video and narrate over it. Do not fake screenshots — the grader will ask you to rerun on the fly.
