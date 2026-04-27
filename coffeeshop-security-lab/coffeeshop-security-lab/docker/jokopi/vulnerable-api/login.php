<?php
// =============================================================================
// VULNERABLE LOGIN ENDPOINT - CIS 3353 Security Lab
// =============================================================================
// Vulnerabilities:
//   1. SQL Injection in username/password fields
//   2. No rate limiting (brute-force possible)
//   3. Plain-text password storage
//   4. Verbose error messages revealing database structure
//   5. No CSRF protection
//   6. No account lockout
// =============================================================================

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$db_path = '/var/www/data/coffeeshop.db';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $username = $input['username'] ?? $_POST['username'] ?? '';
    $password = $input['password'] ?? $_POST['password'] ?? '';

    // Log the login attempt (for Wazuh to monitor)
    error_log("LOGIN ATTEMPT: user=$username from=" . $_SERVER['REMOTE_ADDR']);
    $log_msg = date('Y-m-d H:i:s') . " LOGIN_ATTEMPT user=$username src=" . $_SERVER['REMOTE_ADDR'] . "\n";
    file_put_contents('/var/log/nginx/auth.log', $log_msg, FILE_APPEND);

    if (empty($username) || empty($password)) {
        http_response_code(400);
        echo json_encode([
            'error' => 'Missing credentials',
            'debug' => 'Both username and password fields are required',
            'db_path' => $db_path  // VULNERABILITY: Expose internal path
        ]);
        exit;
    }

    try {
        $db = new SQLite3($db_path);

        // VULNERABILITY: SQL Injection - Direct string concatenation
        // Attacker can use: admin' OR '1'='1' --
        $query = "SELECT * FROM users WHERE username='$username' AND password='$password'";

        // VULNERABILITY: Expose the query in debug mode
        error_log("SQL QUERY: $query");

        $result = $db->query($query);

        if ($row = $result->fetchArray(SQLITE3_ASSOC)) {
            // Successful login
            $log_success = date('Y-m-d H:i:s') . " LOGIN_SUCCESS user=$username src=" . $_SERVER['REMOTE_ADDR'] . "\n";
            file_put_contents('/var/log/nginx/auth.log', $log_success, FILE_APPEND);

            echo json_encode([
                'success' => true,
                'message' => 'Login successful',
                'user' => [
                    'id' => $row['id'],
                    'username' => $row['username'],
                    'email' => $row['email'],
                    'role' => $row['role']
                ],
                // VULNERABILITY: Expose session token in response
                'token' => base64_encode($row['username'] . ':' . $row['role'] . ':' . time())
            ]);
        } else {
            // Failed login
            $log_fail = date('Y-m-d H:i:s') . " LOGIN_FAILED user=$username src=" . $_SERVER['REMOTE_ADDR'] . "\n";
            file_put_contents('/var/log/nginx/auth.log', $log_fail, FILE_APPEND);

            http_response_code(401);
            echo json_encode([
                'success' => false,
                'error' => 'Invalid credentials',
                // VULNERABILITY: Reveal whether username exists
                'debug' => "No matching record for query: $query"
            ]);
        }

        $db->close();
    } catch (Exception $e) {
        http_response_code(500);
        // VULNERABILITY: Expose full error details
        echo json_encode([
            'error' => 'Database error',
            'message' => $e->getMessage(),
            'trace' => $e->getTraceAsString(),
            'query' => $query ?? 'N/A'
        ]);
    }
} else {
    echo json_encode([
        'endpoint' => '/api/login.php',
        'method' => 'POST',
        'params' => ['username', 'password'],
        'version' => 'Jokopi API v1.0-dev'  // VULNERABILITY: Version exposure
    ]);
}
?>
