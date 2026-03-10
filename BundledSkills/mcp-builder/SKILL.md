---
name: mcp-builder
description: "Guide for creating high-quality MCP (Model Context Protocol) servers that enable LLMs to interact with external services through well-designed tools."
---

## MCP Server Development Guide

### Phases

| Phase | Description |
|-------|-------------|
| 1. Research & Planning | API coverage, tool naming — see `references/planning.md` |
| 2. Implementation | Schema, annotations, error handling — see `references/implementation.md` |
| 3. Review & Test | DRY, types, MCP Inspector |
| 4. Evaluations | 10 test questions — see `references/evaluations.md` |

### Recommended Stack
- Language: TypeScript (recommended)
- Transport: Streamable HTTP for remote servers, stdio for local servers

### Tool Naming
Use consistent prefixes and action-oriented naming:
`github_create_issue`, `github_list_repos`, `slack_send_message`
