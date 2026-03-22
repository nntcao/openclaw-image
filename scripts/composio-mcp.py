#!/usr/bin/env python3
"""Composio MCP server launcher — creates an MCP server from configured toolkits."""
import os
import sys
import json

try:
    from composio import Composio
except ImportError:
    print("composio-core not installed, skipping MCP server", file=sys.stderr)
    sys.exit(1)

api_key = os.environ.get("COMPOSIO_API_KEY")
if not api_key:
    print("COMPOSIO_API_KEY not set, skipping MCP server", file=sys.stderr)
    sys.exit(1)

# Load toolkit config
config_path = os.path.expanduser("~/.openclaw/mcp-servers.json")
toolkits = ["gmail", "google-calendar", "github", "slack"]
if os.path.exists(config_path):
    with open(config_path) as f:
        cfg = json.load(f)
    mcp_cfg = cfg.get("mcpServers", {}).get("composio-mcp", {})
    toolkits = mcp_cfg.get("toolkits", toolkits)

composio = Composio(api_key=api_key)
server = composio.mcp.create(
    name="openclaw-composio",
    toolkits=[{"toolkit": t} for t in toolkits],
)
server.run()
