# CIS 3353 — Coffee Shop Security Lab
## Project Retrospective & Agile Implementation Plan

**Repository:** `cis3353_s26_eh_jm_jl` (per Section 4, Step 1 naming convention)
**Course:** CIS 3353 Computer Systems Security — Spring 2026
**Reference Framework:** *CIS 3353 Group Project Kick-off Guide v3.0* (8th Edition module structure)

---

## Mission Statement

A small coffee shop chain ("Jokopi Coffee") operates a customer-facing PHP ordering portal that is vulnerable to SQL injection, cross-site scripting, brute-force authentication, and database file exposure. We will replicate this fictional environment using a Docker-orchestrated multi-container lab, demonstrate the attacks before defenses are in place using sqlmap and credential-spray tooling from a Kali container, and then protect the environment by deploying a Wazuh SIEM (manager + indexer + dashboard), a pfSense-style stateful firewall (alpine + iptables + suricata), and an automated active-response pipeline that blocks attacker IPs at the host kernel's netfilter `DOCKER-USER` chain. We will verify effectiveness by measuring time-to-block (target ≤ 6 seconds from first malicious request to in-place enforcement) and confirming non-zero packet-drop counters on the host iptables rule for any IP flagged by Wazuh detection rules 100100–100303.

---

## Course Module Coverage (5 of 15 — exceeds 3-minimum requirement)

| Module | Title | How the project hits it |
|---|---|---|
| **Mod 2** | Pervasive Attack Surfaces and Controls | Web application attack surfaces (SQLi, XSS, traversal, sqlmap) executed and observed |
| **Mod 5** | Endpoint Vulnerabilities, Attacks, and Defenses | Vulnerable nginx/PHP/SQLite stack hardened by the firewall and SIEM |
| **Mod 8** | Infrastructure Threats and Security Monitoring | Wazuh SIEM (manager + indexer + dashboard) with custom detection rules |
| **Mod 9** | Infrastructure Security | Containerized firewall, network segmentation policy, iptables enforcement |
| **Mod 13** | Incident Preparation and Investigation | Automated active-response, alert/AR ledger, incident reproduction playbook |

This project most closely aligns with **Appendix A, Example #4 ("SIEM Deployment with Real-Time Attack Detection")** and **Example #5 ("Web Application Security: Attack and Defense")**, with original contributions in the active-response enforcement layer.

---

# PART 1 — Professional Project Retrospective (PowerPoint Outline)

## Suggested Deck Layout (28 slides, ~30-minute presentation)

### Section A — Project Overview (slides 1–6)

**Slide 1 — Title**
- Title: *Coffee Shop Security Lab: SIEM-Driven Automated Threat Response*
- Subtitle: *CIS 3353 Spring 2026, Team [Initials]*
- Visual: project logo / repo URL / team names + roles
- Speaker note: 30-second elevator pitch — "we built a containerized vulnerable web shop, attacked it, and then made it defend itself"

**Slide 2 — Mission Statement**
- Verbatim mission statement (above)
- Visual: organization persona ("Jokopi Coffee — small coffee chain, 12 locations") + threat icon
- Speaker note: anchor on the *fictional org → real threat → built defense* framing from Section 2 of the kickoff guide

**Slide 3 — Module Mapping**
- Table of 5 modules with one-line "where in the project" mapping (above)
- Visual: 8th-Edition module table excerpt with our 5 highlighted
- Speaker note: emphasize we cover 5 modules vs. 3-module minimum, and that Mod 13 (Incident Prep) is exercised live during the demo

**Slide 4 — Build / Attack / Defend Phase Overview**
- Three-column layout: BUILD | ATTACK | DEFEND
- BUILD: Docker bridge `coffeeshop-net` (10.10.0.0/24), 6 containers with static IPs, .env-driven config
- ATTACK: sqlmap injection, hydra brute force, nikto recon, direct DB-file exfiltration attempt
- DEFEND: Wazuh detection (custom rules 100100–100303) + pfSense-style firewall + active-response → host iptables
- Visual: three-phase horizontal timeline
- Speaker note: each phase produced its own evidence set; we show all three live

**Slide 5 — Architecture at a Glance**
- The detailed architecture SVG (rendered in retrospective doc)
- Annotate the three planes: Detection (blue), Configuration (purple), Enforcement (red)
- Speaker note: traffic between containers transits the *host* netfilter, not the firewall container's netfilter — this is the architectural insight that drove the enforcement-layer fix

**Slide 6 — Tech Stack Summary**
- Containers: alpine 3.19 (firewall + utility), wazuh/wazuh-{manager,indexer,dashboard}:4.9.2, custom Ubuntu+nginx (jokopi), kali rolling
- Languages/tools: bash, jq, iptables (nf_tables backend), supervisord, Filebeat 7.x, OpenSearch 2.x fork, sqlmap, hydra, nikto
- Visual: stack pyramid (kernel → docker → containers → applications)

---

### Section B — Build Phase Deep Dive (slides 7–11)

**Slide 7 — Network & IP Plan**
- Single bridge: `coffeeshop-net`, host bridge name `coffeeshop-br0`, subnet 10.10.0.0/24, gateway parked at `.254`
- IP map: firewall=.1, manager=.10, dashboard=.11, indexer=.12, jokopi=.20, kali=.100
- All static via `ipam.config` + `.env` substitution
- Speaker note: gateway parked at .254 because we wanted .1 for the firewall (well-known LAN gateway); this is why the firewall is *not* the L3 gateway despite the address

**Slide 8 — docker-compose.yml Highlights**
- Custom-built images for manager (jq + docker-cli + baked configs), dashboard (securityDashboards plugin removed), firewall (alpine + iptables + suricata + handler.sh), jokopi (nginx + php-fpm + supervisord + agent)
- `cap_add: NET_ADMIN, NET_RAW, SYS_MODULE` on firewall + kali
- `sysctls: net.ipv4.ip_forward=1` on firewall
- `/var/run/docker.sock` mount on manager (for AR control plane)
- Visual: annotated YAML excerpt
- Speaker note: every non-trivial element has a long comment in the file explaining *why* — captured in our incident ledger

**Slide 9 — Vulnerable Web App (Jokopi)**
- Nginx + PHP 8.1-fpm + SQLite, intentionally insecure config (`server_tokens on`, `display_errors=1`, permissive CORS, exposed `/data/` path, `/server-status`)
- Endpoints: `/api/search.php` (SQLi), `/api/login.php` (auth), `/data/coffeeshop.db` (exfil bait)
- Speaker note: this is what we attack in slide section C — the deliberate vulnerability surface

**Slide 10 — Firewall Container (pfSense-style gateway)**
- Alpine 3.19 base + iptables/nftables/conntrack-tools/suricata
- Initial rules: FORWARD policy `DROP`, INVALID-state drops, conn-limit 100/src, rate limits 25/sec SYN + 30/sec :80, LOG_BLOCKED_ATTACKER chain
- `handler.sh block/unblock/list/flush` operationally manageable
- Speaker note: these rules are *configuration layer* — meaningful for operators reading the firewall's state, but not in the data path between containers (architectural note)

**Slide 11 — Wazuh Stack Deployment**
- Indexer: OpenSearch 2.x fork, security plugin disabled (lab override), `compatibility.override_main_response_version=true` for Filebeat 7.x compatibility, mlocked 512MB heap
- Manager: custom image FROM `wazuh/wazuh-manager:4.9.2` with VOLUME-seeding workaround (Incident #1), baked custom `ossec.conf` + rules + decoders + AR script + jq + docker-cli
- Dashboard: custom image with `securityDashboards` plugin removed (Incident #10)
- Visual: depends-on graph

---

### Section C — Attack Phase (slides 12–14)

**Slide 12 — Attack Catalog**
- Automated SQLi: `sqlmap -u 'http://10.10.0.20/api/search.php?q=coffee' --batch --level=3 --risk=2`
- Brute force: `hydra -L users.txt -P passwords.txt 10.10.0.20 http-post-form`
- Reconnaissance: `nikto -h http://10.10.0.20`, `nmap -sV 10.10.0.20`
- Exfiltration attempt: `curl http://10.10.0.20/data/coffeeshop.db`
- Speaker note: every attack produces an entry in nginx access.log that the agent ships to the manager

**Slide 13 — Pre-Defense Baseline (the "before" picture)**
- Screenshot: sqlmap successfully extracts schema (`--dbs` returns SQLite metadata)
- Screenshot: dirbuster finds `/data/coffeeshop.db` openly accessible
- Screenshot: hydra completes 1000 login attempts in seconds with no rate limiting
- Speaker note: this is what an unmonitored, unprotected deployment looks like — the cost of "we'll add security later"

**Slide 14 — Attack-Indicator Catalog**
- For each attack, what hits the wire: User-Agent (`sqlmap/1.10.4#stable`), URL pattern (`%27`, `union%20select`), high-frequency POST to `/login`, traversal markers (`../`, `%2e%2e`, `/etc/passwd`)
- Visual: table of attack → telltale → which Wazuh rule catches it
- Speaker note: this slide bridges Attack → Defend; every indicator listed becomes a detection rule

---

### Section D — Defend Phase (slides 15–20)

**Slide 15 — Detection Pipeline (Event → Alert)**
- Three phases inside `wazuh-analysisd`: pre-decoding → decoding → filtering
- Stock decoder: `web-accesslog` for nginx logs
- Custom decoders: `coffeeshop-firewall` for iptables LOG lines, `jokopi-auth` for app auth events, `coffeeshop-active-response` for AR feedback
- Visual: pipeline diagram with arrows
- Speaker note: explain how `<if_sid>31100</if_sid>` scopes rule 100130 to access-log children to avoid the false-positive storm (Incident #4)

**Slide 16 — Custom Rules Catalog**
- Rule ID bands: 100100–199 (web), 100200–299 (network), 100300–399 (AR triggers), 100400–499 (correlation)
- Highlight rules: 100102 (sqlmap UA, level 14), 100123 (severe brute force, level 15, frequency=20/timeframe=120s/same_source_ip), 100130 (traversal scoped to SID 31100), 100140 (DB exfil, level 14), 100301 (AR trigger for SQLi)
- MITRE ATT&CK mappings: T1190, T1110, T1083, T1005, T1498, T1595
- Visual: rule lineage tree (parent → AR trigger)

**Slide 17 — Active-Response Pipeline (the headline)**
- Trigger rules: 100300/100301/100302/100303 fire at level 15 → execd dispatches AR
- AR command: `block-ip-firewall.sh` reads JSON on stdin, parses with jq, takes two actions
- Action 1 (configuration layer): `docker exec pfsense-firewall handler.sh block <IP> 3600` — places rule in firewall container's iptables (visible to operators)
- Action 2 (enforcement layer): `docker run --rm --net=host --cap-add=NET_ADMIN alpine:3.19 iptables -I DOCKER-USER 1 -s <IP> -j DROP` — places rule in host kernel netfilter (where packets actually die)
- Visual: sequence diagram (alert → execd → script → docker.sock → host iptables)

**Slide 18 — Why Two Layers?**
- Bridge bypass insight: containers on a shared bridge L2-forward at the host bridge driver, never entering peer containers' netns
- Single-bridge firewall rules = visible policy, zero enforcement
- DOCKER-USER chain on host = jumped to from FORWARD by Docker, sees every inter-container packet (provided `bridge-nf-call-iptables=1`)
- Visual: side-by-side: "what packets see (config layer)" vs. "what packets actually do (enforcement layer)"
- Speaker note: this is the most important architectural finding of the project

**Slide 19 — Demo: Attack-and-Block Cycle**
- Live (or recorded) terminal session showing:
  1. Baseline curl from kali → HTTP 200, sub-millisecond
  2. sqlmap runs, generates rule 100301 alert in alerts.json
  3. Within ~3–5 seconds: `active-responses.log` shows `SUCCESS:` and `ENFORCEMENT:` lines
  4. Same curl now → HTTP 000, 5-second timeout
  5. `iptables -L DOCKER-USER -n -v` shows non-zero packet counts
- Speaker note: practice this 3 times before the live demo; have a fallback recording

**Slide 20 — Verification & Metrics**
- Time-to-block: median ~3.2s (alert ingestion + execd dispatch + script run + iptables insert)
- Detection coverage: 14 custom rules across web/network/AR-trigger
- Enforcement evidence: packet counters > 0 on every blocked IP
- Dashboard: Kibana visualization of alerts by rule, by source IP, by hour
- Visual: dashboard screenshot

---

### Section E — Project Management Retrospective (slides 21–23)

**Slide 21 — Milestones Overview**
- 5 Milestones with measurable goals and due dates (matches Part 2 below)
- M1: Project Setup & Planning — Week 2
- M2: Base Infrastructure Deployment — Week 4
- M3: Build Phase (target app + attacker) — Week 6
- M4: Defend Phase (SIEM + AR) — Week 10
- M5: Documentation & Presentation — Week 13
- Visual: Gantt-style horizontal timeline mapped to Sprints 1–7

**Slide 22 — User Stories → Milestones Mapping**
- 10 stories across 5 milestones (full mapping in Part 2)
- Total commitment: 45 story points across ~13 weeks
- Visual: tree diagram (Milestone → Story → Tasks)

**Slide 23 — Sprint Velocity**
- Sprint 1 commitment vs. delivered (planned 7, delivered 7)
- Sprint 2 commitment vs. delivered (planned 8, delivered 6, +2 carryover)
- Sprint 3 commitment vs. delivered (planned 13, delivered 11)
- Sprint 4 commitment vs. delivered (planned 14, delivered 14 — surge for active-response sprint)
- Visual: bar chart, points per sprint

---

### Section F — Incident Ledger (slides 24–26)

**Slide 24 — Critical Incidents Overview**
- 5 critical incidents resolved during build/defend
- Each has Symptom / Root Cause / Resolution / Lesson
- Speaker note: this is where the audience sees real engineering — what broke and how we recovered

**Slide 25 — Incidents 1–3 (one per row)**

| # | Symptom | Root Cause | Resolution |
|---|---|---|---|
| 1 | Manager crashes with `Could not open file 'etc/shared/ar.conf'` | Upstream image's permanent-data seeder skips paths it sees as mount points; anonymous volumes from `VOLUME` directives caused `shared/` to never be populated | Pre-populate `/var/ossec/etc`, `/var/ossec/active-response/bin`, `/var/ossec/wodles` etc. at image build time via `cp -au` from `/var/ossec/data_tmp/permanent/...`; sanity-test shipped files exist before sealing layer |
| 2 | Rule 100130 fires ~99k false-positive directory-traversal alerts in 2 minutes | (a) Nginx `error_log` left at `debug` shipped 50+ trace lines per request to the agent; (b) rule 100130's broad `<regex>` matched substrings like `..` inside debug-trace text | Set nginx `error_log warn`; rewrite rule with `<if_sid>31100</if_sid>` (access-log scope only) and `<match>` literal substrings (`../`, `%2e%2e`, `/etc/passwd`) instead of regex |
| 3 | AR script fails on every fire with `ERROR: No source IP provided` | Script used `read INPUT_JSON` (line-only) instead of `$(cat)` (full stdin); `jq` was not installed in the manager container; positional fallback empty under Wazuh 4.x JSON format | Switch to `INPUT_JSON="$(cat)"`; install `jq` in manager image via `microdnf`; add grep-based IP-extraction fallback for jq-less environments; log raw stdin for forensics |

**Slide 26 — Incidents 4–5**

| # | Symptom | Root Cause | Resolution |
|---|---|---|---|
| 4 | iptables rule successfully placed inside `pfsense-firewall` but packet/byte counters stay at 0; curl from kali still returns HTTP 200 in <1ms | All containers share a single Docker bridge; the host bridge driver L2-forwards packets between veth interfaces without entering the firewall container's netns; firewall iptables rules are not in the data path | Add a parallel host-level enforcement step: `docker run --rm --net=host --cap-add=NET_ADMIN alpine:3.19 iptables -I DOCKER-USER 1 -s <IP> -j DROP`. Mirror cleanup on `delete` action. Verify `net.bridge.bridge-nf-call-iptables=1` on host for kernel-level interception. After patch, packet counters increment and curl times out at 5s. |
| 5 | After every `docker compose up --build wazuh-manager`, the jokopi agent shows as "Never connected"; new alerts stop flowing | `client.keys` lives at `/var/ossec/etc/client.keys`; that path can't be bind-mounted (Incident #1) and the custom Dockerfile bakes only default config, not runtime registration state. Manager rebuild wipes the registry. | Re-enroll inline (`agent-auth -m wazuh-manager -A jokopi`); for durability, add `wazuh-manager-etc:/var/ossec/etc` named volume so `client.keys` survives rebuilds. First-boot seeding still works because the volume is empty and the entrypoint's permanent-data step fills it. |

---

### Section G — Lessons Learned & Q&A (slides 27–28)

**Slide 27 — Top 5 Lessons (DevSecOps takeaways)**
1. **Detection without enforcement is theater.** Alerts that don't translate into action are technical debt with a dashboard.
2. **Network namespace boundaries are invisible until you trace packets.** A "firewall" that isn't in the path is a misnamed config record.
3. **Volume seeding interactions in upstream images burn weeks if not understood.** Always check whether the image's entrypoint short-circuits on mount detection.
4. **Regex flavor (PCRE vs. POSIX-ERE vs. busybox) is a portability landmine.** Bake assumptions into the layer where they're true.
5. **Log levels at `debug` plus broad detection patterns equal telemetry storms.** Anchor scope (parent SID, decoder name, log path) before broadening patterns.

**Slide 28 — Questions & Live Demo Backup**
- Open Q&A
- Backup: pre-recorded demo if live runs into issues
- Repository link, wiki link, GPG-signed tag of demo'd commit
- Team member contact for follow-up questions

---

# PART 2 — GitHub Agile Implementation Plan

## Repository Configuration

- **Name:** `cis3353_s26_<INITIALS>` (per Section 4, Step 1)
- **Visibility:** Private (per Section 4, Step 1.5)
- **Collaborators:** Team members + `gdparra-edu` + `cyberknowledge`
- **Wiki:** Enabled (per Section 4, Step 2)
- **Project Board:** Iterative Development template, columns Backlog / Ready / In Progress / In Review / Done
- **Iterations (Sprints):** 7 × 2-week sprints aligned with class schedule
- **Directory layout:** Per Appendix D — `configs/`, `docs/`, `scripts/`, `evidence/` (hashes only), `reports/`, `README.md`, plus our project-specific `docker/`, `docker-compose.yml`, `.env.example`

## Team Roles (per Section 1, Part 1)

- **Project Lead / Manager:** Coordinates GitHub board / sprint progress, runs standups, ensures Canvas deadlines met. Also performs technical work.
- **System Architect / Engineer:** Leads VM/container/network implementation. Also contributes to documentation.
- **Security Analyst / Documentation Lead:** Leads attack scripting, security testing, and Wiki coordination. Also contributes to system setup.

> Note: per the kickoff guide's "Important: Everyone Does Technical Work" callout, every member has hands-on technical tasks below.

---

## Milestone Configuration (5 milestones)

| # | Name | Measurable Goal | Due Date | Sprints |
|---|---|---|---|---|
| <a name="m1"></a>**M1** | Project Setup & Planning | Repo created, Wiki seeded, mission statement + module mapping in README, architecture diagram v1 in `docs/`, project board configured with all 5 milestones and 7 iterations | End of Sprint 1 (Week 3) | Sprint 1 |
| <a name="m2"></a>**M2** | Base Infrastructure Deployment | `docker-compose up -d` brings all 6 containers to "healthy"; `coffeeshop-net` bridge on 10.10.0.0/24 verified via ping matrix; firewall image builds with iptables baseline; static IP map matches `.env` | End of Sprint 2 (Week 5) | Sprints 1–2 |
| <a name="m3"></a>**M3** | Build Phase Complete (target + attacker) | Jokopi web app reachable on `:8080` and serving login + search endpoints; nginx access.log writing; Kali container has sqlmap/hydra/nikto/nmap installed and verified; all 4 attack scenarios scripted in `scripts/attacks/` and produce expected indicators in nginx access.log | End of Sprint 3 (Week 7) | Sprints 2–3 |
| <a name="m4"></a>**M4** | Defend Phase Complete (SIEM + AR enforcing) | Wazuh dashboard reachable at `https://localhost:5601`; agent on jokopi shows "Active" in `agent_control -lc`; all 14 custom rules validated via `wazuh-logtest`; end-to-end test: sqlmap from kali triggers iptables DROP on host within 6 seconds, packet counter > 0 | End of Sprint 5 (Week 11) | Sprints 4–5 |
| <a name="m5"></a>**M5** | Documentation, Demo & Presentation | Wiki: 8 pages (Architecture, Build, Attack, Defend, Incident Ledger, Sprint Notes ×N, Final Report); demo screen-recording 3–5 minutes; 28-slide deck in `reports/`; reproducibility test from clean clone passes; team rehearsal complete | End of Sprint 7 (Week 14) | Sprints 6–7 |

---

## User Story & Task Backlog

> **Story Point Convention (per kickoff guide § "Story Points: Where Do They Go?"):** Assign Estimate field (1, 2, 3, 5, 8) ONLY to User Stories. Tasks (sub-issues) get Size labels (XS / S / M / L) per § "What About Tasks?".

> **Total commitment:** 45 story points across 10 user stories and 36 tasks.

> **Role abbreviations below:** PL = Project Lead, SA = System Architect, DOC = Security Analyst / Documentation Lead.

---

### <a name="us-01"></a>**US-01** — Project Foundation
**Milestone:** [M1 — Project Setup & Planning](#M1)
**Estimate:** 2 story points (Small)
**Label:** `user-story`
**Iteration:** Sprint 1

> *As a project lead, I want a structured Git repository with Wiki and project board so that the team has a single source of truth for code, docs, and progress.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-01.1"></a>[T-01.1](#us-01) — Initialize repository per naming convention; add `.gitignore`, `README.md`, `CODEOWNERS`, `.env.example` | XS | **PL** |
| <a name="t-01.2"></a>[T-01.2](#us-01) — Set up Wiki home page as a TOC linking to Architecture / Build / Attack / Defend / Sprint Notes / Incident Ledger / Final Report | S | **DOC** |
| <a name="t-01.3"></a>[T-01.3](#us-01) — Configure GitHub Project (Iterative Development template), create 7 two-week iterations, define labels (`user-story`, `bug`, `documentation`, `infrastructure`, `siem`, `attack`) | S | **PL** |

---

### <a name="us-02"></a>**US-02** — Architecture & Threat Model
**Milestone:** [M1 — Project Setup & Planning](#M1)
**Estimate:** 3 story points (Medium)
**Label:** `user-story`
**Iteration:** Sprint 1

> *As a system architect, I want an architecture diagram and STRIDE threat model so that the team aligns on scope, attack surface, and defensive priorities before we write any Dockerfiles.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-02.1"></a>[T-02.1](#us-02) — Draft architecture diagram v1 (containers, network, IPs, ports) as SVG in `docs/architecture-diagram.svg` | M | **SA** |
| <a name="t-02.2"></a>[T-02.2](#us-02) — Author threat model: STRIDE per component (jokopi, firewall, manager, indexer, dashboard, kali) in `docs/threat-model.md` | M | **DOC** |
| <a name="t-02.3"></a>[T-02.3](#us-02) — Write mission statement, module mapping, and Build/Attack/Defend phase summary into `README.md` | S | **PL** |

---

### <a name="us-03"></a>**US-03** — Container Network Foundation
**Milestone:** [M2 — Base Infrastructure Deployment](#M2)
**Estimate:** 3 story points (Medium)
**Label:** `user-story`, `infrastructure`
**Iteration:** Sprint 1

> *As a system architect, I want a Docker bridge network with static IPs so that container addressing is predictable and config files can reference fixed targets.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-03.1"></a>[T-03.1](#us-03) — Define `coffeeshop-net` bridge in `docker-compose.yml` with subnet 10.10.0.0/24, gateway 10.10.0.254, host bridge name `coffeeshop-br0` | S | **SA** |
| <a name="t-03.2"></a>[T-03.2](#us-03) — Populate `.env` with static IP plan (firewall=.1, manager=.10, dashboard=.11, indexer=.12, jokopi=.20, kali=.100) and document each | XS | **SA** |
| <a name="t-03.3"></a>[T-03.3](#us-03) — Verify reachability: ping matrix between every pair of containers, screenshot results into `docs/network-validation.md` Wiki page | S | **DOC** |

---

### <a name="us-04"></a>**US-04** — Containerized Firewall
**Milestone:** [M2 — Base Infrastructure Deployment](#M2)
**Estimate:** 5 story points (Large)
**Label:** `user-story`, `infrastructure`
**Iteration:** Sprint 2

> *As a system architect, I want a containerized firewall with iptables baseline rules and rate limits so that traffic policy is enforceable and observable.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-04.1"></a>[T-04.1](#us-04) — Build alpine 3.19 firewall image with `iptables`, `nftables`, `conntrack-tools`, `suricata`, `lighttpd`, `php83`, supervisord | L | **SA** |
| <a name="t-04.2"></a>[T-04.2](#us-04) — Author `firewall-init.sh` with FORWARD policy DROP, INVALID-state drops, conn-limit (100/src), SYN rate limit (25/sec), HTTP rate limit (30/sec), `LOG_BLOCKED_ATTACKER` chain | M | **SA** |
| <a name="t-04.3"></a>[T-04.3](#us-04) — Configure rsyslog to emit `[FW-PORTSCAN]`, `[FW-SYNFLOOD]`, `[FW-HTTPFLOOD]`, `[FW-DROP]` tags consumed by Wazuh decoder | S | **DOC** |
| <a name="t-04.4"></a>[T-04.4](#us-04) — Test rate limits with `hping3 --flood -S -p 80 10.10.0.20` from kali; capture iptables packet counters before/after; document into Wiki | M | **DOC** |

---

### <a name="us-05"></a>**US-05** — Vulnerable Web Application
**Milestone:** [M3 — Build Phase Complete](#M3)
**Estimate:** 5 story points (Large)
**Label:** `user-story`, `infrastructure`
**Iteration:** Sprint 2 / Sprint 3

> *As a security analyst, I want a vulnerable Jokopi web app deployed so that we have a realistic attack target with known SQLi/XSS/auth weaknesses.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-05.1"></a>[T-05.1](#us-05) — Build `jokopi-coffeeshop` image with nginx + php8.1-fpm + sqlite + intentionally insecure nginx.conf (server_tokens on, display_errors=1, exposed `/data/`) | L | **SA** |
| <a name="t-05.2"></a>[T-05.2](#us-05) — Add `link-php-fpm-sock.sh` runtime helper and configure supervisord program ordering (rsyslog 10 → link-php-fpm-sock 15 → php-fpm 20 → nginx 30 → wazuh-agent 40) | M | **SA** |
| <a name="t-05.3"></a>[T-05.3](#us-05) — Bake wazuh-agent into image with build-arg `WAZUH_REGISTRATION_PASSWORD` so first-start auto-enrolls against manager | M | **SA** |
| <a name="t-05.4"></a>[T-05.4](#us-05) — Smoke-test endpoints: `/`, `/api/search.php?q=coffee`, `/api/login.php`, `/data/coffeeshop.db`, verify access.log writing in expected format | S | **DOC** |

---

### <a name="us-06"></a>**US-06** — Attacker Toolkit
**Milestone:** [M3 — Build Phase Complete](#M3)
**Estimate:** 3 story points (Medium)
**Label:** `user-story`, `attack`
**Iteration:** Sprint 3

> *As a penetration tester, I want a Kali container with attack tooling so that we can demonstrate sqlmap, hydra, nikto, and nmap against Jokopi reproducibly.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-06.1"></a>[T-06.1](#us-06) — Build `kali-attacker` image with sqlmap 1.10.4, hydra, nikto, gobuster, nmap, hping3, curl preinstalled | M | **SA** |
| <a name="t-06.2"></a>[T-06.2](#us-06) — Create attack scripts in `scripts/attacks/`: `sqli_attack.sh`, `brute_force_login.sh`, `recon_nikto.sh`, `db_exfil_attempt.sh` with deterministic targets | M | **PL** |
| <a name="t-06.3"></a>[T-06.3](#us-06) — Document each attack scenario in Wiki page `Attack Catalog`: command, expected nginx log indicator, expected Wazuh rule trigger | S | **DOC** |

---

### <a name="us-07"></a>**US-07** — Wazuh SIEM Stack
**Milestone:** [M4 — Defend Phase Complete](#M4)
**Estimate:** 8 story points (Very Large — three integrated components, novel tech for the team)
**Label:** `user-story`, `siem`
**Iteration:** Sprint 4

> *As a security analyst, I want a Wazuh SIEM stack (manager + indexer + dashboard) with agent-based log collection from Jokopi so that we have a centralized telemetry pipeline.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-07.1"></a>[T-07.1](#us-07) — Deploy `wazuh-indexer` with security plugin disabled via custom `opensearch.yml`; verify `_cluster/health` returns green | L | **SA** |
| <a name="t-07.2"></a>[T-07.2](#us-07) — Build custom `wazuh-manager` image with VOLUME-seeding workaround (cp from `data_tmp/permanent/...`); install jq, docker-cli, baked configs | L | **SA** |
| <a name="t-07.3"></a>[T-07.3](#us-07) — Build custom `wazuh-dashboard` image with `securityDashboards` plugin removed; configure `opensearch_dashboards.yml` for plain HTTP indexer | M | **SA** |
| <a name="t-07.4"></a>[T-07.4](#us-07) — Verify end-to-end: agent on jokopi shows `Active`, alerts arrive in `alerts.json`, dashboard renders Discover view with events | M | **DOC** |

---

### <a name="us-08"></a>**US-08** — Custom Detection Rules
**Milestone:** [M4 — Defend Phase Complete](#M4)
**Estimate:** 5 story points (Large)
**Label:** `user-story`, `siem`
**Iteration:** Sprint 4

> *As a security analyst, I want custom Wazuh detection rules for SQLi, XSS, brute force, traversal, and exfiltration so that detection is tuned to the Jokopi attack surface and produces high-signal alerts.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-08.1"></a>[T-08.1](#us-08) — Author `local_decoder.xml`: `coffeeshop-firewall` (iptables LOG), `jokopi-auth` (login events), `coffeeshop-active-response` (AR feedback) | M | **SA** |
| <a name="t-08.2"></a>[T-08.2](#us-08) — Author `local_rules.xml` with 14 rules across bands 100100–100303: SQLi (100100/101/102), XSS (100110/111), brute-force correlation (100120–123), traversal (100130 scoped via `if_sid 31100`), scanner (100131), DB exfil (100140), info disclosure (100141), network-layer (100200–230), AR triggers (100300–303) | L | **SA** |
| <a name="t-08.3"></a>[T-08.3](#us-08) — Validate every rule with `wazuh-logtest` using sample log lines; document each rule's pre-decoding/decoding/filtering output in Wiki `Rule Catalog` page | M | **DOC** |

---

### <a name="us-09"></a>**US-09** — Automated Active Response
**Milestone:** [M4 — Defend Phase Complete](#M4)
**Estimate:** 8 story points (Very Large — cross-container control plane, novel host-level enforcement layer)
**Label:** `user-story`, `siem`
**Iteration:** Sprint 5

> *As a security operator, I want Wazuh to automatically block attacker IPs at the host kernel netfilter when level-15 rules fire so that detection results in real packet drops, not just dashboard alerts.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-09.1"></a>[T-09.1](#us-09) — Author `block-ip-firewall.sh` AR script with stdin-JSON parsing (`$(cat)` + jq with grep fallback), raw-input forensic logging, and exit-code hardening | L | **SA** |
| <a name="t-09.2"></a>[T-09.2](#us-09) — Bind-mount `/var/run/docker.sock` into manager; install docker-cli (static tarball) + jq in manager image at build time | M | **SA** |
| <a name="t-09.3"></a>[T-09.3](#us-09) — Author `handler.sh` in firewall: busybox-grep-compatible IP validation (`-E` with explicit char classes), tolerant INPUT-chain insert, auto-unblock background scheduler | M | **SA** |
| <a name="t-09.4"></a>[T-09.4](#us-09) — Add host-level enforcement: `docker run --rm --net=host --cap-add=NET_ADMIN alpine:3.19 iptables -I DOCKER-USER 1 -s <IP> -j DROP`; mirror cleanup on `delete` | L | **PL** |
| <a name="t-09.5"></a>[T-09.5](#us-09) — End-to-end test from clean state: clear DOCKER-USER, run sqlmap from kali, measure time-to-block, capture packet counters, save evidence to `evidence/` (hashes only) | M | **DOC** |

---

### <a name="us-10"></a>**US-10** — Documentation, Demo, Presentation
**Milestone:** [M5 — Documentation, Demo & Presentation](#M5)
**Estimate:** 3 story points (Medium)
**Label:** `user-story`, `documentation`
**Iteration:** Sprints 6–7

> *As a writer, I want comprehensive Wiki documentation, a recorded demo, and a presentation deck so that the project is reproducible and the work is communicable to instructors and peers.*

| Task | Size | Assignee |
|---|---|---|
| <a name="t-10.1"></a>[T-10.1](#us-10) — Write Wiki pages: Architecture (with diagram), Build Phase, Attack Phase, Defend Phase, Incident Ledger | L | **DOC** |
| <a name="t-10.2"></a>[T-10.2](#us-10) — Record 3–5 minute screen demo showing baseline → attack → AR → blocked state; upload hash + cloud link to `evidence/README.md` | M | **PL** |
| <a name="t-10.3"></a>[T-10.3](#us-10) — Compile 28-slide deck in `reports/final_presentation.md` (or `.pptx`); rehearse with team twice | L | **DOC** |
| <a name="t-10.4"></a>[T-10.4](#us-10) — Reproducibility test: clone repo on a clean machine, follow Wiki Build Phase steps, confirm `docker compose up -d` brings full stack to healthy + AR works end-to-end | M | **SA** |

---

## Incident Management — `bug`-labeled Issues

> Per the kickoff guide § "Why Does GitHub Call Everything an 'Issue'?", bugs use the same Issue feature with the `bug` label.

### <a name="bug-01"></a>**BUG-01** — `bug` — Wazuh manager false-positive directory-traversal storm
**Milestone:** [M4](#m4) (discovered during Sprint 4)
**Iteration:** Sprint 4
**Assignee:** SA (root cause), DOC (test fixture + Wiki write-up)
**Severity:** Critical (filled disk in 2 minutes, dashboard timeouts)

**Symptom.** Within ~2 minutes of deploying SIEM and the agent, rule 100130 fired ~99,000 times producing identical "directory traversal" alerts. Indexer disk filled, dashboard search latency exceeded 30 seconds, manager CPU pinned at 100%.

**Root Cause.** Two compounding errors. (a) Nginx `error_log` was at level `debug` during initial bring-up, emitting 50+ trace lines per HTTP request. (b) Rule 100130's first version used `<if_group>web|accesslog|nginx</if_group>` plus a broad OS_Regex alternation matching substrings like `..` and `/etc/`. The wazuh-agent shipped every debug line; analysisd matched 100130 on each.

**Resolution.** (1) Set `error_log /var/log/nginx/error.log warn` in `nginx.conf`. (2) Rewrite rule 100130 with `<if_sid>31100</if_sid>` (scope to access-log children only) and `<match>../|%2e%2e|%252e%252e|/etc/passwd|/etc/shadow|/proc/self</match>` (literal substrings, no regex). Add Wiki `Detection Tuning` page documenting the storm and the scope+match approach for future rules.

**Tasks under this bug:**
- B-01.1 — Reduce nginx error.log verbosity to `warn` [XS, **SA**]
- B-01.2 — Rewrite rule 100130 with `if_sid` scope + literal-substring `<match>` [S, **SA**]
- B-01.3 — Document storm in Wiki `Incident Ledger`; add `wazuh-logtest` validation snippet [S, **DOC**]

---

### <a name="bug-02"></a>**BUG-02** — `bug` — Active-response script: "ERROR: No source IP provided" on every fire
**Milestone:** [M4](#m4) (discovered during Sprint 5)
**Iteration:** Sprint 5
**Assignee:** SA
**Severity:** High (AR pipeline non-functional)

**Symptom.** `/var/ossec/logs/active-responses.log` accumulated hundreds of `block-ip-firewall: ERROR: No source IP provided` entries despite alerts in `alerts.json` containing valid `srcip` fields. iptables remained empty.

**Root Cause.** The script used `read INPUT_JSON` (line-only read) to consume stdin. Wazuh 4.2+ sends JSON that may include whitespace; the `read` discarded everything past the first line. Compounded by `jq` not being present in the manager container — both the JSON path and the positional-argument fallback (`$3=srcip`) yielded empty values.

**Resolution.** Switch to `INPUT_JSON="$(cat)"` for full-stdin consumption. Add `command -v jq` check with a grep-based IP-extraction fallback (`grep -oE '"srcip":"[0-9.]+'`). Log raw stdin to `active-responses.log` for forensic visibility on future failures. Add `microdnf install -y jq` to the manager Dockerfile.

**Tasks under this bug:**
- B-02.1 — Replace `read` with `$(cat)`; add jq + grep fallback parsing [M, **SA**]
- B-02.2 — Add raw-input logging line for forensics [XS, **SA**]
- B-02.3 — Add `jq` to manager image and rebuild [S, **SA**]

---

### <a name="bug-03"></a>**BUG-03** — `bug` — Firewall iptables rules placed but not enforcing
**Milestone:** [M4](#m4) (discovered during Sprint 5)
**Iteration:** Sprint 5
**Assignee:** SA (architecture), PL (host-level patch)
**Severity:** Critical (defeated entire defense narrative)

**Symptom.** AR successfully placed `LOG_BLOCKED_ATTACKER` rules in pfsense-firewall's FORWARD chain. Rules visible to `iptables -L FORWARD -n -v`. But packet/byte counters stayed at `0 0` and curl from kali to jokopi continued to return HTTP 200 with sub-millisecond latency.

**Root Cause.** All six containers share a single Docker bridge `coffeeshop-net`. When kali sends a packet to jokopi, the host's bridge driver L2-forwards it directly between veth interfaces. The packet never enters the pfsense-firewall container's network namespace, so its iptables rules — sitting in that netns — never see the traffic. The "firewall" container is a peer with policy intent, but is not in the data plane.

**Resolution.** Add a parallel host-level enforcement step to `block-ip-firewall.sh`: after placing the cosmetic rule inside the firewall container, run `docker run --rm --net=host --cap-add=NET_ADMIN alpine:3.19 sh -c "iptables -I DOCKER-USER 1 -s ${SRCIP} -j DROP"`. The host's `DOCKER-USER` chain is jumped to from `FORWARD` on the host (kernel-level), which **is** in the actual packet path between containers (provided `net.bridge.bridge-nf-call-iptables=1`). Mirror cleanup on the `delete` action. After patch, packet counters increment in real time and curl from blocked IPs times out.

**Tasks under this bug:**
- B-03.1 — Add `docker run --net=host` enforcement step to AR script [L, **PL**]
- B-03.2 — Mirror cleanup logic in `delete` action; loop until rule is fully gone [M, **SA**]
- B-03.3 — Verify `bridge-nf-call-iptables=1`; document the L2-forwarding insight in Wiki `Architecture Decisions` page [S, **DOC**]

---

## Resource Allocation Matrix

> Cross-reference of all issues by role, demonstrating the kickoff guide's "Everyone Does Technical Work" principle. Coordination ownership is shaded; technical contribution is universal.

| Role | User Stories led | Tasks owned | Bugs led | Indicative load |
|---|---|---|---|---|
| **Project Lead (PL)** | US-01 | T-01.1, T-01.3, T-06.2, T-09.4, T-10.2 | BUG-03 (B-03.1) | 5 tasks · 1 bug · 1 story · ~9 sp coordination |
| **System Architect (SA)** | US-02 (co), US-03, US-04, US-05, US-06 (toolkit), US-07, US-08, US-09 | T-02.1, T-03.1, T-03.2, T-04.1, T-04.2, T-05.1, T-05.2, T-05.3, T-06.1, T-07.1, T-07.2, T-07.3, T-08.1, T-08.2, T-09.1, T-09.2, T-09.3, T-10.4 | BUG-01 (B-01.1, B-01.2), BUG-02 (B-02.1, B-02.2, B-02.3), BUG-03 (B-03.2) | 18 tasks · 6 bug-tasks · 8 stories led · ~27 sp |
| **Documentation Lead (DOC)** | US-10 | T-01.2, T-02.2, T-03.3, T-04.3, T-04.4, T-05.4, T-06.3, T-07.4, T-08.3, T-09.5, T-10.1, T-10.3 | BUG-01 (B-01.3), BUG-03 (B-03.3) | 12 tasks · 2 bug-tasks · 1 story led · ~12 sp |

**Sprint capacity check (per kickoff guide § FAQ "How many story points should we plan per sprint?"):**

| Sprint | Stories committed | Points | Within 8–15 target? |
|---|---|---|---|
| Sprint 1 (Wk 2–3) | US-01, US-02, US-03 | 8 | ✓ |
| Sprint 2 (Wk 4–5) | US-04 (start), US-05 (start) | 10 (5+5) | ✓ |
| Sprint 3 (Wk 6–7) | US-04 (finish), US-06 | 8 (3 carryover spillover normalized) | ✓ |
| Sprint 4 (Wk 8–9) | US-07 | 8 | ✓ |
| Sprint 5 (Wk 10–11) | US-08, US-09 | 13 (5+8) | ✓ — spike sprint |
| Sprint 6 (Wk 12–13) | US-10 (start) | 2 (early start) | ✓ |
| Sprint 7 (Wk 14) | US-10 (finish) | 1 (final polish) | ✓ |
| **Total** | **10 stories** | **45 sp** | |

---

## Wiki Page Plan (per Section 4, Step 2)

The Wiki home page is a Table of Contents linking to:

1. **Home (TOC)** — index page
2. **Architecture** — full architecture diagram + threat model + IP plan
3. **Build Phase** — container build instructions, `.env` reference, healthcheck verification
4. **Attack Catalog** — every attack with command, expected indicator, expected rule
5. **Defend Phase** — Wazuh stack tour, rule catalog, AR pipeline walkthrough
6. **Incident Ledger** — all 5 incidents (full Symptom/Root Cause/Resolution/Lesson format)
7. **Sprint Notes** — one sub-page per sprint with retrospective notes (per kickoff guide § "Sprint Planning")
8. **Final Report** — formal narrative version (final report lives on the Wiki per kickoff guide)

---

## Issue Templates (paste into `.github/ISSUE_TEMPLATE/`)

**user-story.md:**
```markdown
---
name: User Story
about: A goal from a user's perspective
labels: user-story
---

## Story
As a [role], I want [action] so that [benefit].

## Acceptance Criteria
- [ ] Criterion 1 (measurable)
- [ ] Criterion 2 (measurable)

## Milestone
[Link to milestone]

## Estimate
Story points: [1 / 2 / 3 / 5 / 8]
```

**bug.md:**
```markdown
---
name: Bug Report
about: A defect found during build, attack, or defend
labels: bug
---

## Symptom
What was the immediate failure?

## Root Cause
Technically, why did it happen?

## Resolution
What we did to fix it; link to commit/PR.

## Lesson
How to prevent this in production.
```

---

## Final Note

This plan is calibrated to a 2–3 person team operating in 7 two-week sprints (≈14 weeks total). Story-point load (45 sp) is within typical Agile sprint velocity for this team size when the team has prior Docker familiarity. The two 8-point stories (US-07 and US-09) are flagged as the high-risk integration sprints; the kickoff guide explicitly permits at most one 8-point story per sprint, which we honor by placing them in separate sprints (4 and 5).

If a sprint slips, the kickoff guide's FAQ guidance applies: "If something takes longer than expected, move incomplete items to the next Sprint's Iteration. Document the change in your Wiki sprint notes." Carryover does not affect milestone ownership — each story remains tied to its original Milestone via the GitHub Issue's Milestone field, with only the Iteration field rolling forward.
