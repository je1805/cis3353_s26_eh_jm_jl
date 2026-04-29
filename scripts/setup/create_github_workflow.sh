#!/bin/bash
# Automatically generated script to create GitHub milestones, labels, and issues for the project.

echo "Creating Labels..."
gh label create "user-story" --color "0e8a16" --description "A goal from a user's perspective" --force 2>/dev/null || true
gh label create "bug" --color "d73a4a" --description "A defect found during build, attack, or defend" --force 2>/dev/null || true
gh label create "documentation" --color "0075ca" --description "Documentation tasks" --force 2>/dev/null || true
gh label create "infrastructure" --color "bfd4f2" --description "Infrastructure and environment setup" --force 2>/dev/null || true
gh label create "siem" --color "5319e7" --description "Wazuh SIEM stack tasks" --force 2>/dev/null || true
gh label create "attack" --color "d93f0b" --description "Attacker toolkit and scripts" --force 2>/dev/null || true
gh label create "XS" --color "ededed" --description "Extra Small Size" --force 2>/dev/null || true
gh label create "S" --color "c2e0c6" --description "Small Size" --force 2>/dev/null || true
gh label create "M" --color "bfdadc" --description "Medium Size" --force 2>/dev/null || true
gh label create "L" --color "f9d0c4" --description "Large Size" --force 2>/dev/null || true
gh label create "1" --color "ffffff" --description "1 Story Point" --force 2>/dev/null || true
gh label create "2" --color "ffffff" --description "2 Story Points" --force 2>/dev/null || true
gh label create "3" --color "ffffff" --description "3 Story Points" --force 2>/dev/null || true
gh label create "5" --color "ffffff" --description "5 Story Points" --force 2>/dev/null || true
gh label create "8" --color "ffffff" --description "8 Story Points" --force 2>/dev/null || true

echo "Creating Milestones..."
# Ignore errors if milestones already exist
gh api repos/:owner/:repo/milestones -f title="M1 - Project Setup & Planning" -f state="open" --silent 2>/dev/null || true
gh api repos/:owner/:repo/milestones -f title="M2 - Base Infrastructure Deployment" -f state="open" --silent 2>/dev/null || true
gh api repos/:owner/:repo/milestones -f title="M3 - Build Phase Complete (target + attacker)" -f state="open" --silent 2>/dev/null || true
gh api repos/:owner/:repo/milestones -f title="M4 - Defend Phase Complete (SIEM + AR enforcing)" -f state="open" --silent 2>/dev/null || true
gh api repos/:owner/:repo/milestones -f title="M5 - Documentation, Demo & Presentation" -f state="open" --silent 2>/dev/null || true

echo "Creating User Stories and Tasks..."

create_us() {
    local title="$1"
    local milestone="$2"
    local labels="$3"
    local body="$4"
    # Create the User Story and get its URL/ID
    US_URL=$(gh issue create --title "$title" --milestone "$milestone" --label "$labels" --body "$body")
    echo "$US_URL"
}

create_task() {
    local title="$1"
    local parent_url="$2"
    local labels="$3"
    gh issue create --title "$title" --label "$labels" --body "Parent User Story: $parent_url"
}

# US-01
US_URL=$(create_us "US-01: Project Foundation" "M1 - Project Setup & Planning" "user-story,2" "As a project lead, I want a structured Git repository with Wiki and project board so that the team has a single source of truth for code, docs, and progress.")
create_task "T-01.1 — Initialize repository per naming convention; add .gitignore, README.md, CODEOWNERS, .env.example" "$US_URL" "XS"
create_task "T-01.2 — Set up Wiki home page as a TOC linking to Architecture / Build / Attack / Defend / Sprint Notes / Incident Ledger / Final Report" "$US_URL" "S"
create_task "T-01.3 — Configure GitHub Project (Iterative Development template), create 7 two-week iterations, define labels" "$US_URL" "S"

# US-02
US_URL=$(create_us "US-02: Architecture & Threat Model" "M1 - Project Setup & Planning" "user-story,3" "As a system architect, I want an architecture diagram and STRIDE threat model so that the team aligns on scope, attack surface, and defensive priorities before we write any Dockerfiles.")
create_task "T-02.1 — Draft architecture diagram v1 (containers, network, IPs, ports) as SVG in docs/architecture-diagram.svg" "$US_URL" "M"
create_task "T-02.2 — Author threat model: STRIDE per component in docs/threat-model.md" "$US_URL" "M"
create_task "T-02.3 — Write mission statement, module mapping, and Build/Attack/Defend phase summary into README.md" "$US_URL" "S"

# US-03
US_URL=$(create_us "US-03: Container Network Foundation" "M2 - Base Infrastructure Deployment" "user-story,infrastructure,3" "As a system architect, I want a Docker bridge network with static IPs so that container addressing is predictable and config files can reference fixed targets.")
create_task "T-03.1 — Define coffeeshop-net bridge in docker-compose.yml" "$US_URL" "S"
create_task "T-03.2 — Populate .env with static IP plan and document each" "$US_URL" "XS"
create_task "T-03.3 — Verify reachability: ping matrix between every pair of containers, screenshot results" "$US_URL" "S"

# US-04
US_URL=$(create_us "US-04: Containerized Firewall" "M2 - Base Infrastructure Deployment" "user-story,infrastructure,5" "As a system architect, I want a containerized firewall with iptables baseline rules and rate limits so that traffic policy is enforceable and observable.")
create_task "T-04.1 — Build alpine 3.19 firewall image with iptables, nftables, conntrack-tools, suricata, lighttpd, php83, supervisord" "$US_URL" "L"
create_task "T-04.2 — Author firewall-init.sh with FORWARD policy DROP, rate limits, LOG_BLOCKED_ATTACKER chain" "$US_URL" "M"
create_task "T-04.3 — Configure rsyslog to emit tags consumed by Wazuh decoder" "$US_URL" "S"
create_task "T-04.4 — Test rate limits with hping3 from kali; capture iptables packet counters before/after" "$US_URL" "M"

# US-05
US_URL=$(create_us "US-05: Vulnerable Web Application" "M3 - Build Phase Complete (target + attacker)" "user-story,infrastructure,5" "As a security analyst, I want a vulnerable Jokopi web app deployed so that we have a realistic attack target with known SQLi/XSS/auth weaknesses.")
create_task "T-05.1 — Build jokopi-coffeeshop image with nginx + php8.1-fpm + sqlite + intentionally insecure nginx.conf" "$US_URL" "L"
create_task "T-05.2 — Add link-php-fpm-sock.sh runtime helper and configure supervisord program ordering" "$US_URL" "M"
create_task "T-05.3 — Bake wazuh-agent into image with build-arg WAZUH_REGISTRATION_PASSWORD" "$US_URL" "M"
create_task "T-05.4 — Smoke-test endpoints and verify access.log writing in expected format" "$US_URL" "S"

# US-06
US_URL=$(create_us "US-06: Attacker Toolkit" "M3 - Build Phase Complete (target + attacker)" "user-story,attack,3" "As a penetration tester, I want a Kali container with attack tooling so that we can demonstrate sqlmap, hydra, nikto, and nmap against Jokopi reproducibly.")
create_task "T-06.1 — Build kali-attacker image with sqlmap, hydra, nikto, gobuster, nmap, hping3, curl preinstalled" "$US_URL" "M"
create_task "T-06.2 — Create attack scripts in scripts/attacks/" "$US_URL" "M"
create_task "T-06.3 — Document each attack scenario in Wiki page Attack Catalog" "$US_URL" "S"

# US-07
US_URL=$(create_us "US-07: Wazuh SIEM Stack" "M4 - Defend Phase Complete (SIEM + AR enforcing)" "user-story,siem,8" "As a security analyst, I want a Wazuh SIEM stack with agent-based log collection from Jokopi so that we have a centralized telemetry pipeline.")
create_task "T-07.1 — Deploy wazuh-indexer with security plugin disabled" "$US_URL" "L"
create_task "T-07.2 — Build custom wazuh-manager image with VOLUME-seeding workaround" "$US_URL" "L"
create_task "T-07.3 — Build custom wazuh-dashboard image with securityDashboards plugin removed" "$US_URL" "M"
create_task "T-07.4 — Verify end-to-end: agent on jokopi shows Active, alerts arrive in alerts.json, dashboard renders" "$US_URL" "M"

# US-08
US_URL=$(create_us "US-08: Custom Detection Rules" "M4 - Defend Phase Complete (SIEM + AR enforcing)" "user-story,siem,5" "As a security analyst, I want custom Wazuh detection rules for SQLi, XSS, brute force, traversal, and exfiltration.")
create_task "T-08.1 — Author local_decoder.xml" "$US_URL" "M"
create_task "T-08.2 — Author local_rules.xml with 14 rules across bands 100100–100303" "$US_URL" "L"
create_task "T-08.3 — Validate every rule with wazuh-logtest" "$US_URL" "M"

# US-09
US_URL=$(create_us "US-09: Automated Active Response" "M4 - Defend Phase Complete (SIEM + AR enforcing)" "user-story,siem,8" "As a security operator, I want Wazuh to automatically block attacker IPs at the host kernel netfilter when level-15 rules fire.")
create_task "T-09.1 — Author block-ip-firewall.sh AR script with stdin-JSON parsing" "$US_URL" "L"
create_task "T-09.2 — Bind-mount /var/run/docker.sock into manager; install docker-cli + jq" "$US_URL" "M"
create_task "T-09.3 — Author handler.sh in firewall for busybox-grep-compatible IP validation" "$US_URL" "M"
create_task "T-09.4 — Add host-level enforcement in docker container" "$US_URL" "L"
create_task "T-09.5 — End-to-end test from clean state" "$US_URL" "M"

# US-10
US_URL=$(create_us "US-10: Documentation, Demo, Presentation" "M5 - Documentation, Demo & Presentation" "user-story,documentation,3" "As a writer, I want comprehensive Wiki documentation, a recorded demo, and a presentation deck.")
create_task "T-10.1 — Write Wiki pages: Architecture, Build Phase, Attack Phase, Defend Phase, Incident Ledger" "$US_URL" "L"
create_task "T-10.2 — Record 3–5 minute screen demo" "$US_URL" "M"
create_task "T-10.3 — Compile 28-slide deck in reports/final_presentation.md; rehearse" "$US_URL" "L"
create_task "T-10.4 — Reproducibility test on a clean machine" "$US_URL" "M"

echo "Creating Bugs..."
gh issue create --title "BUG-01: Wazuh manager false-positive directory-traversal storm" --milestone "M4 - Defend Phase Complete (SIEM + AR enforcing)" --label "bug" --body "Symptom: Within ~2 minutes of deploying SIEM and the agent, rule 100130 fired ~99,000 times producing identical directory traversal alerts."
gh issue create --title "BUG-02: Active-response script: ERROR: No source IP provided on every fire" --milestone "M4 - Defend Phase Complete (SIEM + AR enforcing)" --label "bug" --body "Symptom: /var/ossec/logs/active-responses.log accumulated hundreds of block-ip-firewall: ERROR: No source IP provided entries."
gh issue create --title "BUG-03: Firewall iptables rules placed but not enforcing" --milestone "M4 - Defend Phase Complete (SIEM + AR enforcing)" --label "bug" --body "Symptom: AR successfully placed LOG_BLOCKED_ATTACKER rules in pfsense-firewall's FORWARD chain... But packet/byte counters stayed at 0 0."

echo "Workflow Creation Complete!"
