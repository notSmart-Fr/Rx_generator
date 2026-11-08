#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="$DIR/rx_generator"

if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$DIR/../bin/rx_generator"
fi

PID_FILE="/tmp/rx_generator_desktop.pid"

cleanup() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
}

trap cleanup EXIT INT TERM

# Start release daemon in background
"$BIN_PATH" start &
BEAM_PID=$!
echo "$BEAM_PID" > "$PID_FILE"

# Wait for [RX_PORT:<port>]
PORT=4000
for i in {1..20}; do
    if [ -f "/tmp/rx_generator_port" ]; then
        PORT=$(cat "/tmp/rx_generator_port")
        break
    fi
    sleep 0.2
done

URL="http://127.0.0.1:${PORT}/"

# Launch available webview or browser window
if command -v zenity >/dev/null 2>&1; then
    zenity --info --text="RxGenerator running at $URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL"
fi

wait "$BEAM_PID"

