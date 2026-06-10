# Fully Functional Local llama.cpp Agent with TurboQuant, Drafter, and MCP Tools

This folder contains scripts for running a local experimental AI agent with `llama.cpp`, `llama-ui`, and several free MCP servers that do not require API keys.

The setup is designed for local testing: the model runs through `llama-server`, tools are exposed over localhost HTTP endpoints, and temporary logs/runtime data live under `/tmp`.

## Features

- Local `llama.cpp` server using the Gemma 4 26B A4B QAT Q4_0 GGUF model
- `llama-ui` web interface on `http://127.0.0.1:8080`
- TurboQuant KV cache settings with `turbo3` keys and `turbo2` values
- `ngram-mod` speculative drafter
- Jinja chat template support
- MCP tools through localhost HTTP endpoints
- MCP access through the `llama.cpp` web UI MCP proxy
- DuckDuckGo search MCP
- Fetch MCP
- Context7 documentation MCP
- Sequential Thinking MCP
- Time MCP
- SQLite MCP
- Playwright browser automation MCP
- Temporary logs, runtime files, SQLite data, and browser profile under `/tmp/ankur-mcp-runtime`
- No GitHub token or external API key required

## Folder Contents

| File | Purpose |
| --- | --- |
| `start.sh` | Starts `llama-server` with the Gemma 4 26B A4B QAT Q4_0 GGUF model, TurboQuant KV cache, ngram drafter, Jinja, tool support, and the web UI MCP proxy. |
| `internet.sh` | Starts all MCP servers and exposes them on localhost ports. It also creates temporary runtime, log, SQLite, and Playwright profile directories under `/tmp/ankur-mcp-runtime`. |
| `mcp_setup.sh` | Installs required dependencies, installs/warm-ups MCP packages, installs Playwright Chromium, and recreates the MCP launcher script. |
| `llama_settings_2026-06-10.json` | `llama-ui` settings export containing MCP server URLs, 300 second MCP timeouts, and useful UI settings for this local agent setup. |

## Requirements

- Linux recommended
- Tested on an Arch/Garuda-style environment
- The setup script also attempts Debian/Ubuntu, Fedora/RHEL-like, and openSUSE package managers
- `node`, `npm`, and `npx`
- `uv` and `uvx`
- `sqlite3`
- `git` and `curl`
- A built `llama.cpp` checkout with `./build/bin/llama-server`
- Enough RAM/VRAM for the selected Gemma model and context size
- Chromium/Playwright browser, installed by `mcp_setup.sh`

## Quick Start

From the repository root:

```bash
cd llama.cpp/03_fully_functional_local_agent_with_turboQuant_drafter_MCP
chmod +x mcp_setup.sh internet.sh start.sh
./mcp_setup.sh
```

Start `llama-server`:

```bash
./start.sh
```

In another terminal, start the MCP servers:

```bash
./internet.sh
```

Then open:

```text
http://127.0.0.1:8080
```

## MCP Server URLs

| MCP server | URL |
| --- | --- |
| DuckDuckGo | `http://127.0.0.1:8000/mcp` |
| Sequential Thinking | `http://127.0.0.1:8003/mcp` |
| Fetch | `http://127.0.0.1:8004/mcp` |
| Time | `http://127.0.0.1:8005/mcp` |
| SQLite | `http://127.0.0.1:8006/mcp` |
| Context7 | `http://127.0.0.1:8007/mcp` |
| Playwright | `http://127.0.0.1:8931/mcp` |

## llama-ui Setup

1. Open `http://127.0.0.1:8080`.
2. Go to the MCP Servers section in `llama-ui`.
3. Add the MCP URLs from the table above, or import/use `llama_settings_2026-06-10.json` if your UI build supports settings import.
4. Use a 300 second MCP request timeout. Some local MCP calls, browser startup, package cold starts, and documentation lookups can take longer than short default timeouts.

The provided settings export already includes the MCP server URLs with 300 second timeouts.

## Runtime and Logs

`internet.sh` recreates this temporary runtime folder on every run:

```bash
/tmp/ankur-mcp-runtime
```

| Path | Purpose |
| --- | --- |
| `/tmp/ankur-mcp-runtime/logs` | MCP server logs and PID files |
| `/tmp/ankur-mcp-runtime/data/test.db` | Temporary SQLite test database |
| `/tmp/ankur-mcp-runtime/playwright-profile` | Temporary Playwright browser profile |

The folder is deleted and recreated whenever `internet.sh` starts. If your `/tmp` is mounted as `tmpfs`, this data mostly stays in RAM and disappears after reboot.

## Testing Prompt

Copy this into `llama-ui` after the model and MCP servers are running:

```text
You have access to local MCP tools.

Please run a complete tool test:
1. Use the Time MCP to tell me the current local time.
2. Use DuckDuckGo MCP to search for "llama.cpp TurboQuant ngram drafter" and summarize the most relevant result.
3. Use Fetch MCP to fetch https://example.com and tell me the page title or main text.
4. Use Context7 MCP to look up documentation for Playwright browser automation and summarize one useful point.
5. Use SQLite MCP to create a small table called agent_test, insert one row, then read it back.
6. Use Playwright MCP to open https://example.com and confirm what text is visible on the page.
7. Use Sequential Thinking MCP to outline how you verified each tool.

Keep the final answer short and list which MCP tools worked.
```

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Port already in use | Stop the old process using that port, or change the port in `internet.sh` and update the matching URL in `llama-ui`. Useful checks: `ss -ltnp` or `lsof -i :8000`. |
| MCP failed to fetch / CORS error | Make sure `LLAMA_UI_ORIGIN` in `internet.sh` matches your UI origin. The default is `http://localhost:8080`. If you use `http://127.0.0.1:8080`, update the origin and restart `internet.sh`. |
| Playwright does not open a browser | Run `npx -y playwright install chromium` again, then restart `internet.sh`. Check `/tmp/ankur-mcp-runtime/logs/playwright.log`. |
| `uvx` missing | Run `./mcp_setup.sh`, or install `uv` manually from Astral and ensure `$HOME/.local/bin` is in your `PATH`. |
| `npx` missing | Install Node.js and npm through your system package manager, then verify `node`, `npm`, and `npx` are available. |
| Chromium missing | Run `npx -y playwright install chromium`. Some distributions may also need Playwright system dependencies. |
| `llama-ui` MCP timeout | Set MCP request timeout to 300 seconds. First runs can be slow because packages and browser profiles may initialize. |
| High RAM or swap usage | Lower context size (`-c`), generation length (`-n`), batch size (`-b`/`-ub`), or choose a smaller model/quantization in `start.sh`. |
| Model download or Hugging Face model change | Check the `-hf` model reference in `start.sh`. If the model name changes or download fails, replace it with a valid GGUF model repo/tag supported by your `llama.cpp` build. |

## Safety Notes

- MCP tools are powerful because they let the model call external tools.
- This setup intentionally avoids GitHub PAT/API-key based MCP servers.
- Playwright MCP can control a real browser session.
- The SQLite database is temporary and recreated under `/tmp/ankur-mcp-runtime/data/test.db`.
- No filesystem or git MCP server is included in the final launcher because those tools caused timeout issues and can be more sensitive.
- This is a local experimental setup, not a production security model.

## Customization

- Change the model by editing the `-hf` value in `start.sh`.
- Tune `llama.cpp` parameters in `start.sh`, including context size (`-c`), generation length (`-n`), threads (`-t`), batch size (`-b`/`-ub`), GPU layers (`-ngl`), and KV cache types (`--cache-type-k`/`--cache-type-v`).
- Change the `llama-ui` origin in `internet.sh` if your UI runs on a different host or port.
- Add or remove MCP servers by editing the `run ...` blocks in `internet.sh` and updating the MCP server list in `llama-ui`.
- If you rerun `mcp_setup.sh`, remember that it recreates `internet.sh` from the embedded launcher template.
