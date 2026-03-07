#!/bin/bash
# PHOSPHOR Relay Server
# Usage: ./server.sh [PORT]
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${1:-8766}"
echo "Starting PHOSPHOR Relay on wss://0.0.0.0:$PORT"
fvm dart "$DIR/relay_server.dart" --cert "$DIR/public.pem" --key "$DIR/private.pem" --port "$PORT"
