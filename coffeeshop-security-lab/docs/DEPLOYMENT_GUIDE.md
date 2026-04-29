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
│   ├── kali/                     # kalilinux/kali-rolling + nmap/sqlmap/hydra/hping3/nikto
│   ├── wazuh-manager/            # Custom build that pre-seeds VOLUME dirs (see §5.2)
│   └── wazuh-dashboard/          # Custom build that removes securityDashboards plugin (see §5.3)
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

Run each block, wait for it to finish, then move on. The whole sequence takes **10–20 minutes on first build** (image pulls + React build + Wazuh agent install + the two custom Wazuh images) and **~90 seconds on subsequent runs**.

> **Custom Wazuh images.** Both `wazuh-manager` and `wazuh-dashboard` are now built from local Dockerfiles under `docker/wazuh-manager/` and `docker/wazuh-dashboard/` respectively. The manager image pre-seeds the VOLUME-declared data dirs (§5.2) and the dashboard image removes the broken `securityDashboards` plugin (§5.3). `docker compose build` picks both up automatically.

```bash
# [A] Build all custom images (firewall, jokopi, kali, wazuh-manager, wazuh-dashboard)
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
# Browse to https://localhost:5601 — should land DIRECTLY on /app/wz-home with
# no login screen (the security plugin is removed; see §5.3). On first boot
# allow ~60 s for the dashboard to register all 47 plugins.

# [F] Start the app (agent auto-registers with the Manager on first boot)
docker compose up -d jokopi-app

# [G] Start the attacker last
docker compose up -d kali-attacker

# [H] Final status
docker compose ps
```

> **If you change a Dockerfile, force a rebuild.** Docker Compose's build cache will happily reuse a stale layer (or even a stale image from a *failed* prior build) without telling you. After editing anything under `docker/wazuh-*/`, run `docker compose build --no-cache wazuh-manager wazuh-dashboard` and, if you suspect a poisoned image, `docker image rm coffeeshop-lab/wazuh-manager:4.9.2 coffeeshop-lab/wazuh-dashboard:4.9.2` before rebuilding. See §5.7.

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

The quick-reference table is in §5.0. Anything that needed more than one row to explain — the four big ones we hit putting this stack together — gets a dedicated subsection (§§5.1–5.6).

### 5.0 Quick-reference table

| Symptom                                         | Root cause                                     | Fix                                                                 |
|-------------------------------------------------|------------------------------------------------|---------------------------------------------------------------------|
| `wazuh-indexer` exits with `max virtual memory areas too low` | `vm.max_map_count` not set in WSL2             | Fix `.wslconfig` (§1.4), then `wsl --shutdown`                      |
| `wazuh-indexer` OOMKilled                       | Docker RAM < 8 GB                              | Raise memory in `.wslconfig`; close Chrome/Teams                    |
| Dashboard hangs on "Waiting for Wazuh API"      | Manager not healthy yet                        | Wait 2–3 min on first boot; check `docker compose logs wazuh-manager` |
| Agent on Jokopi shows "Never connected"         | Registration password mismatch                 | `.env:WAZUH_REGISTRATION_PASSWORD` must match Manager's `authd.pass` |
| `docker compose up` fails with `address already in use` | Something on the host owns 5601/8080/8443       | `netstat -ano | findstr :5601` then stop that process, or change host ports in compose |
| Kali can't resolve `jokopi` by name             | DNS not yet propagated on compose restart      | Wait 30s, or use `10.10.0.20` directly                              |
| Firewall rules revert after a restart          | Changes made live via `iptables` aren't persisted | Edit `configs/firewall/default-rules.sh` on the host instead        |
| `docker compose build` errors with `error getting credentials ... docker-credential-desktop.exe: exec format error`, OR `error getting credentials - err: exit status 1, out: \`\`` while pulling `node:18-alpine` / `ubuntu:22.04` / etc. | Running `docker` from `/mnt/c/...` so WSL picks up Docker Desktop's Windows credential helper. The `.exe: exec format error` variant is the helper itself failing to launch; the "exit status 1, out: `` " variant is the helper launching fine but failing to fetch a (re-)auth token after Docker Desktop restarted — both leave Docker unable to even do an anonymous public pull. | In WSL: `sed -i 's/"credsStore": *"[^"]*"/"credsStore": ""/' ~/.docker/config.json` then retry. If `credsStore` was already empty, clear the stale tokens too: `docker logout && rm -f ~/.docker/config.json`. Public Docker Hub images all pull anonymously — no re-login needed. Ideally also move the repo out of `/mnt/c/` into `~/` for speed. |
| `up` fails with `failed to set up container networking: Address already in use` on the firewall | Docker's bridge already owns `10.10.0.1` as the network's gateway IP, so the firewall container can't claim it | In `.env`, set `NETWORK_GATEWAY=10.10.0.254` (or any unused `.254`-style address), leave `FIREWALL_IP=10.10.0.1`. Then `docker compose down && docker compose up -d`. |
| `curl: (77) error setting certificate file` inside the Jokopi build | `ca-certificates` not pulled in because `--no-install-recommends` skips it for `curl` | Already fixed: `ca-certificates` added to the first apt-get block + `update-ca-certificates` after install |
| Jokopi build fails with `Directory nonexistent` on `/etc/php/*/fpm/php.ini` | `/bin/sh` passes unmatched globs through literally | Already fixed: `find` is used to locate the ini, with diagnostics + a fallback install if missing |
| `wazuh-indexer` restart-loops with `java.security.AccessControlException` / `java.io.FilePermission ... /etc/wazuh-indexer/certs/indexer.pem read` | The image's baked-in `opensearch.yml` points at absolute paths (`/etc/wazuh-indexer/certs/*.pem`), but the JVM actually runs with `-Dopensearch.path.conf=/usr/share/wazuh-indexer`. SecurityManager only permits reads under `path.conf`, so the certs can't be loaded no matter where they're mounted. | Lab workaround (already applied): mount `configs/wazuh/opensearch-indexer.yml` over `/usr/share/wazuh-indexer/opensearch.yml` with `plugins.security.disabled: true`, and set the manager/dashboard to reach the indexer over plain `http://` with auth off. This is **lab-only** — call it out in the final report; production would keep the security plugin on and use relative cert paths that resolve under `path.conf`. |
| Any port `0.0.0.0:XXXX already allocated`                | Leftover container from another project (common: `docker-elk-kibana-1` holds 5601) | `docker ps -a | grep <port>`, then `docker stop <name>` or `docker rm -f <name>` |
| Wazuh Manager fatals with `INVALID_ELEMENT` / refuses to load `local_rules.xml` or `local_decoder.xml` | Custom rule/decoder uses PCRE-style escapes (`\[`, `\]`, `\x`, `\/`) that Wazuh's OS_Regex engine rejects | See §5.1 — write OS_Regex literally, no backslash escapes |
| Manager health flaps after `down -v`; `/var/ossec/etc/`, `/queue/`, etc. show up empty | Wazuh's s6 init's `mount_permanent_data()` short-circuits on a non-empty directory, and our bind mounts make it look non-empty before it's been seeded | See §5.2 — the custom `docker/wazuh-manager/Dockerfile` pre-seeds the VOLUME contents at build time |
| Dashboard 401 on every login; logs show `no handler found for uri [/_plugins/_security/authinfo]` | The bundled `securityDashboards` plugin calls a `/_plugins/_security/*` endpoint that doesn't exist on an indexer with `plugins.security.disabled: true` | See §5.3 — the `securityDashboards` plugin is now physically removed from the dashboard image |
| Dashboard crashloops with `ValidationError: [config validation of [opensearch_security].disabled]: definition for this key is missing` | Wazuh's fork of `securityDashboards` has a strict config schema and rejects unknown keys, so the obvious "just disable it in YAML" fix doesn't work | See §5.3 — same fix; the plugin is removed, not configured around |
| Dashboard exits immediately after a Dockerfile change with `OpenSearch Dashboards should not be run as root. Use --allow-root to continue.` | A `USER root` directive in the custom Dockerfile leaked into runtime | See §5.3 — the Dockerfile now ends with `USER wazuh-dashboard` |
| Dashboard logs `EACCES: permission denied, open '/etc/wazuh-dashboard/opensearch_dashboards.keystore'` once at startup | Cosmetic — entrypoint tries to regenerate a root-owned keystore that already exists; the server starts anyway | Ignore. See §5.5 |
| Browser shows `ERR_SSL_SSLV3_ALERT_CERTIFICATE_UNKNOWN` on first hit to `https://localhost:5601` | Self-signed dashboard cert; Chrome rejects on the first probe before you click *Proceed* | Click through "Advanced → Proceed" once. See §5.5 |
| Dashboard logs `no handler found for uri [/_plugins/_security/api/account]` after login | This one's from `indexManagementDashboards` (a different plugin), feature-detect probe — not the same as the `authinfo` 401 | Ignore. See §5.5 |
| Just rebuilt the dashboard/manager image, container behaves identically to before — fix not visible | `docker compose build` reused a cached layer, or `docker run` reused a stale tagged image from a failed earlier build | See §5.7 — `docker image rm` then `--no-cache` rebuild |
| `jokopi-coffeeshop` restart-loops with exit code 2; logs say `Format string '/usr/sbin/php-fpm%(ENV_PHP_VERSION)s -F' ... contains names ('ENV_PHP_VERSION') which cannot be expanded` | The shipped `supervisord.conf` tried to interpolate the PHP version at runtime via `%(ENV_PHP_VERSION)s`, but nothing in the image or compose ever defined `PHP_VERSION` — so supervisord failed to parse its config and bailed before launching anything | Already fixed: the Dockerfile now creates a stable `/usr/sbin/php-fpm` symlink pointing at whichever versioned binary apt installed, and `supervisord.conf` just calls `/usr/sbin/php-fpm -F`. Rebuild jokopi-app: `docker compose build jokopi-app && docker compose up -d jokopi-app` |
| `jokopi-coffeeshop` is `(healthy)` but supervisord logs flap `spawned: 'wazuh-agent' with pid X` / `exited: wazuh-agent (exit status 0; not expected)` every few seconds | `wazuh-control start` spawns the agent's daemons as detached processes and then exits with code 0. With `autorestart=true` + `startsecs=10` supervisord treated each <10s clean exit as an unexpected termination and relaunched, which re-ran `wazuh-control start` against already-running daemons. The agent itself is fine; the noise is the wrapper. | Already fixed: `supervisord.conf` now wraps the start as `sh -c "wazuh-control start && exec tail -F /var/ossec/logs/ossec.log"` so the supervised PID is a long-lived tail of the agent log, and `startsecs=0` reflects that the start command's own runtime is what's being measured. Rebuild + restart jokopi-app to pick up the new config. |
| `agent_control -l` on the manager only shows ID 000 (manager itself); jokopi's `ossec.log` repeats `wazuh-agentd: ERROR: Invalid password (from manager)` every ~60 s | Two preconditions collide: (a) the agent has a fixed `authd.pass` baked in at build time from `WAZUH_REGISTRATION_PASSWORD` in `.env`; (b) the manager's `ossec.conf` had `<use_password>yes</use_password>`, but no `/var/ossec/etc/authd.pass` existed on the manager — so `wazuh-authd` auto-generated a *random* password on first start, which the agent has never seen. | Already fixed in `configs/wazuh/ossec-manager.conf`: `<use_password>no</use_password>`, matching the rest of the lab's "no-auth on the wire" pattern. To apply without a full rebuild, sed-replace the live file inside the running manager and restart authd: `docker exec wazuh-manager sed -i 's\|<use_password>yes</use_password>\|<use_password>no</use_password>\|' /var/ossec/etc/ossec.conf && docker exec wazuh-manager /var/ossec/bin/wazuh-control restart`, then re-enroll the agent with `docker exec jokopi-coffeeshop /var/ossec/bin/agent-auth -m 10.10.0.10` and `docker exec jokopi-coffeeshop /var/ossec/bin/wazuh-control restart`. |
| `bash: !2026: event not found` when running `agent-auth -P "AgentRegistration!2026"` | Bash history-expansion eats `!2026` inside double quotes | Use single quotes: `agent-auth -m 10.10.0.10 -P 'AgentRegistration!2026'` (or escape the `!`). Better yet, with the password fix above you don't need `-P` at all. |
| `agent-auth: ERROR: Agent version must be lower or equal to manager version (from manager)`, OR earlier-stage `Invalid request for new agent` from authd against an agent that just installed cleanly | The agent was installed from `https://packages.wazuh.com/4.x/apt/ stable main` which always serves the *latest* 4.x release (4.14.x as of writing), but the manager image is pinned to 4.9.2. Wazuh authd enforces `agent_version <= manager_version` and rejects newer agents — sometimes with the misleading `Invalid request for new agent` framing before the version-specific error surfaces. | Already fixed: the jokopi Dockerfile pins `wazuh-agent=4.9.2-1` and `apt-mark hold`s it. Rebuild jokopi-app: `docker compose build jokopi-app && docker compose up -d jokopi-app`. The agent will auto-enroll on first boot via the .deb postinstall now that versions match and the manager has `<use_password>no</use_password>`. |
| Wazuh dashboard shows tens of thousands of `Directory traversal attempt detected against Jokopi app` (rule 100130) alerts in the first minute, all with `full_log` containing benign nginx debug-trace lines like `[debug] 23#23: *375 hc free: 0...` or `[debug] 23#23: *375 http header: "Accept: */*"` | Two compounding bugs: (a) `nginx.conf` had `error_log /var/log/nginx/error.log debug;` which made nginx emit 50+ trace lines per HTTP request, (b) rule 100130 was scoped `<if_group>web\|accesslog\|nginx</if_group>` with an OS_Regex alternation whose precedence in this build matched any line whose parent decoder fell into the `nginx` group — so every debug-trace line in error.log was getting the "directory traversal" tag. Combined effect: ~99k false positives in under 2 min, indexer disk filling, real high-severity rules (100300-series) starved of analysisd budget. | See §5.6 for the full fix. Short version: `nginx.conf` is now at `error_log ... warn;`, and rule 100130 has been rewritten to `<if_sid>31100</if_sid>` (web access-log parent only) with a `<match>` substring filter. Live-patch with `docker exec jokopi-coffeeshop sed -i ...` + `nginx -s reload`, then `docker cp configs/wazuh/rules/local_rules.xml wazuh-manager:/var/ossec/etc/rules/local_rules.xml && docker exec wazuh-manager /var/ossec/bin/wazuh-control restart`, then delete today's polluted alert index from the indexer. **Note**: don't try `<pcre2>` for this — Wazuh 4.9.2 rejects it as an unknown rule option and the manager won't start. |

---

### 5.1 Wazuh custom rules / decoders: OS_Regex, not PCRE

`configs/wazuh/rules/local_rules.xml` and `configs/wazuh/decoders/local_decoder.xml` are parsed by Wazuh's **OS_Regex** engine, not PCRE2. They have a similar surface syntax but a much smaller escape vocabulary, and OS_Regex flatly rejects unknown escapes — including some that look perfectly normal in a PCRE world. Get any of them wrong and the manager refuses to load the ruleset and exits.

What OS_Regex does **not** accept (any of these will surface as `INVALID_ELEMENT` / `regex error` and abort manager startup):

```text
\[   \]   \(   \)   \/   \x   \d   \w   \s
```

Write the characters literally instead. A few patterns that bit us during this build:

```xml
<!-- Wrong (PCRE habits): -->
<regex>(?i)\[ERROR\]\s+/admin\.php</regex>

<!-- Right (OS_Regex): write the brackets and the slash literally, -->
<!-- and use \p+ / \w+ for whitespace/word runs.                  -->
<regex>(?i)[ERROR]\p+/admin.php</regex>
```

Things OS_Regex *does* accept that you'll actually use: `\.`, `\\`, `\t`, `\n`, character classes like `[A-Za-z0-9_-]`, the OS_Regex-flavored quantifiers `\w` (any word char), `\d` (any digit), `\s` (any whitespace), `\p` (printable, very lenient), and ordinary `+ * ?`. When in doubt, prefer character classes over escape shortcuts.

If the manager won't start after you edit either file:

```bash
docker exec wazuh-manager /var/ossec/bin/wazuh-logtest -t
# walks the ruleset and prints the exact rule/decoder that fails to compile.
```

---

### 5.2 Wazuh Manager: pre-seeding the VOLUME data dirs

The stock `wazuh/wazuh-manager:4.9.2` image declares VOLUMEs over `/var/ossec/etc`, `/var/ossec/queue`, `/var/ossec/logs`, etc., and ships an s6 init script (`/etc/cont-init.d/0-wazuh-init`) that calls a `mount_permanent_data()` helper to seed those directories from a tarball baked into the image — *but only if they're empty*.

The "is it empty?" check is:

```sh
find "$dir" -mindepth 1 | read   # exits 0 if anything is found, 1 if nothing
```

That's a "directory non-empty" probe, not a real "is this a fresh volume?" probe. The first time a bind mount or named volume is attached, Docker creates the mount point with a `lost+found` (or otherwise non-empty) skeleton, the `find ... | read` returns 0, and the seeding step **silently skips**. The manager then starts against an empty `/var/ossec/etc`, can't find `ossec.conf`, and either crashloops or comes up in a half-broken state that fails its healthcheck a few minutes in.

**Fix already applied:** `docker/wazuh-manager/Dockerfile` is a custom image that runs the seeding step at *build time* — copying the contents of `/var/ossec/{etc,queue,logs,...}` into the layers that back the VOLUMEs, so the image-baked data is always present even when the runtime check short-circuits. `docker-compose.yml`'s `wazuh-manager:` service builds this Dockerfile (`coffeeshop-lab/wazuh-manager:4.9.2`) instead of pulling the upstream image directly.

If you ever need to verify the seed worked:

```bash
docker exec wazuh-manager ls /var/ossec/etc/ossec.conf
docker exec wazuh-manager ls /var/ossec/queue/
```

Both should be populated immediately after `up`, before the manager has even finished its first start.

---

### 5.3 Wazuh Dashboard: removing the `securityDashboards` plugin

This was the single biggest debugging adventure of the build, so it gets the long version.

**Symptom.** Dashboard comes up cleanly, the login page renders, but every login attempt — including with the `admin / SecretPassword!123` creds from `.env` — returns 401. Dashboard logs:

```
[error][plugins][securityDashboards] no handler found for uri [/_plugins/_security/authinfo] and method [GET]
```

**Why.** Because we run the indexer with `plugins.security.disabled: true` (§5.0 row about the certs / `path.conf` SecurityManager issue), the `/_plugins/_security/*` endpoints don't exist on the indexer at all. The dashboard's bundled `securityDashboards` plugin calls `GET /_plugins/_security/authinfo` on every login submission; when the indexer responds "no handler," the plugin treats it as an auth failure and surfaces a 401 to the browser.

**The trap that wastes an afternoon.** The natural fix is to add `opensearch_security.disabled: true` to `configs/wazuh/opensearch-dashboards.yml`. **This does not work on the Wazuh fork** — its config schema is strict and rejects unknown keys with:

```
ValidationError: [config validation of [opensearch_security].disabled]: definition for this key is missing
```

Worse, the same trap fires for *every* `opensearch_security.*` key, so you can't sneak the dashboard into a "no security plugin" mode by reconfiguring it.

**Fix already applied.** `docker/wazuh-dashboard/Dockerfile` is a custom image that physically removes the plugin at build time:

```dockerfile
FROM wazuh/wazuh-dashboard:4.9.2

USER root
RUN /usr/share/wazuh-dashboard/bin/opensearch-dashboards-plugin remove \
        securityDashboards --allow-root || true

COPY configs/wazuh/opensearch-dashboards.yml \
     /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml
RUN chown wazuh-dashboard:wazuh-dashboard \
        /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml && \
    chmod 640 \
        /usr/share/wazuh-dashboard/config/opensearch_dashboards.yml

# Sanity check — fail the build loudly if a future base-image layout
# leaves the plugin somewhere we didn't expect.
RUN test ! -d /usr/share/wazuh-dashboard/plugins/securityDashboards

# Restore the non-root runtime user. Without this line, `USER root` from
# above persists into runtime and the OSD entrypoint refuses to start with:
#   "OpenSearch Dashboards should not be run as root. Use --allow-root to
#   continue."
USER wazuh-dashboard
```

`configs/wazuh/opensearch-dashboards.yml` no longer contains *any* `opensearch_security.*` keys — they'd be rejected by the same schema check that hit us on `disabled`. With the plugin gone, the dashboard stops calling the missing endpoint, stops requiring authentication, and lands the browser straight on `/app/wz-home`. The Wazuh app itself is a separate plugin (`wazuh`) and is unaffected.

`docker-compose.yml`'s `wazuh-dashboard:` service builds this Dockerfile (`coffeeshop-lab/wazuh-dashboard:4.9.2`) instead of pulling upstream.

> **Lab-only.** This image has *no* dashboard authentication. Do not run it on any network where someone uninvited could reach port 5601. The `coffeeshop-net` bridge is the only thing it should ever be attached to.

---

### 5.4 The `5601` port conflict on the firewall service

If you used to publish the dashboard via the firewall (`firewall.ports: ["5601:5601"]`) and then later wired the dashboard to publish its own port, you'll get a `bind: address already in use` collision the next time both come up together. The dashboard now publishes 5601 directly (it's the service that actually serves it); the firewall service should publish only the app and admin-UI ports.

If your `docker-compose.yml` still has a `5601:5601` line under `firewall.ports`, delete it.

```bash
docker compose down
# remove the stale 5601 line under firewall.ports
docker compose up -d
```

---

### 5.5 Harmless log noise you can ignore

These show up in clean runs and are not bugs:

- **`EACCES: permission denied, open '/etc/wazuh-dashboard/opensearch_dashboards.keystore'`** at dashboard startup. The entrypoint tries to regenerate a keystore file that already exists root-owned in the image. The server proceeds normally, the keystore is loaded, and 5601 comes up.
- **`net::ERR_SSL_SSLV3_ALERT_CERTIFICATE_UNKNOWN`** in your browser the first time you hit `https://localhost:5601`. The dashboard cert is self-signed (generated by `scripts/setup/generate-certs.sh`); Chrome flags it once. Click *Advanced → Proceed* and the rest of the session is fine.
- **`no handler found for uri [/_plugins/_security/api/account]`** in dashboard logs *after* a successful page load. This is from `indexManagementDashboards` (different plugin from the one we removed), which probes the security API to feature-detect; it logs the miss and moves on.

If you see one of these and the corresponding container is `(healthy)` and serving traffic, leave it alone.

---

### 5.6 The "directory traversal flood" — nginx debug + over-broad rule

When the lab first comes up and you load Jokopi in a browser even once, the dashboard fills with thousands of rule-100130 alerts ("Directory traversal attempt detected against Jokopi app") whose `full_log` shows ordinary nginx internal trace output, not actual attacks. We hit `firedtimes: 99,542` in under two minutes on the first bring-up. Two bugs were colliding.

**Bug A: nginx was at `debug` log level.** `docker/jokopi/nginx.conf` had `error_log /var/log/nginx/error.log debug;`. At debug level nginx emits 50+ internal trace lines per HTTP request — every malloc/free, every timer event, every internal phase transition, plus the parsed request line and header set. The wazuh-agent's `<localfile>/var/log/nginx/error.log</localfile>` ships every one of them. A normal page load became hundreds of agent events.

**Bug B: rule 100130's match scope was too broad.** It started as:

```xml
<rule id="100130" level="10">
  <if_group>web|accesslog|nginx</if_group>
  <regex>\.\./|\.\.\\|%2e%2e|%252e%252e|/etc/passwd|/etc/shadow</regex>
  ...
</rule>
```

`<if_group>` is parent-rule scope: any base rule that decodes an `nginx`-group line (which includes the entire error.log under the stock `nginx-errorlog` decoder) makes this rule eligible. That alone is too wide — error.log contains operational data, not user-supplied input — and combined with whatever OS_Regex alternation precedence quirk this Wazuh build has, the regex was matching debug lines that contain none of the listed traversal tokens. We never fully pinned down the exact OS_Regex misparse, so the fix sidesteps the engine entirely.

**Fix in `configs/wazuh/rules/local_rules.xml`** — rule 100130 is rewritten as:

```xml
<rule id="100130" level="10">
  <if_sid>31100</if_sid>
  <match>../|%2e%2e|%252e%252e|/etc/passwd|/etc/shadow|/proc/self</match>
  <description>Directory traversal attempt detected against Jokopi app</description>
  ...
</rule>
```

Two changes: `<if_sid>31100</if_sid>` scopes the rule to the *web access log* base rule (sid 31100) only, so debug-trace lines from error.log decode under a different parent and never reach this rule; and `<match>` replaces `<regex>` so we sidestep the OS_Regex alternation parsing entirely. `<match>` uses OS_Match for fixed-content substring searches with `|` as a simple OR separator — no escape rules, no precedence ambiguity, can't misparse.

> **Don't use `<pcre2>` here.** A first attempt at this fix used `<pcre2>(?i)(\.\./|...)</pcre2>` thinking PCRE2 would resolve the alternation precedence. Wazuh 4.9.2 rejects that with `ERROR: Invalid option 'pcre2' for rule '100130'` and the manager refuses to start. `<pcre2>` is a decoder-only tag in this version; for rules, use `<regex type="pcre2">` if you need PCRE2 semantics. We didn't need them — `<match>` is sufficient and version-agnostic.

**Fix in `docker/jokopi/nginx.conf`** — `error_log` is now at `warn`. Real PHP errors and 500s still flow; per-request trace noise doesn't.

**Live-recovery procedure** (no full rebuild needed):

```bash
# 1. Quiet nginx
docker exec jokopi-coffeeshop sed -i \
    's|error_log /var/log/nginx/error.log debug;|error_log /var/log/nginx/error.log warn;|' \
    /etc/nginx/sites-available/default
docker exec jokopi-coffeeshop nginx -t && docker exec jokopi-coffeeshop nginx -s reload

# 2. Push the corrected rule to the manager
docker cp configs/wazuh/rules/local_rules.xml \
    wazuh-manager:/var/ossec/etc/rules/local_rules.xml
docker exec wazuh-manager chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec wazuh-manager /var/ossec/bin/wazuh-logtest -t 2>&1 | head -5
docker exec wazuh-manager /var/ossec/bin/wazuh-control restart

# 3. Confirm the rule no longer matches debug lines but still catches attacks
docker exec -i wazuh-manager /var/ossec/bin/wazuh-logtest <<'EOF'
2026/04/27 13:16:42 [debug] 23#23: *375 hc free: 0000000000000000
EOF
# Expect: no rule matched.

docker exec -i wazuh-manager /var/ossec/bin/wazuh-logtest <<'EOF'
10.10.0.100 - - [27/Apr/2026:13:30:00 +0000] "GET /api/../../etc/passwd HTTP/1.1" 200 1234
EOF
# Expect: rule 100130 fires.

# 4. Clear the polluted alert index so the dashboard isn't drowning
docker exec wazuh-indexer curl -sk http://localhost:9200/_cat/indices/wazuh-alerts-*
docker exec wazuh-indexer curl -sk -X DELETE \
    "http://localhost:9200/wazuh-alerts-4.x-$(date +%Y.%m.%d)"
# (Wazuh recreates the index automatically on the next alert.)
```

**General lesson, worth carrying to the other custom rules:** `<if_group>` is the most common foot-gun in Wazuh rule writing because it silently drags in *every* decoder that tags that group. Default to `<if_sid>` when you can name the specific parent rule, and reserve `<if_group>` for when you genuinely want every member of a category. When you do use `<regex>`, run `wazuh-logtest` against representative lines from *both* the file you want to match and any other log file the same decoder family touches — debug logs, error logs, slow-query logs, audit logs — to confirm scope. The other custom rules in `configs/wazuh/rules/local_rules.xml` (100100/SQLi, 100110/XSS, 100120/brute-force, 100131/scanner-fingerprint, 100200-300/active-response triggers) all use `<if_group>web|accesslog|nginx</if_group>` too — once you've validated 100130's fix, audit the rest the same way.

---

### 5.7 The Docker image cache pitfall

Compose's build cache and the local image store will quietly hand you a stale image when you don't expect it. The two cases to know about:

1. **Cached layers from a successful build that no longer reflects your Dockerfile.** Editing a `RUN` near the bottom of the file invalidates only that layer and below, but if your fix is to *change* an early `RUN`, the cached output of the old version may still get reused if the line itself didn't change textually (e.g., when the change is in a file you `COPY` afterward). Force a clean rebuild:
   ```bash
   docker compose build --no-cache wazuh-manager wazuh-dashboard
   ```
2. **A poisoned image left over from a failed prior build.** If `docker compose build` errored out partway through, the previously-tagged `coffeeshop-lab/wazuh-*:4.9.2` image is still sitting in your local store. The next `docker compose up` will happily run *that* image, and you'll spend ten minutes wondering why your fix did nothing. Nuke it before rebuilding:
   ```bash
   docker image rm coffeeshop-lab/wazuh-manager:4.9.2 \
                    coffeeshop-lab/wazuh-dashboard:4.9.2
   docker compose build --no-cache wazuh-manager wazuh-dashboard
   docker compose up -d wazuh-manager wazuh-dashboard
   ```

A useful sanity check, especially when iterating on the dashboard Dockerfile:

```bash
# What image did the running container *actually* come from?
docker inspect wazuh-dashboard \
  --format '{{.Image}} {{.Config.Image}}'
docker image inspect coffeeshop-lab/wazuh-dashboard:4.9.2 \
  --format '{{.Created}} {{.Id}}'
```

If `Created` is older than your last edit, you're running a stale image.

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
