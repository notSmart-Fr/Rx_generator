#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_PATH="$DIR/rx_generator"

if [ ! -f "$BIN_PATH" ]; then
    BIN_PATH="$DIR/../bin/rx_generator"
fi

LOCK_FILE="/tmp/rx_generator.lock"
PID_FILE="/tmp/rx_generator_desktop.pid"
STDOUT_LOG="/tmp/rx_generator_stdout_$$.log"

focus_existing_window() {
    if command -v wmctrl >/dev/null 2>&1; then
        wmctrl -a "RxGenerator" 2>/dev/null || true
    elif command -v xdotool >/dev/null 2>&1; then
        xdotool search --name "RxGenerator" windowactivate 2>/dev/null || true
    fi
}

# Single-instance enforcement using /tmp/rx_generator.lock
if command -v flock >/dev/null 2>&1; then
    exec 9>"$LOCK_FILE"
    if ! flock -n 9; then
        focus_existing_window
        exit 0
    fi
    echo "$$" >&9
else
    if [ -f "$LOCK_FILE" ]; then
        EXISTING_PID=$(cat "$LOCK_FILE" 2>/dev/null || true)
        if [ -n "$EXISTING_PID" ] && kill -0 "$EXISTING_PID" 2>/dev/null; then
            focus_existing_window
            exit 0
        fi
    fi
    echo "$$" > "$LOCK_FILE"
fi

cleanup() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE" 2>/dev/null || true)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            kill "$PID" 2>/dev/null || true
        fi
        rm -f "$PID_FILE"
    fi
    rm -f "$STDOUT_LOG" "$LOCK_FILE"
}

trap cleanup EXIT INT TERM

# Start release in background capturing stdout/stderr for IPC port detection
: > "$STDOUT_LOG"
"$BIN_PATH" start > "$STDOUT_LOG" 2>&1 &
BEAM_PID=$!
echo "$BEAM_PID" > "$PID_FILE"

# Poll child stdout up to 10 seconds (50 x 0.2s) for [RX_PORT:<port>]
PORT=""
for _i in $(seq 1 50); do
    if [ -f "$STDOUT_LOG" ]; then
        MATCH=$(grep -oE '\[RX_PORT:[0-9]+\]' "$STDOUT_LOG" | head -n 1 || true)
        if [ -n "$MATCH" ]; then
            PORT=$(echo "$MATCH" | sed -E 's/\[RX_PORT:([0-9]+)\]/\1/')
            break
        fi
    fi

    if ! kill -0 "$BEAM_PID" 2>/dev/null; then
        break
    fi

    sleep 0.2
done

if [ -z "$PORT" ]; then
    DIAGNOSTICS=$(tail -n 20 "$STDOUT_LOG" 2>/dev/null || true)
    ERR_MSG="RxGenerator failed to bind local loopback port within 10 seconds.\n\nRecent runtime output:\n${DIAGNOSTICS}"
    if command -v zenity >/dev/null 2>&1; then
        zenity --error --title="RxGenerator - Startup Error" --text="$ERR_MSG" 2>/dev/null || true
    fi
    printf "%b\n" "$ERR_MSG" >&2
    exit 1
fi

URL="http://127.0.0.1:${PORT}/"

# Launch available webview or desktop browser window
if command -v zenity >/dev/null 2>&1; then
    zenity --info --text="RxGenerator running at $URL" 2>/dev/null || true
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL"
fi

wait "$BEAM_PID"
