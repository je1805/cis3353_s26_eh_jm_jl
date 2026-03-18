# cis3353_s26_eh_jm_jl
A local coffee shop is vulnerable to on-path attacks because their Guest Wi-Fi and PoS systems share a flat network. We will
replicate this using pfSense VLANs, demonstrate an ARP Spoofing attack, and then defend the shop by implementing Suricata IDS
for automated traffic monitoring and Wazuh for automated IP blocking. We will verify effectiveness by showing that the
network automatically 'severs' the attacker's connection the moment a scan is detected.
