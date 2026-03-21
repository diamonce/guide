#!/bin/bash
# Tests HAProxy write and read routing.
# Requires mysql client on host: brew install mysql-client

set -euo pipefail

WRITE_PORT=3306
READ_PORT=3307
USER="app"
PASS="apppass"
DB="shopdb"

echo "=== HAProxy write port $WRITE_PORT → should always be primary (server_id=1) ==="
for i in 1 2 3; do
    mysql -h 127.0.0.1 -P "$WRITE_PORT" -u"$USER" -p"$PASS" "$DB" \
        -e "SELECT @@server_id AS server_id, @@hostname AS host;" 2>/dev/null
done

echo ""
echo "=== HAProxy read port $READ_PORT → should round-robin replica1/replica2 ==="
for i in 1 2 3 4; do
    mysql -h 127.0.0.1 -P "$READ_PORT" -u"$USER" -p"$PASS" "$DB" \
        -e "SELECT @@server_id AS server_id, @@hostname AS host;" 2>/dev/null
done

echo ""
echo "=== HAProxy stats: http://localhost:8404/stats ==="
echo "    (open in browser)"
