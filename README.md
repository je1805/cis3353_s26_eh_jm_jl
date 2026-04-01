# cis3353_s26_eh_jm_jl
A small coffee shop (Jokopi) runs a customer-facing React web application for online orders and menu
browsing. The shop is vulnerable to web application attacks (SQL injection, XSS, brute-force login) and
network-level threats (port scanning, denial-of-service attempts). We will replicate this environment using
Docker containers, demonstrate how these attacks impact the unprotected application, and then defend it by
deploying Wazuh as a SIEM for real-time monitoring and alerting, and pfSense as a network firewall to enforce
traffic filtering and automated defense actions triggered by Wazuh intelligence. We will verify effectiveness by
confirming that attacks are detected within 60 seconds, alerts are generated in the Wazuh dashboard, and
pfSense blocks malicious traffic based on Wazuh-triggered rules.
