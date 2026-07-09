import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StreamableHTTPClientTransport } from "@modelcontextprotocol/sdk/client/streamableHttp.js";

const servers = [
  ["duckduckgo", "http://127.0.0.1:8000/mcp"],
  ["sequential-thinking", "http://127.0.0.1:8003/mcp"],
  ["fetch", "http://127.0.0.1:8004/mcp"],
  ["time", "http://127.0.0.1:8005/mcp"],
  ["sqlite", "http://127.0.0.1:8006/mcp"],
  ["context7", "http://127.0.0.1:8007/mcp"],
  ["playwright", "http://127.0.0.1:8931/mcp"],
];

function approxTokens(text) {
  return Math.ceil(text.length / 4);
}

for (const [name, url] of servers) {
  try {
    const client = new Client(
      { name: "mcp-size-checker", version: "1.0.0" },
      { capabilities: {} }
    );

    const transport = new StreamableHTTPClientTransport(new URL(url));
    await client.connect(transport);

    const toolsResult = await client.listTools();
    const tools = toolsResult.tools ?? [];

    const raw = JSON.stringify(toolsResult, null, 2);

    const toolRows = tools.map((tool) => {
      const toolRaw = JSON.stringify(tool, null, 2);
      return {
        name: tool.name,
        chars: toolRaw.length,
        approx_tokens: approxTokens(toolRaw),
      };
    });

    toolRows.sort((a, b) => b.approx_tokens - a.approx_tokens);

    console.log("\n==================================================");
    console.log(`${name}`);
    console.log(`URL: ${url}`);
    console.log(`Tools: ${tools.length}`);
    console.log(`Tool schema chars: ${raw.length}`);
    console.log(`Approx prompt tokens: ${approxTokens(raw)}`);
    console.log("Largest tools:");
    console.table(toolRows.slice(0, 10));

    await client.close();
  } catch (err) {
    console.log("\n==================================================");
    console.log(`${name}`);
    console.log(`URL: ${url}`);
    console.log("FAILED:", err?.message ?? err);
  }
}

// npm install @modelcontextprotocol/sdk
// run with :
// node mcp_tool_size_check.mjs
