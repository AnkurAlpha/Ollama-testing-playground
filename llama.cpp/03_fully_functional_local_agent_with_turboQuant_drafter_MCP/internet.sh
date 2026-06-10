#!/bin/env bash
set -Eeuo pipefail

# for starting cleanly
pkill -u "$USER" -f supergateway 2>/dev/null || true
pkill -u "$USER" -f duckduckgo-mcp-server 2>/dev/null || true
pkill -u "$USER" -f '@playwright/mcp' 2>/dev/null || true
sleep 1

# Everything temporary/recreated will live here
RUNTIME_DIR="${TMPDIR:-/tmp}/ankur-mcp-runtime"
LOG_DIR="$RUNTIME_DIR/logs"
DATA_DIR="$RUNTIME_DIR/data"
PLAYWRIGHT_PROFILE_DIR="$RUNTIME_DIR/playwright-profile"

# llama-ui origin
LLAMA_UI_ORIGIN="http://localhost:8080"

# Clean old runtime folder every time this script starts
if [ -d "$RUNTIME_DIR" ]; then
    echo "Cleaning old MCP runtime directory: $RUNTIME_DIR"

    # Stop old processes from previous run if pid files exist
    for pidfile in "$RUNTIME_DIR"/logs/*.pid; do
        [ -e "$pidfile" ] || continue
        pid="$(cat "$pidfile")"
        kill "$pid" 2>/dev/null || true
    done

    rm -rf "$RUNTIME_DIR"
fi

mkdir -p "$LOG_DIR" "$DATA_DIR" "$PLAYWRIGHT_PROFILE_DIR"

# Create temporary SQLite test DB
sqlite3 "$DATA_DIR/test.db" 'CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, text TEXT);' >/dev/null 2>&1 || true

run() {
    local name="$1"
    shift

    echo "Starting $name ..."
    "$@" > "$LOG_DIR/$name.log" 2>&1 &
    echo "$!" > "$LOG_DIR/$name.pid"
}

cleanup() {
    echo
    echo "Stopping MCP servers..."
    for pidfile in "$LOG_DIR"/*.pid; do
        [ -e "$pidfile" ] || continue
        pid="$(cat "$pidfile")"
        kill "$pid" 2>/dev/null || true
        rm -f "$pidfile"
    done
}

trap cleanup INT TERM EXIT

# 8000: DuckDuckGo internet MCP
run duckduckgo \
    uvx duckduckgo-mcp-server \
        --transport streamable-http \
        --host 127.0.0.1 \
        --port 8000

# 8003: Sequential Thinking MCP
run sequential-thinking \
    npx -y supergateway \
        --stdio "npx -y @modelcontextprotocol/server-sequential-thinking" \
        --outputTransport streamableHttp \
        --port 8003 \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

# 8004: Fetch MCP
run fetch \
    npx -y supergateway \
        --stdio "uvx mcp-server-fetch" \
        --outputTransport streamableHttp \
        --port 8004 \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

# 8005: Time MCP
run time \
    npx -y supergateway \
        --stdio "uvx mcp-server-time --local-timezone=Asia/Kolkata" \
        --outputTransport streamableHttp \
        --port 8005 \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

# 8006: SQLite MCP
# DB is temporary and recreated every run at /tmp/ankur-mcp-runtime/data/test.db
run sqlite \
    npx -y supergateway \
        --stdio "uvx mcp-server-sqlite --db-path $DATA_DIR/test.db" \
        --outputTransport streamableHttp \
        --port 8006 \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

# 8007: Context7 MCP
run context7 \
    npx -y supergateway \
        --stdio "npx -y @upstash/context7-mcp" \
        --outputTransport streamableHttp \
        --port 8007 \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

# 8931: Playwright MCP
# Wrapped through supergateway. Browser profile is temporary/recreated every run.
run playwright \
    npx -y supergateway \
        --stdio "npx -y @playwright/mcp@latest --user-data-dir $PLAYWRIGHT_PROFILE_DIR" \
        --outputTransport streamableHttp \
        --port 8931 \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

echo
echo "MCP servers started:"
echo "duckduckgo           http://127.0.0.1:8000/mcp"
echo "sequential-thinking  http://127.0.0.1:8003/mcp"
echo "fetch                http://127.0.0.1:8004/mcp"
echo "time                 http://127.0.0.1:8005/mcp"
echo "sqlite               http://127.0.0.1:8006/mcp"
echo "context7             http://127.0.0.1:8007/mcp"
echo "playwright           http://127.0.0.1:8931/mcp"
echo
echo "Temporary runtime directory:"
echo "$RUNTIME_DIR"
echo
echo "Logs:"
echo "$LOG_DIR"
echo
echo "SQLite temp DB:"
echo "$DATA_DIR/test.db"
echo
echo "Playwright temp profile:"
echo "$PLAYWRIGHT_PROFILE_DIR"
echo
echo "Press Ctrl+C to stop all."

wait
