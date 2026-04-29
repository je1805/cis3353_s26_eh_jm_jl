<?php
// =============================================================================
// Firewall Management Web UI - CIS 3353 Security Lab
// Provides a pfSense-style web interface for the Docker firewall
// =============================================================================
$action = $_POST['action'] ?? $_GET['action'] ?? '';
$message = '';

if ($action === 'block' && !empty($_POST['ip'])) {
    $ip = escapeshellarg($_POST['ip']);
    $dur = intval($_POST['duration'] ?? 3600);
    exec("/opt/active-response/handler.sh block $ip $dur 2>&1", $out);
    $message = implode("\n", $out);
} elseif ($action === 'unblock' && !empty($_POST['ip'])) {
    $ip = escapeshellarg($_POST['ip']);
    exec("/opt/active-response/handler.sh unblock $ip 2>&1", $out);
    $message = implode("\n", $out);
} elseif ($action === 'flush') {
    exec("/opt/active-response/handler.sh flush 2>&1", $out);
    $message = implode("\n", $out);
}

// Get current state
exec("iptables -L FORWARD -n -v --line-numbers 2>&1", $fw_rules);
exec("iptables -L INPUT -n -v --line-numbers 2>&1", $in_rules);
exec("cat /var/log/firewall/blocklist.txt 2>/dev/null", $blocklist);
exec("cat /var/log/firewall/active-response.log 2>/dev/null | tail -20", $ar_log);
exec("conntrack -C 2>/dev/null || echo 'N/A'", $conn_count);
?>
<!DOCTYPE html>
<html>
<head>
    <title>pfSense Firewall - CIS 3353 Lab</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Segoe UI', Arial, sans-serif; background: #1a1a2e; color: #e0e0e0; }
        .header { background: #16213e; padding: 15px 30px; border-bottom: 3px solid #e94560; }
        .header h1 { color: #e94560; font-size: 1.4em; }
        .header span { color: #888; font-size: 0.85em; }
        .container { max-width: 1200px; margin: 20px auto; padding: 0 20px; }
        .card { background: #16213e; border-radius: 8px; padding: 20px; margin-bottom: 20px; border: 1px solid #2a2a4a; }
        .card h2 { color: #e94560; margin-bottom: 15px; font-size: 1.1em; border-bottom: 1px solid #2a2a4a; padding-bottom: 8px; }
        .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
        pre { background: #0f0f23; padding: 12px; border-radius: 5px; overflow-x: auto; font-size: 0.8em; color: #76ff03; max-height: 300px; overflow-y: auto; }
        input, select, button { padding: 8px 14px; border-radius: 4px; border: 1px solid #2a2a4a; background: #0f0f23; color: #e0e0e0; }
        button { background: #e94560; border: none; cursor: pointer; font-weight: bold; }
        button:hover { background: #c73650; }
        button.unblock { background: #2ecc71; }
        button.flush { background: #e67e22; }
        .alert { background: #2ecc71; color: #000; padding: 10px; border-radius: 5px; margin-bottom: 15px; }
        .stat-box { display: inline-block; background: #0f0f23; padding: 10px 20px; border-radius: 5px; margin: 5px; text-align: center; }
        .stat-box .num { font-size: 1.8em; color: #e94560; }
        .stat-box .label { font-size: 0.75em; color: #888; }
        form { display: flex; gap: 10px; align-items: center; flex-wrap: wrap; }
    </style>
    <meta http-equiv="refresh" content="30">
</head>
<body>
    <div class="header">
        <h1>pfSense Firewall Dashboard</h1>
        <span>CIS 3353 Coffee Shop Security Lab | <?= date('Y-m-d H:i:s') ?></span>
    </div>
    <div class="container">
        <?php if ($message): ?>
            <div class="alert"><?= htmlspecialchars($message) ?></div>
        <?php endif; ?>

        <div class="card">
            <h2>Quick Actions</h2>
            <form method="POST">
                <input type="hidden" name="action" value="block">
                <input type="text" name="ip" placeholder="IP Address (e.g. 10.10.0.100)" required>
                <select name="duration">
                    <option value="300">5 minutes</option>
                    <option value="3600" selected>1 hour</option>
                    <option value="86400">24 hours</option>
                    <option value="0">Permanent</option>
                </select>
                <button type="submit">Block IP</button>
            </form>
            <br>
            <form method="POST" style="display:inline">
                <input type="hidden" name="action" value="unblock">
                <input type="text" name="ip" placeholder="IP to unblock">
                <button type="submit" class="unblock">Unblock IP</button>
            </form>
            <form method="POST" style="display:inline; margin-left:10px;">
                <input type="hidden" name="action" value="flush">
                <button type="submit" class="flush">Flush All Blocks</button>
            </form>
        </div>

        <div class="card">
            <h2>Blocked IPs (Active Response)</h2>
            <pre><?= !empty($blocklist) ? htmlspecialchars(implode("\n", $blocklist)) : "No IPs currently blocked." ?></pre>
        </div>

        <div class="grid">
            <div class="card">
                <h2>FORWARD Chain Rules</h2>
                <pre><?= htmlspecialchars(implode("\n", $fw_rules)) ?></pre>
            </div>
            <div class="card">
                <h2>INPUT Chain Rules</h2>
                <pre><?= htmlspecialchars(implode("\n", $in_rules)) ?></pre>
            </div>
        </div>

        <div class="card">
            <h2>Active Response Log (Last 20 Entries)</h2>
            <pre><?= !empty($ar_log) ? htmlspecialchars(implode("\n", $ar_log)) : "No active response events yet." ?></pre>
        </div>
    </div>
</body>
</html>
