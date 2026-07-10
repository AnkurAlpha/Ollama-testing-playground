#!/usr/bin/env bash
set -Eeuo pipefail

CHROMA_IMAGE="${CHROMA_IMAGE:-chromadb/chroma:1.5.3}"
CHROMA_MCP_DIR="${CHROMA_MCP_DIR:-$HOME/mcp-servers/chroma-memory}"

install_system_packages() {
echo
echo "==> Installing system packages"

if command -v pacman >/dev/null 2>&1; then
sudo pacman -S --needed nodejs npm git curl sqlite python python-pip docker docker-compose
elif command -v apt >/dev/null 2>&1; then
sudo apt update
sudo apt install -y nodejs npm git curl sqlite3 python3 python3-pip docker.io docker-compose-plugin
elif command -v dnf >/dev/null 2>&1; then
sudo dnf install -y nodejs npm git curl sqlite python3 python3-pip docker docker-compose
elif command -v zypper >/dev/null 2>&1; then
sudo zypper install -y nodejs npm git curl sqlite3 python3 python3-pip docker docker-compose
else
echo "ERROR: Unsupported package manager."
echo "Please install manually: nodejs npm git curl sqlite3 python3 python-pip docker"
exit 1
fi
}

install_uv() {
echo
echo "==> Ensuring uv/uvx are installed"

if command -v uv >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1; then
echo "uv and uvx already installed."
return 0
fi

curl -LsSf https://astral.sh/uv/install.sh | sh
export PATH="$HOME/.local/bin:$PATH"
}

check_commands() {
echo
echo "==> Checking required commands"

local missing=0

for cmd in node npm npx git curl sqlite3 python3 uv uvx docker; do
if ! command -v "$cmd" >/dev/null 2>&1; then
echo "Missing command: $cmd"
missing=1
else
echo "OK: $cmd -> $(command -v "$cmd")"
fi
done

if [ "$missing" -ne 0 ]; then
echo
echo "ERROR: Some commands are missing."
exit 1
fi
}

ensure_docker_running() {
echo
echo "==> Ensuring Docker is running"

if ! command -v docker >/dev/null 2>&1; then
echo "ERROR: Docker is not installed."
exit 1
fi

sudo systemctl enable --now docker

if ! docker ps >/dev/null 2>&1; then
echo
echo "Docker is installed, but your current user cannot access it without sudo."
echo "Adding $USER to docker group..."
sudo usermod -aG docker "$USER"
echo
echo "IMPORTANT:"
echo "  Run this now:"
echo "    newgrp docker"
echo
echo "Then rerun:"
echo "    ./mcp_setup.sh"
echo
exit 1
fi

echo "Docker is ready."
}

setup_chroma_memory_mcp() {
echo
echo "==> Setting up Chroma memory MCP server"

mkdir -p "$CHROMA_MCP_DIR"
cd "$CHROMA_MCP_DIR"

uv init --bare >/dev/null 2>&1 || true
uv add "mcp[cli]>=1,<2" chromadb

cat > server.py <<'PY'
import os
import time
import uuid
from typing import Optional

import chromadb
from chromadb.utils import embedding_functions
from mcp.server.fastmcp import FastMCP

CHROMA_HOST = os.getenv("CHROMA_HOST", "127.0.0.1")
CHROMA_PORT = int(os.getenv("CHROMA_PORT", "8010"))
COLLECTION_NAME = os.getenv("CHROMA_COLLECTION", "agent_memory")

mcp = FastMCP("chroma-memory")

client = chromadb.HttpClient(host=CHROMA_HOST, port=CHROMA_PORT)

embedding_function = embedding_functions.DefaultEmbeddingFunction()

collection = client.get_or_create_collection(
    name=COLLECTION_NAME,
    metadata={"hnsw:space": "cosine"},
    embedding_function=embedding_function,
)


@mcp.tool()
def remember_memory(
    text: str,
    title: Optional[str] = None,
    tags: Optional[str] = None,
    source: Optional[str] = None,
) -> str:
"""
    Store useful long-term memory: benchmark results, project decisions,
    working commands, repo facts, or recurring user preferences.
    """
text = text.strip()
if not text:
return "Memory text is empty; nothing stored."

memory_id = str(uuid.uuid4())
now = int(time.time())

collection.add(
    ids=[memory_id],
    documents=[text],
    metadatas=[{
    "title": title or "",
    "tags": tags or "",
    "source": source or "",
    "created_at": now,
    "updated_at": now,
    }],
)

return f"Stored memory_id={memory_id}"


@mcp.tool()
def search_memory(query: str, top_k: int = 5) -> str:
"""
    Search long-term memory for information relevant to the current task.
    """
query = query.strip()
if not query:
return "Search query is empty."

top_k = max(1, min(int(top_k), 10))

result = collection.query(
    query_texts=[query],
    n_results=top_k,
    include=["documents", "metadatas", "distances"],
)

ids = result.get("ids", [[]])[0]
docs = result.get("documents", [[]])[0]
metas = result.get("metadatas", [[]])[0]
dists = result.get("distances", [[]])[0]

if not ids:
return "No relevant memories found."

chunks = []
for i, memory_id in enumerate(ids):
meta = metas[i] or {}
chunks.append(
    f"[{i+1}] id={memory_id}\n"
    f"title={meta.get('title', '')}\n"
    f"tags={meta.get('tags', '')}\n"
    f"source={meta.get('source', '')}\n"
    f"distance={dists[i] if i < len(dists) else ''}\n"
    f"memory:\n{docs[i]}"
)

return "\n\n---\n\n".join(chunks)


@mcp.tool()
def delete_memory(memory_id: str) -> str:
"""
    Delete one memory by exact memory_id.
    """
memory_id = memory_id.strip()
if not memory_id:
return "memory_id is empty."

collection.delete(ids=[memory_id])
return f"Deleted memory_id={memory_id}"


@mcp.tool()
def update_memory(memory_id: str, new_text: str) -> str:
"""
    Replace an existing memory by exact memory_id.
    """
memory_id = memory_id.strip()
new_text = new_text.strip()

if not memory_id:
return "memory_id is empty."
if not new_text:
return "new_text is empty."

current = collection.get(ids=[memory_id], include=["metadatas"])
if not current.get("ids"):
return f"No memory found with id={memory_id}"

meta = current["metadatas"][0] or {}
meta["updated_at"] = int(time.time())

collection.update(
    ids=[memory_id],
    documents=[new_text],
    metadatas=[meta],
)

return f"Updated memory_id={memory_id}"


@mcp.tool()
def list_recent_memories(limit: int = 10) -> str:
"""
    List recently stored memories.
    """
limit = max(1, min(int(limit), 50))

result = collection.get(include=["documents", "metadatas"])

rows = []
for memory_id, doc, meta in zip(
    result.get("ids", []),
    result.get("documents", []),
    result.get("metadatas", []),
):
meta = meta or {}
rows.append((meta.get("created_at", 0), memory_id, doc, meta))

rows.sort(reverse=True, key=lambda x: x[0])
rows = rows[:limit]

if not rows:
return "No memories stored yet."

out = []
for created_at, memory_id, doc, meta in rows:
preview = doc[:300].replace("\n", " ")
out.append(
    f"id={memory_id}\n"
    f"title={meta.get('title', '')}\n"
    f"tags={meta.get('tags', '')}\n"
    f"created_at={created_at}\n"
    f"preview={preview}"
)

return "\n\n---\n\n".join(out)


if __name__ == "__main__":
mcp.run()
PY
}

install_playwright_browser() {
echo
echo "==> Installing Playwright Chromium browser"

npx -y playwright install chromium || true
}

create_launcher_script() {
echo
echo "==> Creating internet.sh launcher"

cat > internet.sh <<'LAUNCHER'
#!/usr/bin/env bash
set -Eeuo pipefail

# Usage:
#   ./internet.sh
#   ./internet.sh gemma4-26b-a4b-it-qat-q4_0
#   MCP_MEMORY_MODEL_NAME=gemma4-26b-a4b-it-qat-q4_0 ./internet.sh
#
# The Chroma Docker volume name is exactly:
#   chroma-memory-volume-<safe_model_name>
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

# Stop old MCP servers started by previous runs.
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
ss -ltn "sport = :$port" | grep -q LISTEN
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
echo "Run ./mcp_setup.sh first."
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

# Remove old manually-created container from earlier experiments, but do not delete its data folder/volume.
docker rm -f chroma-memory >/dev/null 2>&1 || true

if port_in_use "$CHROMA_DB_PORT"; then
echo
echo "ERROR: Port $CHROMA_DB_PORT is already in use."
echo "Details:"
ss -ltnp "sport = :$CHROMA_DB_PORT" || true
echo
echo "Stop the process using this port or set CHROMA_DB_PORT to another value."
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
        --stdio "env CHROMA_HOST=127.0.0.1 CHROMA_PORT=${CHROMA_DB_PORT} CHROMA_COLLECTION=agent_memory uv run --project ${CHROMA_MCP_DIR} python server.py" \
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
LAUNCHER

chmod +x internet.sh
}

warm_up_mcp_packages() {
echo
echo "==> Warming up MCP packages"

timeout 60 uvx duckduckgo-mcp-server --help >/dev/null 2>&1 || true
timeout 60 npx -y supergateway --help >/dev/null 2>&1 || true
timeout 60 npx -y @modelcontextprotocol/server-sequential-thinking --help >/dev/null 2>&1 || true
timeout 60 uvx mcp-server-fetch --help >/dev/null 2>&1 || true
timeout 60 uvx mcp-server-time --help >/dev/null 2>&1 || true
timeout 60 uvx mcp-server-sqlite --help >/dev/null 2>&1 || true
timeout 60 npx -y @upstash/context7-mcp --help >/dev/null 2>&1 || true
timeout 60 npx -y @playwright/mcp@latest --help >/dev/null 2>&1 || true

echo "Pulling Chroma image if missing: $CHROMA_IMAGE"
docker image inspect "$CHROMA_IMAGE" >/dev/null 2>&1 || docker pull "$CHROMA_IMAGE"
}

print_done_message() {
echo
echo "============================================================"
echo "MCP setup complete."
echo "============================================================"
echo
echo "Run all MCP servers with memory for your default Gemma 4 QAT model:"
echo
echo "  ./internet.sh"
echo
echo "Run with an explicit model-specific memory volume:"
echo
echo "  ./internet.sh gemma4-26b-a4b-it-qat-q4_0"
echo "  ./internet.sh gemma4-26b-a4b-it-normal-q4_k_m"
echo
echo "The Chroma memory volume will be named exactly:"
echo
echo "  chroma-memory-volume-<model_name>"
echo
echo "Example:"
echo
echo "  chroma-memory-volume-gemma4-26b-a4b-it-qat-q4_0"
echo
echo "Memory MCP endpoint:"
echo
echo "  http://127.0.0.1:8011/mcp"
echo
echo "Chroma DB endpoint:"
echo
echo "  http://127.0.0.1:8010"
echo
echo "Check volumes:"
echo
echo "  docker volume ls | grep chroma-memory-volume"
echo
}

main() {
install_system_packages
install_uv
export PATH="$HOME/.local/bin:$PATH"
check_commands
ensure_docker_running
setup_chroma_memory_mcp
install_playwright_browser
create_launcher_script
warm_up_mcp_packages
print_done_message
}

main "$@"
