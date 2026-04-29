# Implementation Plan — Demo Day Friday

**Team:** Emily Hernandez (Project Lead), Jediah Mayberry (System Architect), Jeraldhin Leon (Security Analyst)

**Deadline:** Friday (3 days from now)

**Presentation format:** 20 min presentation + 5 min setup + 5 min Q&A

---

## What We Already Have (no work needed)

These items from the professor's checklist are already solid in the repo:

- System architecture diagram (ASCII diagram in README + dependency graph in DEPLOYMENT_GUIDE)
- High-level component summary (container table with IPs, roles, ports)
- Drilled-down component functionality (3 data flows: normal traffic, attack detection, active response)
- Dockerfiles with documentation (multi-stage builds, library installs, user generation, directory scaffolding)
- .dockerignore file
- Usage instructions (step-by-step setup, attack demos, common commands, troubleshooting)
- Detection rules with MITRE ATT&CK mappings (30+ rules in local_rules.xml)
- Docker Compose guide (DEPLOYMENT_GUIDE.md)
- Attack narrative / "story" foundation (Jokopi coffee shop scenario in README)
- CompTIA Security+ SY0-701 module mapping

---

## What's Missing — Day-by-Day Plan

### TUESDAY (Today) — Foundation Work

Owner tags: **E** = Emily, **JM** = Jediah, **JL** = Jeraldhin

#### T1. Re-enable OpenSearch Authentication [ ] — JM

The professor specifically said "Add authentication back in if possible… it's possible."
Security is currently disabled because of a cert path issue. Here's the fix:

**The problem:** The Wazuh indexer image expects certs at `/usr/share/wazuh-indexer/certs/`
but the security plugin's `path.conf` resolves to `/usr/share/wazuh-indexer`, so
SecurityManager blocks reads. The team disabled security entirely to work around it.

**The fix (3 files to change):**

1. `configs/wazuh/opensearch-indexer.yml` — replace the entire file with:
```yaml
network.host: 0.0.0.0
node.name: node-1
cluster.name: wazuh-cluster
discovery.type: single-node

path.data: /var/lib/wazuh-indexer
path.logs: /var/log/wazuh-indexer

# Re-enable security
plugins.security.disabled: false

plugins.security.ssl.http.enabled: true
plugins.security.ssl.http.pemcert_filepath: /usr/share/wazuh-indexer/certs/indexer.pem
plugins.security.ssl.http.pemkey_filepath: /usr/share/wazuh-indexer/certs/indexer-key.pem
plugins.security.ssl.http.pemtrustedcas_filepath: /usr/share/wazuh-indexer/certs/root-ca.pem

plugins.security.ssl.transport.enforce_hostname_verification: false
plugins.security.ssl.transport.pemcert_filepath: /usr/share/wazuh-indexer/certs/indexer.pem
plugins.security.ssl.transport.pemkey_filepath: /usr/share/wazuh-indexer/certs/indexer-key.pem
plugins.security.ssl.transport.pemtrustedcas_filepath: /usr/share/wazuh-indexer/certs/root-ca.pem

plugins.security.authcz.admin_dn:
  - "CN=wazuh-indexer,OU=Security,O=CIS3353Lab,L=SanAntonio,ST=TX,C=US"
plugins.security.nodes_dn:
  - "CN=wazuh-indexer,OU=Security,O=CIS3353Lab,L=SanAntonio,ST=TX,C=US"

plugins.security.allow_default_init_securityindex: true
plugins.security.restapi.roles_enabled: ["all_access", "security_rest_api_access"]

compatibility.override_main_response_version: true
```

2. `docker-compose.yml` — change INDEXER_URL lines back to HTTPS:
   - Line 140: change `http://` to `https://`
   - Line 192-193: change both `http://` to `https://`
   - Line 143: add back `- SSL_CERTIFICATE_AUTHORITIES=/etc/ssl/root-ca.pem`

3. Test it:
```bash
docker compose down -v   # wipe old indexer data (security index needs reinit)
bash scripts/setup/rotate-secrets.sh   # fresh certs
docker compose build --no-cache
docker compose up -d
# Wait ~3 min, then:
curl -sk https://localhost:9200 -u admin:$(grep INDEXER_PASSWORD .env | cut -d= -f2)
```

**If it doesn't work within 1 hour, fall back:** Keep security disabled but add a
slide explaining: "We identified the cert path issue, here's our planned fix, and
here's why we scoped it for a future sprint." The professor said "if possible" — 
showing you understand the problem is still worth points.


#### T2. Add CVE References to Detection Rules [ ] — JL

Open `configs/wazuh/rules/local_rules.xml` and add CVE numbers to each rule's
`<description>` or as `<info>` tags. Here's the mapping:

| Attack | CVE(s) to Reference | Why |
|--------|---------------------|-----|
| SQL Injection | CVE-2024-27956 (WordPress SQLi), CVE-2023-34362 (MOVEit SQLi) | Shows real-world SQLi impact |
| XSS (Reflected) | CVE-2024-21388 (Edge XSS), CVE-2023-29489 (cPanel XSS) | Common web app XSS |
| Brute Force | CVE-2023-46747 (F5 BIG-IP auth bypass) | Auth attack relevance |
| Directory Traversal | CVE-2024-3400 (Palo Alto PAN-OS path traversal) | Critical infrastructure vuln |
| DoS/DDoS | CVE-2023-44487 (HTTP/2 Rapid Reset) | Major DDoS technique |

Example — add to the SQL injection rule:
```xml
<rule id="100100" level="12">
  ...
  <description>SQL Injection attempt detected in web request</description>
  <info type="cve">CVE-2024-27956</info>
  <info type="link">https://nvd.nist.gov/vuln/detail/CVE-2024-27956</info>
  ...
</rule>
```

Also create a brief `docs/CVE_REFERENCE.md` that lists each CVE, what it is, how
it relates to attacks in the lab, and why it matters as a CSEC student.


#### T3. Start the Presentation Deck [ ] — E

Create the slide outline (content filled in Wed). Aim for 12-15 slides max for 20 min.

Suggested slide structure:
1. Title slide (team name, course, date)
2. The Problem — "Small businesses are targets" (1 slide, use a stat)
3. Meet Jokopi — the coffee shop scenario (1 slide, show the app screenshot)
4. Architecture Overview — the infographic (1 slide, redraw the ASCII diagram as a graphic)
5. What We Built — components at a glance (1 slide, icons for each container)
6. Attack Surface — what's vulnerable and why (1 slide)
7. Live Demo: Reconnaissance (1 slide with screenshot/video as backup)
8. Live Demo: SQL Injection + XSS (1 slide with screenshot/video)
9. Live Demo: Brute Force (1 slide)
10. Detection — Wazuh catches it (1 slide, dashboard screenshot)
11. Active Response — automatic blocking (1 slide, show the pipeline)
12. Log Filtering — signal vs. noise (1 slide)
13. CVEs — real-world relevance (1 slide)
14. Authentication & Hardening (1 slide — what we did or would do)
15. Future Plans (1 slide)
16. Q&A

**Use speaker notes for narration — keep slides visual with minimal text.**

---

### WEDNESDAY — Content & Screenshots

#### W1. Capture Demo Screenshots & Backup Videos [ ] — JM

Boot the lab and capture screenshots of every key moment. Save to a `docs/screenshots/` folder:

```bash
mkdir -p docs/screenshots
```

Capture (at minimum):
- Jokopi app homepage in browser
- Wazuh Dashboard login screen
- Wazuh Dashboard showing 0 alerts (before attack)
- Kali terminal running reconnaissance script
- Wazuh Dashboard showing SQL injection alerts appearing in real-time
- Wazuh Dashboard showing brute-force correlation alerts
- Firewall web UI showing blocked IPs
- Active response log showing automatic block

**Record a 2-3 min screen recording** of the attack→detection→block flow as a backup
in case the live demo has issues on Friday. Use QuickTime (Mac) or OBS.


#### W2. Write the Log Filtering Guide [ ] — JL

Create `docs/LOG_FILTERING_GUIDE.md` covering:

**Section 1: Log Sources in the Lab**
- Nginx access/error logs (high volume, mostly noise)
- PHP application logs (medium volume, useful for SQLi/XSS detection)
- Wazuh agent FIM alerts (low volume, high signal)
- Firewall iptables logs (medium volume, need filtering)
- Suricata IDS alerts (low volume, high signal)

**Section 2: Signal vs. Noise**
- Noise: health checks, normal page loads, static asset requests, Docker internal traffic
- Signal: unusual query strings, repeated failed logins, port scans, non-standard user agents

**Section 3: Filtering in Wazuh Dashboard**
- How to filter by rule.level (show only level 10+ for critical alerts)
- How to filter by rule.groups (web-attack, brute-force, dos)
- How to use the rule.id ranges (100100-100199 = web, 100200-100299 = network)
- Explain role IDs / agent IDs for troubleshooting

**Section 4: Thresholds That Matter**
- Brute force: 5 failed logins in 60 seconds triggers rule 100122
- DoS: SYN flood threshold, HTTP flood threshold
- Scanner detection: nikto/dirb/gobuster user-agent patterns
- Why these thresholds were chosen (balance between false positives and missed attacks)

**Section 5: From Logs → Detection Rules → Attacks**
Walk through one complete example: raw Nginx log line → decoder parses it → rule 100100
matches → alert fires → active response blocks IP. This is the "how do the logs relate
to the detection rules to the attacks" question from the professor.


#### W3. Fill in Presentation Slides [ ] — E

Using the screenshots from W1 and content from W2/T2:
- Replace placeholder text with real content
- Add screenshots to demo slides
- Build the architecture infographic (use draw.io, Canva, or PowerPoint SmartArt)
- Write speaker notes for each slide
- Add CrowdStrike-style attack analysis formatting (see their blog for inspiration:
  https://www.crowdstrike.com/blog/ — look at how they present attack timelines)

---

### THURSDAY — Polish, Practice, Final Commits

#### R1. Add Future Plans Section to README [ ] — E

Add before the Team Members section in README.md:

```markdown
## Future Plans

### Short-Term (Next Sprint)
- Re-enable full TLS authentication on OpenSearch indexer with proper cert paths
- Add CSRF token validation to the Jokopi web forms
- Implement password hashing (bcrypt) to replace plain-text storage
- Add rate limiting at the Nginx level as a defense-in-depth measure

### Medium-Term
- Integrate Elasticsearch SIEM correlation for cross-container threat hunting
- Add a WAF (ModSecurity) container between the firewall and Jokopi
- Create automated compliance reporting from Wazuh data
- Build a CI/CD pipeline that runs security scans on every push

### Long-Term Vision
- Expand to a multi-site coffee shop network (multiple Jokopi instances)
- Add cloud-hosted SIEM for centralized monitoring across locations
- Implement zero-trust network architecture with micro-segmentation
- Develop student lab modules that can be assigned as homework exercises
```


#### R2. Activate the GitHub Wiki [ ] — JM

1. Go to the repo on GitHub → Settings → Features → check "Wikis"
2. Create these wiki pages (can be brief — bullet points are fine):
   - **Home** — project overview, link to README
   - **Setup Guide** — condensed version of DEPLOYMENT_GUIDE.md
   - **Attack Playbook** — summary of the 5 attack phases
   - **Detection Rules Reference** — table of rule IDs, descriptions, and CVEs
   - **Troubleshooting** — common issues from README's troubleshooting section


#### R3. Practice the Presentation [ ] — ALL

- **Time yourselves.** Set a 20-minute timer and run through the full presentation.
- Assign sections:
  - Emily: Intro, problem statement, story, future plans, Q&A moderation
  - Jediah: Architecture walkthrough, live demo (or video backup), Docker explanation
  - Jeraldhin: Detection rules, CVE analysis, log filtering, CrowdStrike-style findings
- Practice transitions between speakers
- Practice the live demo flow: start Kali → run attack → switch to Wazuh Dashboard → show alerts → show blocked IP
- **Have a backup plan**: if live demo fails, switch to screenshots/video immediately
- Do at least 2 full run-throughs


#### R4. Final Commit & Repo Cleanup [ ] — JM

```bash
# Run the secret cleanup before pushing
bash scripts/setup/scrub-history.sh
bash scripts/setup/rotate-secrets.sh

# Stage and commit all new docs
git add -A
git commit -m "Add presentation materials, log guide, CVEs, future plans, wiki content"

# Force push (history was rewritten by scrub script)
git remote add origin https://github.com/je1805/cis3353_s26_eh_jm_jl.git
git push --force --set-upstream origin main
```

Tell Emily and Jeraldhin to **delete and re-clone** after the force push.

---

## Task Assignment Summary

| Task | Owner | Day | Est. Time | Priority |
|------|-------|-----|-----------|----------|
| T1. Re-enable authentication | Jediah | Tue | 1-2 hrs | HIGH |
| T2. Add CVE references | Jeraldhin | Tue | 1-2 hrs | HIGH |
| T3. Start presentation deck | Emily | Tue | 1-2 hrs | HIGH |
| W1. Capture screenshots & video | Jediah | Wed | 1 hr | HIGH |
| W2. Log filtering guide | Jeraldhin | Wed | 2 hrs | HIGH |
| W3. Fill in slides | Emily | Wed | 2-3 hrs | HIGH |
| R1. Future plans in README | Emily | Thu | 30 min | MEDIUM |
| R2. Activate GitHub wiki | Jediah | Thu | 1 hr | MEDIUM |
| R3. Practice presentation (x2) | ALL | Thu | 1-2 hrs | CRITICAL |
| R4. Final commit & cleanup | Jediah | Thu | 30 min | HIGH |

---

## Professor's Checklist — Final Cross-Reference

| Requirement | Status | Where |
|-------------|--------|-------|
| Commit work to GitHub | DONE | Repo is on GitHub, team can push |
| Don't share secrets | DONE | .env gitignored, scrub script ready |
| System architecture | DONE | README diagram + DEPLOYMENT_GUIDE |
| High-level component summary | DONE | README container table |
| Drilled-down functionality | DONE | README data flows + DEPLOYMENT_GUIDE |
| Practice narrating | DO Thu | R3 rehearsal |
| Identify pain-points | DO Wed | Add to slides (W3) |
| Dockerfile construction | DONE | 3 well-documented Dockerfiles |
| Multi-system deployment | DONE | docker-compose.yml with 6 services |
| Logins / user generation | DONE | SQLite seed data in jokopi Dockerfile |
| Library installs | DONE | All Dockerfiles document installs |
| Container connectivity | DONE | Static IPs on coffeeshop-net bridge |
| OAuth setup | N/A | Not applicable to this lab (note in slides) |
| .dockerignore | DONE | Root .dockerignore present |
| Expert system navigation | DO Thu | R3 rehearsal |
| Team instructions | DONE | README + DEPLOYMENT_GUIDE + lab-setup.sh |
| Log filtering concept | DO Wed | W2 guide |
| Signal vs. noise | DO Wed | W2 guide |
| Role IDs for troubleshooting | DO Wed | W2 guide |
| Important logs identification | DO Wed | W2 guide |
| Thresholds for actionable info | DO Wed | W2 guide |
| Logs → rules → attacks mapping | DO Wed | W2 guide |
| Re-enable authentication | DO Tue | T1 (or document the plan) |
| Repo reflects work done | DO Thu | R4 final commit |
| Future plans | DO Thu | R1 README section |
| Story / narrative | DONE | README + slides (W3) |
| Docker Compose guide (extra pts) | DONE | DEPLOYMENT_GUIDE.md |
| CVEs | DO Tue | T2 references |
| CrowdStrike-style analysis | DO Wed | W3 slides |
| Activate wiki | DO Thu | R2 |
| Presentation ≤20 min | DO Thu | R3 timed rehearsal |
| Screenshots / video backup | DO Wed | W1 captures |
| High-level slides, not wordy | DO Wed | W3 (visual-first design) |
| Infographics | DO Wed | W3 architecture diagram |
