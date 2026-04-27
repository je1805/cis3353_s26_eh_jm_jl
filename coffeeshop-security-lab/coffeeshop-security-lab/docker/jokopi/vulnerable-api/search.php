<?php
// =============================================================================
// VULNERABLE SEARCH ENDPOINT - CIS 3353 Security Lab
// =============================================================================
// Vulnerabilities:
//   1. SQL Injection via search parameter
//   2. Reflected XSS via search term in response
//   3. No input sanitization
//   4. Verbose error messages
// =============================================================================

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$db_path = '/var/www/data/coffeeshop.db';
$search = $_GET['q'] ?? $_POST['q'] ?? '';

error_log("SEARCH REQUEST: q=$search from=" . $_SERVER['REMOTE_ADDR']);

if (empty($search)) {
    echo json_encode([
        'endpoint' => '/api/search.php',
        'usage' => '?q=<search_term>',
        'description' => 'Search menu items by name or description'
    ]);
    exit;
}

try {
    $db = new SQLite3($db_path);

    // VULNERABILITY: SQL Injection - user input directly in query
    // Attacker can use: ' UNION SELECT * FROM users --
    $query = "SELECT * FROM menu WHERE name LIKE '%$search%' OR description LIKE '%$search%'";
    error_log("SQL QUERY: $query");

    $result = $db->query($query);
    $items = [];

    while ($row = $result->fetchArray(SQLITE3_ASSOC)) {
        $items[] = $row;
    }

    echo json_encode([
        'success' => true,
        // VULNERABILITY: Reflected XSS - search term echoed without encoding
        'query' => $search,
        'html_preview' => "<p>Results for: <b>$search</b></p>",  // XSS vector
        'count' => count($items),
        'results' => $items,
        'debug' => [
            'sql' => $query,  // VULNERABILITY: Expose SQL query
            'execution_time' => microtime(true)
        ]
    ]);

    $db->close();
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode([
        'error' => $e->getMessage(),
        'query' => $query ?? 'N/A',
        'trace' => $e->getTraceAsString()
    ]);
}
?>
