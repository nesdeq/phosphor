#!/bin/bash
# PHOSPHOR Relay Server Setup
# Generates TLS certificates and prepares the client + server for multiplayer.
#
# Usage:
#   ./server_setup.sh <SERVER_IP> [PORT]
#
# Example:
#   ./server_setup.sh 203.0.113.10
#   ./server_setup.sh 203.0.113.10 9000

set -e

if [ -z "$1" ]; then
  echo "Usage: $0 <SERVER_IP> [PORT]"
  echo ""
  echo "  SERVER_IP   Your server's public IP address"
  echo "  PORT        Relay port (default: 8766)"
  exit 1
fi

SERVER_IP="$1"
PORT="${2:-8766}"
DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_DIR="$DIR/server"
CERT_DIR="$DIR/assets/certs"

echo "=== PHOSPHOR Relay Setup ==="
echo ""
echo "Server IP:  $SERVER_IP"
echo "Port:       $PORT"
echo ""

# Generate self-signed TLS certificate
echo "[1/4] Generating TLS certificate..."
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
  -keyout "$SERVER_DIR/private.pem" -out "$SERVER_DIR/public.pem" \
  -days 365 -nodes \
  -subj "/CN=phosphor-relay" \
  -addext "subjectAltName=IP:$SERVER_IP,IP:127.0.0.1" \
  2>/dev/null

echo "  -> server/private.pem (keep secret, do NOT commit)"
echo "  -> server/public.pem"

# Copy public cert to client assets for certificate pinning
echo ""
echo "[2/4] Pinning certificate in client..."
mkdir -p "$CERT_DIR"
cp "$SERVER_DIR/public.pem" "$CERT_DIR/public.pem"
echo "  -> assets/certs/public.pem"

# Create portable server zip
echo ""
echo "[3/4] Packaging relay server..."
ZIP_DIR=$(mktemp -d)
RELAY_DIR="$ZIP_DIR/phosphor-relay"
mkdir -p "$RELAY_DIR"
cp "$SERVER_DIR/relay_server.dart" "$RELAY_DIR/"
cp "$SERVER_DIR/public.pem" "$RELAY_DIR/"
cp "$SERVER_DIR/private.pem" "$RELAY_DIR/"
cat > "$RELAY_DIR/server.sh" << 'SCRIPT'
#!/bin/bash
# PHOSPHOR Relay Server
# Usage: ./server.sh [PORT]
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-8766}"
echo "Starting PHOSPHOR Relay on wss://0.0.0.0:$PORT"
dart run "$DIR/relay_server.dart" --cert "$DIR/public.pem" --key "$DIR/private.pem" --port "$PORT"
SCRIPT
chmod +x "$RELAY_DIR/server.sh"
(cd "$ZIP_DIR" && zip -rq "$DIR/phosphor-relay.zip" phosphor-relay/)
rm -rf "$ZIP_DIR"
echo "  -> phosphor-relay.zip (copy to your server)"

# Done
echo ""
echo "[4/4] Done!"
echo ""
echo "=== Next Steps ==="
echo ""
echo "  1. Copy phosphor-relay.zip to your server and unzip it."
echo "     The server only needs Dart installed — no Flutter, no dependencies."
echo ""
echo "     scp phosphor-relay.zip user@$SERVER_IP:~/"
echo "     ssh user@$SERVER_IP 'unzip phosphor-relay.zip && cd phosphor-relay && ./server.sh $PORT'"
echo ""
echo "  2. Rebuild the client with the pinned cert:"
echo "     flutter build macos    # or: flutter build linux"
echo ""
echo "  3. Distribute the built app. It will only connect to this server."
echo "     Users enter wss://$SERVER_IP:$PORT in Settings > Relay Server."
echo ""
echo "  4. To regenerate certs (e.g. new server), re-run this script"
echo "     and rebuild the client."
echo ""
