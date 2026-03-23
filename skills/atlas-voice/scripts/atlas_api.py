#!/usr/bin/env python3
"""Build and send an Anthropic API request for the voice loop."""
import json, sys, os, urllib.request, urllib.error

api_key = os.environ.get("ANTHROPIC_API_KEY", "")
history_file = sys.argv[1]
system_prompt = sys.argv[2]
user_message = sys.argv[3]

# Load history
with open(history_file) as f:
    history = json.load(f)

# Append user message
history.append({"role": "user", "content": user_message})

# Build request
payload = json.dumps({
    "model": "claude-haiku-4-5",
    "max_tokens": 300,
    "system": system_prompt,
    "messages": history
}).encode()

req = urllib.request.Request(
    "https://api.anthropic.com/v1/messages",
    data=payload,
    headers={
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json",
    }
)

try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.loads(resp.read())
    reply = data.get("content", [{}])[0].get("text", "")
except urllib.error.HTTPError as e:
    data = json.loads(e.read())
    reply = data.get("error", {}).get("message", "API error")

# Append assistant reply to history
history.append({"role": "assistant", "content": reply})
with open(history_file, "w") as f:
    json.dump(history, f)

print(reply)
