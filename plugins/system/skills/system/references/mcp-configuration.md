# MCP Configuration Guide

## Introduction

MCP (Model Context Protocol) servers provide specialized tools and knowledge to AI agents like Claude. The Ghostmind system allows you to configure **project-specific MCP servers** in `meta.json`, which are then used to generate `.mcp.json` files for MCP clients.

## What is MCP?

MCP servers extend AI agent capabilities by providing:
- **Tools** - Functions the agent can call (e.g., query database, search documentation)
- **Resources** - Information the agent can access (e.g., schemas, configurations)
- **Prompts** - Specialized instructions for specific tasks

**Project-Specific MCP:**
The MCP configuration in `meta.json` is for project-specific servers, not global ones.

## meta.json Configuration

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

### Basic Configuration

```json
{
  "mcp": {
    "server-name": {
      "type": "http",
      "url": "https://mcp.ghostmind.app"
    }
  }
}
```

**Structure:**

**`mcp.<name>` (object)**
- `<name>`: Server identifier (e.g., `tags-dev`, `system-local`)
- Value: Server configuration object

**For complete `mcp` property structure:** Fetch the schema

## Server Types

### HTTP Type

For remote MCP servers accessed via HTTP:

```json
{
  "mcp": {
    "tags-dev": {
      "type": "http",
      "url": "https://mcp.ghostmind.app"
    }
  }
}
```

**Properties:**
- `type`: `"http"`
- `url`: Full URL to MCP server endpoint

### Command Type

For local MCP servers executed as commands:

```json
{
  "mcp": {
    "local-server": {
      "type": "command",
      "command": "node",
      "args": ["server.js"]
    }
  }
}
```

**Properties:**
- `type`: `"command"`
- `command`: Executable command
- `args`: Array of arguments

### Command with Custom Script

```json
{
  "mcp": {
    "system-local": {
      "type": "command",
      "command": "run",
      "args": ["custom", "mcp-server"]
    }
  }
}
```

This executes a custom script that starts the MCP server.

## Workflow

### 1. Define MCP Servers in meta.json

```json
{
  "mcp": {
    "tags-dev": {
      "type": "http",
      "url": "https://mtl-mcp.ghostmind.app"
    },
    "system-dev": {
      "type": "http",
      "url": "https://mcp.ghostmind.app"
    }
  }
}
```

### 2. Generate .mcp.json

```bash
# Generate .mcp.json from all MCP configs
run mcp set --all

# Generate specific MCP server config
run mcp set --name tags-dev
```

### 3. Use with MCP Client

The generated `.mcp.json` file is used by:
- Claude Code
- Other MCP-compatible clients
- AI agents that support MCP

## Multiple MCP Servers

You can define multiple MCP servers for different purposes:

```json
{
  "mcp": {
    "database": {
      "type": "http",
      "url": "https://db-mcp.example.com"
    },
    "docs": {
      "type": "http",
      "url": "https://docs-mcp.example.com"
    },
    "local-tools": {
      "type": "command",
      "command": "node",
      "args": ["tools/mcp-server.js"]
    }
  }
}
```

## Integration with Routines

Common pattern to set MCP configuration via routine:

```json
{
  "mcp": {
    "tags-dev": {
      "type": "http",
      "url": "https://mcp.ghostmind.app"
    }
  },
  "routines": {
    "mcp_set": "run mcp set --all",
    "setup": "run vault import && run routine mcp_set"
  }
}
```

**Usage:**
```bash
run routine mcp_set
```

## Real-World Examples

### HTTP MCP Server

```json
{
  "mcp": {
    "tags-dev": {
      "type": "http",
      "url": "https://mtl-mcp.ghostmind.app"
    }
  }
}
```

### Multiple Environment-Specific Servers

```json
{
  "mcp": {
    "tags-dev": {
      "type": "http",
      "url": "https://dev-mcp.ghostmind.app"
    },
    "tags-prod": {
      "type": "http",
      "url": "https://prod-mcp.ghostmind.app"
    }
  }
}
```

### Mixed HTTP and Command

```json
{
  "mcp": {
    "remote-tools": {
      "type": "http",
      "url": "https://mcp.example.com"
    },
    "local-server": {
      "type": "command",
      "command": "run",
      "args": ["custom", "start-mcp"]
    }
  }
}
```

## When to Use MCP Configuration

**Use MCP configuration when:**
- Project needs access to project-specific tools
- AI agent needs specialized knowledge for the project
- Domain-specific operations required (database queries, API calls, etc.)

**Common Use Cases:**
- Database schema exploration
- Documentation search
- Project-specific utilities
- API interaction tools
- Custom development workflows

## Best Practices

### 1. Use Descriptive Server Names

```json
// ✅ Good - clear purpose
{
  "mcp": {
    "database-tools": { ... },
    "docs-search": { ... }
  }
}

// ❌ Avoid - unclear
{
  "mcp": {
    "server1": { ... },
    "mcp2": { ... }
  }
}
```

### 2. Separate Dev and Prod Servers

```json
{
  "mcp": {
    "tools-dev": {
      "type": "http",
      "url": "https://dev.example.com"
    },
    "tools-prod": {
      "type": "http",
      "url": "https://prod.example.com"
    }
  }
}
```

### 3. Use Routines for MCP Setup

```json
{
  "mcp": { ... },
  "routines": {
    "mcp_set": "run mcp set --all",
    "setup": "run routine mcp_set"
  }
}
```

### 4. Document Server Purpose

Add comments in documentation or README about what each MCP server provides.

## Troubleshooting

### .mcp.json not generated

**Problem:** Running `run mcp set --all` but no `.mcp.json` created

**Solution:** Verify `mcp` property exists in `meta.json` and has valid configuration

### MCP server not accessible

**Problem:** MCP client can't connect to server

**Solution:**
- Check URL is correct
- Verify server is running (for command type)
- Check network connectivity (for http type)

### Wrong server configuration

**Problem:** Generated `.mcp.json` has incorrect settings

**Solution:** Update `meta.json` and run `run mcp set --all` again

## Next Steps

- **Understanding meta.json:** See `meta-json-guide.md`
- **run CLI:** See `run-cli-overview.md`
- **Routines:** See `routines-guide.md`
- **System overview:** See `system-overview.md`

**Remember:** MCP configuration in `meta.json` is for project-specific servers. Global MCP servers are configured separately in Claude Code settings.
