<?php
// =============================================================================
// VULNERABLE SERVER INFO ENDPOINT - CIS 3353 Security Lab
// VULNERABILITY: Exposes full PHP configuration and server details
// =============================================================================

// This endpoint should NEVER exist in production
// It exposes: PHP version, loaded modules, server paths, environment variables

phpinfo();
?>
