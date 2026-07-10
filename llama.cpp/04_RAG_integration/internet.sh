#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   ./internet.sh
#   ./internet.sh gemma4-26b-a4b-it-qat-q4_0
#   MCP_MEMORY_MODEL_NAME=gemma4-26b-a4b-it-qat-q4_0 ./internet.sh
#
# Persistent Docker volume name:
#   chroma-memory-volume-<model_name>
#
# Example:
#   chroma-memory-volume-gemma4-26b-a4b-it-qat-q4_0

MODEL_NAME="${MCP_MEMORY_MODEL_NAME:-${1:-gemma4-26b-a4b-it-qat-q4_0}}"

SAFE_MODEL_NAME="$(
    printf '%s' "$MODEL_NAME" |
    tr '[:upper:]' '[:lower:]' |
    sed -E 's/[^a-z0-9_.-]+/-/g; s/^-+//; s/-+$//'
)"

if [ -z "$SAFE_MODEL_NAME" ]; then
    echo "ERROR: model name became empty after sanitization."
    exit 1
fi

CHROMA_IMAGE="${CHROMA_IMAGE:-chromadb/chroma:1.5.3}"
CHROMA_VOLUME="chroma-memory-volume-${SAFE_MODEL_NAME}"
CHROMA_CONTAINER="chroma-memory-${SAFE_MODEL_NAME}"
CHROMA_DB_PORT="${CHROMA_DB_PORT:-8010}"
CHROMA_MCP_PORT="${CHROMA_MCP_PORT:-8011}"
CHROMA_MCP_DIR="${CHROMA_MCP_DIR:-$HOME/mcp-servers/chroma-memory}"

# Stop old MCP servers from previous runs.
pkill -u "$USER" -f supergateway 2>/dev/null || true
pkill -u "$USER" -f duckduckgo-mcp-server 2>/dev/null || true
pkill -u "$USER" -f '@playwright/mcp' 2>/dev/null || true
sleep 1

RUNTIME_DIR="${TMPDIR:-/tmp}/ankur-mcp-runtime"
LOG_DIR="$RUNTIME_DIR/logs"
DATA_DIR="$RUNTIME_DIR/data"
PLAYWRIGHT_PROFILE_DIR="$RUNTIME_DIR/playwright-profile"

LLAMA_UI_ORIGIN="${LLAMA_UI_ORIGIN:-http://localhost:8080}"

if [ -d "$RUNTIME_DIR" ]; then
    echo "Cleaning old MCP runtime directory: $RUNTIME_DIR"

    for pidfile in "$RUNTIME_DIR"/logs/*.pid; do
        [ -e "$pidfile" ] || continue
        pid="$(cat "$pidfile")"
        kill "$pid" 2>/dev/null || true
    done

    rm -rf "$RUNTIME_DIR"
fi

mkdir -p "$LOG_DIR" "$DATA_DIR" "$PLAYWRIGHT_PROFILE_DIR"

sqlite3 "$DATA_DIR/test.db" 'CREATE TABLE IF NOT EXISTS notes(id INTEGER PRIMARY KEY, text TEXT);' >/dev/null 2>&1 || true

run() {
    local name="$1"
    shift

    echo "Starting $name ..."
    "$@" > "$LOG_DIR/$name.log" 2>&1 &
    echo "$!" > "$LOG_DIR/$name.pid"
}

port_in_use() {
    local port="$1"

    if command -v ss >/dev/null 2>&1; then
        ss -ltn "sport = :$port" | grep -q LISTEN
    else
        return 1
    fi
}

start_chroma() {
    if ! command -v docker >/dev/null 2>&1; then
        echo "ERROR: docker is not installed. Run ./mcp_setup.sh first."
        exit 1
    fi

    if ! docker ps >/dev/null 2>&1; then
        echo "ERROR: docker is not accessible for this user."
        echo "Try: newgrp docker"
        exit 1
    fi

    if [ ! -f "$CHROMA_MCP_DIR/server.py" ]; then
        echo "ERROR: Chroma MCP server not found:"
        echo "  $CHROMA_MCP_DIR/server.py"
        echo
        echo "Run ./mcp_setup.sh first, or create the Chroma MCP server."
        exit 1
    fi

    echo
    echo "Starting Chroma memory DB..."
    echo "Model name:      $MODEL_NAME"
    echo "Safe model name: $SAFE_MODEL_NAME"
    echo "Docker image:    $CHROMA_IMAGE"
    echo "Docker volume:   $CHROMA_VOLUME"
    echo "Container name:  $CHROMA_CONTAINER"
    echo "DB port:         $CHROMA_DB_PORT"
    echo "MCP port:        $CHROMA_MCP_PORT"

    docker volume create "$CHROMA_VOLUME" >/dev/null

    # Remove same-model old container if a previous script crashed.
    docker rm -f "$CHROMA_CONTAINER" >/dev/null 2>&1 || true

    # Remove old manually-created Chroma container from earlier experiments.
    # This does NOT delete named volumes.
    docker rm -f chroma-memory >/dev/null 2>&1 || true

    if port_in_use "$CHROMA_DB_PORT"; then
        echo
        echo "ERROR: Port $CHROMA_DB_PORT is already in use."
        echo "Details:"
        ss -ltnp "sport = :$CHROMA_DB_PORT" || true
        echo
        echo "Most likely an old Chroma container is still running."
        echo "Check with:"
        echo "  docker ps --format 'table {{.ID}}\t{{.Names}}\t{{.Ports}}' | grep $CHROMA_DB_PORT"
        echo
        echo "Then stop only that Chroma container."
        exit 1
    fi

    if ! docker image inspect "$CHROMA_IMAGE" >/dev/null 2>&1; then
        echo "Pulling Chroma image: $CHROMA_IMAGE"
        docker pull "$CHROMA_IMAGE"
    fi

    docker run -d \
        --rm \
        --name "$CHROMA_CONTAINER" \
        -p "127.0.0.1:${CHROMA_DB_PORT}:8000" \
        -v "${CHROMA_VOLUME}:/data" \
        "$CHROMA_IMAGE" >/dev/null

    echo "Waiting for Chroma heartbeat..."
    for _ in {1..90}; do
        if curl -fsS "http://127.0.0.1:${CHROMA_DB_PORT}/api/v2/heartbeat" >/dev/null 2>&1; then
            echo "Chroma is ready."
            return 0
        fi
        sleep 1
    done

    echo
    echo "ERROR: Chroma did not become ready."
    echo "Container logs:"
    docker logs "$CHROMA_CONTAINER" || true
    exit 1
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

    echo "Stopping Chroma container, keeping persistent Docker volume safe..."
    docker stop "$CHROMA_CONTAINER" >/dev/null 2>&1 || true

    echo
    echo "Persistent Chroma volume kept:"
    echo "  $CHROMA_VOLUME"
}

trap cleanup INT TERM EXIT

start_chroma

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

# 8011: Chroma Memory MCP
run chroma-memory \
    npx -y supergateway \
        --stdio "env CHROMA_HOST=127.0.0.1 CHROMA_PORT=${CHROMA_DB_PORT} CHROMA_COLLECTION=agent_memory uv run --project ${CHROMA_MCP_DIR} python ${CHROMA_MCP_DIR}/server.py" \
        --outputTransport streamableHttp \
        --port "$CHROMA_MCP_PORT" \
        --streamableHttpPath /mcp \
        --cors "$LLAMA_UI_ORIGIN"

# 8931: Playwright MCP
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
echo "chroma-memory        http://127.0.0.1:${CHROMA_MCP_PORT}/mcp"
echo "playwright           http://127.0.0.1:8931/mcp"
echo
echo "Chroma DB:"
echo "http://127.0.0.1:${CHROMA_DB_PORT}"
echo
echo "Chroma persistent Docker volume:"
echo "$CHROMA_VOLUME"
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
echo "Press Ctrl+C to stop all MCP servers and the Chroma container."
echo "The Chroma Docker volume will NOT be deleted."

wait
