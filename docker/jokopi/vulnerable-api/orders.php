<?php
// =============================================================================
// VULNERABLE ORDERS ENDPOINT - CIS 3353 Security Lab
// =============================================================================
// Vulnerabilities:
//   1. SQL Injection in order lookup
//   2. No authentication required to view orders
//   3. Exposes sensitive card data
//   4. IDOR (Insecure Direct Object Reference)
// =============================================================================

header('Content-Type: application/json');
header('Access-Control-Allow-Origin: *');

$db_path = '/var/www/data/coffeeshop.db';

error_log("ORDER REQUEST: method=" . $_SERVER['REQUEST_METHOD'] . " from=" . $_SERVER['REMOTE_ADDR']);

try {
    $db = new SQLite3($db_path);

    if ($_SERVER['REQUEST_METHOD'] === 'GET') {
        $id = $_GET['id'] ?? '';

        if (!empty($id)) {
            // VULNERABILITY: SQL Injection + IDOR
            $query = "SELECT * FROM orders WHERE id=$id";
            $result = $db->query($query);
            $order = $result->fetchArray(SQLITE3_ASSOC);

            if ($order) {
                // VULNERABILITY: Exposes card numbers without masking
                echo json_encode(['success' => true, 'order' => $order]);
            } else {
                http_response_code(404);
                echo json_encode(['error' => "Order $id not found", 'sql' => $query]);
            }
        } else {
            // VULNERABILITY: No auth needed to list all orders
            $result = $db->query("SELECT * FROM orders ORDER BY created_at DESC");
            $orders = [];
            while ($row = $result->fetchArray(SQLITE3_ASSOC)) {
                $orders[] = $row;
            }
            echo json_encode(['success' => true, 'count' => count($orders), 'orders' => $orders]);
        }
    } elseif ($_SERVER['REQUEST_METHOD'] === 'POST') {
        $input = json_decode(file_get_contents('php://input'), true);
        $name = $input['customer_name'] ?? '';
        $item = $input['item'] ?? '';
        $qty = $input['quantity'] ?? 1;
        $total = $input['total'] ?? 0;
        $card = $input['card_number'] ?? '';

        // VULNERABILITY: No input validation, stores card in plain text
        $query = "INSERT INTO orders (customer_name, item, quantity, total, card_number) "
               . "VALUES ('$name', '$item', $qty, $total, '$card')";
        $db->exec($query);

        echo json_encode([
            'success' => true,
            'message' => 'Order placed',
            'order_id' => $db->lastInsertRowID()
        ]);
    }

    $db->close();
} catch (Exception $e) {
    http_response_code(500);
    echo json_encode(['error' => $e->getMessage(), 'trace' => $e->getTraceAsString()]);
}
?>
