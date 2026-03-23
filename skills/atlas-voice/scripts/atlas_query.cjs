#!/usr/bin/env node
// atlas_query.js — send one message to the Atlas main session via Gateway WebSocket
// Usage: node atlas_query.js "your message here"
// Prints the agent reply to stdout, exits 0 on success.

const WS_PATH = "/opt/homebrew/lib/node_modules/openclaw/node_modules/ws";
const WebSocket = require(WS_PATH);

const GW_URL = "ws://127.0.0.1:18789";
const TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN || "add6b9d322c8";
const message = process.argv.slice(2).join(" ");

if (!message) {
  process.stderr.write("Usage: atlas_query.js <message>\n");
  process.exit(1);
}

const ws = new WebSocket(`${GW_URL}?token=${TOKEN}`);
let replied = false;
let sessionId = null;

const timeout = setTimeout(() => {
  if (!replied) {
    process.stderr.write("Timeout waiting for reply\n");
    ws.close();
    process.exit(2);
  }
}, 60000);

ws.on("open", () => {
  // Join main session
  ws.send(
    JSON.stringify({
      method: "session.join",
      params: { sessionKey: "agent:main:main" },
      id: 1,
    }),
  );
});

ws.on("message", (data) => {
  let msg;
  try {
    msg = JSON.parse(data);
  } catch {
    return;
  }

  // After joining, send the chat message
  if (msg.id === 1) {
    sessionId = msg.result && msg.result.sessionId;
    ws.send(
      JSON.stringify({
        method: "chat.send",
        params: { message, sessionKey: "agent:main:main" },
        id: 2,
      }),
    );
    return;
  }

  // Watch for agent reply event
  if (msg.event === "agent" && msg.params && msg.params.status === "done") {
    const reply = msg.params.reply || msg.params.message || msg.params.content || "";
    if (reply && !replied) {
      replied = true;
      clearTimeout(timeout);
      process.stdout.write(reply + "\n");
      ws.close();
    }
    return;
  }

  // Also handle chat event with role=assistant
  if (msg.event === "chat" && msg.params && msg.params.role === "assistant") {
    const reply = msg.params.content || msg.params.message || "";
    if (reply && !replied) {
      replied = true;
      clearTimeout(timeout);
      process.stdout.write(reply + "\n");
      ws.close();
    }
  }
});

ws.on("error", (err) => {
  process.stderr.write(`WS error: ${err.message}\n`);
  process.exit(3);
});

ws.on("close", () => {
  if (!replied) process.exit(2);
});
