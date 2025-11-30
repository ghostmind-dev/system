# meta.json Configuration Guide

## Introduction

The `meta.json` file is the **central configuration** for every application in the Ghostmind system. It is the single source of truth that defines what components exist, how they're configured, and how the `run` tool orchestrates them.

## ⚠️ CRITICAL: ALWAYS FETCH THE SCHEMA

**This cannot be emphasized enough:**

### Before ANY work with meta.json, ALWAYS fetch the latest schema:

```
Schema URL: https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

**Why this is absolutely critical:**
- The schema is the **only authoritative source** for all available properties
- The schema is **actively maintained and updated**
- Properties, structures, validation rules, and options **change over time**
- Working without the latest schema **will lead to invalid configurations**
- **No documentation can replace the schema** - it is always the source of truth

**When to fetch (every time):**
- Before creating a new meta.json
- Before modifying an existing meta.json
- Before documenting meta.json properties
- Before troubleshooting configuration issues
- **At the start of ANY task** involving the Ghostmind system
- When in doubt about any property or structure

**How to fetch:**
Use WebFetch or similar tools to retrieve and examine the complete schema structure.

## Core Required Properties

Every meta.json must have these three properties:

```json
{
  "id": "_kc2vvsMN7jU",
  "name": "my-app",
  "version": "0.0.1"
}
```

**`id` (string, required)**
- Unique identifier
- Generated once, never changes

**`name` (string, required)**
- Configuration name
- Used to extract `PROJECT` and `APP` environment variables
- Should be descriptive

**`version` (string, required)**
- Semantic version: "major.minor.patch"
- Track configuration changes over time

## Optional Core Metadata

```json
{
  "description": "Next.js UI with authentication",
  "type": "app",
  "global": false,
  "tags": ["frontend", "oauth"]
}
```

**`description`** - Human-readable description

**`type`** - Values: `"app"`, `"project"`, `"template"`

**`global`** - Boolean for global/local scope

**`tags`** - Array of strings for categorization

## Configuration Components

meta.json can define configurations for:

| Component   | Property     | Detailed Guide                |
|-------------|--------------|-------------------------------|
| Docker      | `docker`     | `docker-overview.md`          |
| Compose     | `compose`    | `compose-overview.md`         |
| Terraform   | `terraform`  | `terraform-overview.md`       |
| Tmux        | `tmux`       | `tmux-guide.md`               |
| Custom      | `custom`     | `custom-scripts-guide.md`     |
| Routines    | `routines`   | `routines-guide.md`           |
| MCP         | `mcp`        | `mcp-configuration.md`        |
| Tunnel      | `tunnel`     | `tunnel-configuration.md`     |
| Secrets     | `secrets`    | `system-overview.md`          |
| Port        | `port`       | `system-overview.md`          |

**⚠️ For detailed configuration of each component:**
- **Fetch the schema** to see available properties
- **Read the component's guide** for detailed documentation and examples
- Each guide includes its own meta.json configuration section

## Variable Substitution

meta.json supports variable substitution:

```json
{
  "name": "my-app",
  "port": 5001,
  "tunnel": {
    "default": {
      "hostname": "${PROJECT}.example.com",
      "service": "http://localhost:${PORT}"
    }
  }
}
```

Variables available:
- `${PORT}` - From `port` property
- `${PROJECT}` - From root meta.json `name`
- `${APP}` - From current directory meta.json `name`
- Any variable from `.env` files

**For details on variable substitution:** See `system-overview.md` (Environment Variables section)

## Multi-meta.json Projects

Projects can have multiple meta.json files:

### Pattern 1: Root + App-Specific

```
my-project/
├── meta.json          # Root: global config (tmux, mcp)
├── ui/
│   └── meta.json      # UI: docker, compose, terraform
└── api/
    └── meta.json      # API: docker, compose, terraform
```

**Behavior:**
- `PROJECT` extracted from root meta.json `name`
- `APP` extracted from current directory meta.json `name`
- Navigate to appropriate directory before running `run` commands

### Pattern 2: Single Consolidated

```
my-app/
├── meta.json          # All configuration in one file
├── app/
├── docker/
├── local/
└── infra/
```

### Pattern 3: Config-Only (No App Code)

```
database/
├── meta.json          # Just infrastructure config
└── infra/
```

**For details:** See `system-overview.md` (Project Structure Patterns section)

## Component Configuration Overview

**Each component has its own guide with detailed meta.json configuration:**

### Docker (`docker` property)
```json
{
  "docker": {
    "default": {
      "root": "docker",
      "image": "gcr.io/project/app",
      "context_dir": "app"
    }
  }
}
```
**→ See `docker-overview.md` for complete configuration**

### Compose (`compose` property)
```json
{
  "compose": {
    "default": {
      "root": "local",
      "filename": "compose.yaml"
    }
  }
}
```
**→ See `compose-overview.md` for complete configuration**

### Terraform (`terraform` property)
```json
{
  "terraform": {
    "run": {
      "path": "infra",
      "containers": ["default"]
    }
  }
}
```
**→ See `terraform-overview.md` for complete configuration**

### Tmux (`tmux` property)
```json
{
  "tmux": {
    "sessions": [
      {
        "name": "session-name",
        "windows": [ ... ]
      }
    ]
  }
}
```
**→ See `tmux-guide.md` for complete configuration**

### Custom Scripts (`custom` property)
```json
{
  "custom": {
    "root": "scripts"
  }
}
```
**→ See `custom-scripts-guide.md` for complete configuration**

### Routines (`routines` property)
```json
{
  "routines": {
    "dev": "run custom dev build up",
    "deploy": "run docker build && run docker push"
  }
}
```
**→ See `routines-guide.md` for complete configuration**

### MCP (`mcp` property)
```json
{
  "mcp": {
    "server-name": {
      "type": "http",
      "url": "https://mcp.example.com"
    }
  }
}
```
**→ See `mcp-configuration.md` for complete configuration**

### Tunnel (`tunnel` property)
```json
{
  "tunnel": {
    "default": {
      "hostname": "app.example.com",
      "service": "http://localhost:5001"
    }
  }
}
```
**→ See `tunnel-configuration.md` for complete configuration**

## Workflow: Creating a meta.json

**1. Fetch the Schema (ALWAYS)**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

**2. Start with Required Properties**
```json
{
  "id": "unique-id",
  "name": "my-app",
  "version": "0.0.1"
}
```

**3. Add Components as Needed**

For each component you want to add:
1. **Fetch the schema** again to see latest structure
2. **Read the component's guide** (e.g., `docker-overview.md`)
3. **Add the configuration** to meta.json
4. **Test with `run` commands**

**4. Validate**

Ensure:
- Required properties present
- Referenced directories exist
- Valid JSON syntax
- Variable substitution uses correct format

## Best Practices

### 1. Always Fetch Schema First

Cannot be repeated enough - **fetch the schema before any meta.json work**.

### 2. Start Minimal, Expand Incrementally

```json
// Start
{
  "id": "abc",
  "name": "app",
  "version": "0.0.1"
}

// Add components one at a time
{
  "id": "abc",
  "name": "app",
  "version": "0.0.1",
  "docker": { ... }  // Added docker
}
```

### 3. Read Component Guides for Details

Don't guess at configuration - read the specific guide for each component.

### 4. Use Variable Substitution

Avoid hardcoding values that can be derived:

```json
// ✅ Good
{
  "port": 5001,
  "tunnel": {
    "default": {
      "service": "http://localhost:${PORT}"
    }
  }
}

// ❌ Avoid
{
  "port": 5001,
  "tunnel": {
    "default": {
      "service": "http://localhost:5001"
    }
  }
}
```

### 5. Organize Multi-App Projects

Use multiple meta.json files for complex projects:
- Root meta.json: Global config (tmux, mcp)
- App meta.json files: App-specific config (docker, compose, terraform)

## Troubleshooting

### "Property not found in schema"

**Problem:** Using a property that doesn't exist

**Solution:** Fetch the schema and verify the property exists and is spelled correctly

### "Invalid value for property"

**Problem:** Using wrong type or invalid value

**Solution:** Fetch the schema to see valid types and enum values

### "Referenced directory doesn't exist"

**Problem:** Config references `"root": "docker"` but no `docker/` directory

**Solution:** Create the directory or fix the path in meta.json

### Always Out of Date?

**Problem:** Documentation seems out of sync with schema

**Solution:** The schema is the authority - always fetch it, documentation may lag behind

## Next Steps

**To understand the system:**
- `system-overview.md` - Architecture and how components connect
- `run-cli-overview.md` - How run commands work with meta.json

**To configure specific components (each has meta.json config section):**
- `docker-overview.md` - Docker images
- `compose-overview.md` - Local development
- `terraform-overview.md` - Infrastructure deployment
- `tmux-guide.md` - Terminal layouts
- `custom-scripts-guide.md` - TypeScript scripts
- `routines-guide.md` - Command aliases
- `mcp-configuration.md` - MCP servers
- `tunnel-configuration.md` - Cloudflared tunnels

**Remember: ALWAYS FETCH THE SCHEMA FIRST**

```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```
