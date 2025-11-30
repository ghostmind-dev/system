# System Overview

## Introduction

The Ghostmind development system is a configuration-driven workflow where **meta.json serves as the central configuration** that defines and orchestrates all application components. This document provides a comprehensive overview of the system architecture, development environment, and how components interconnect.

## Core Principle: Everything Starts with `meta.json`

The `meta.json` file is the **foundation of every application** in the Ghostmind system. It acts as the single source of truth that:

- Defines what components exist in the application
- Links different parts together (app code, Docker, Compose, Terraform, Tmux)
- Configures development tools (MCP, tunnels, routines, custom scripts)
- Enables the `run` tool to understand and orchestrate the application
- Allows dynamic behavior through variable substitution

**Key insight:** An application can exist with just a `meta.json` file. All other components (Docker, Compose, Terraform, etc.) are optional and only defined when needed.

**Flexibility:** The structure is not prescriptive. `meta.json` describes where things are and how they're configured, not enforcing rigid folder structures or naming conventions. A project can have one meta.json at the root, or multiple meta.json files for different apps within the project.

### CRITICAL: Always Fetch the Schema

**⚠️ IMPERATIVE RULE: Before working with meta.json configuration or understanding the system, ALWAYS fetch the latest schema:**

```
Schema URL: https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

**Why this is critical:**
- The schema is the **authoritative source** for all available meta.json properties
- The schema is actively maintained and updated
- Properties, structures, and validation rules may change
- Working without the latest schema can lead to invalid configurations

**When to fetch:**
- Before creating or modifying meta.json files
- When documenting the system
- When troubleshooting configuration issues
- At the start of any task involving the Ghostmind system

**How to fetch:**
Use WebFetch or similar tools to retrieve the schema and understand the complete structure before proceeding with any configuration work.

## System Architecture

### GitHub Organization Structure

All Ghostmind system repositories are hosted in the GitHub organization:
- **Organization**: https://github.com/orgs/ghostmind-dev/repositories

**Key Repositories:**

1. **container** (https://github.com/ghostmind-dev/container)
   - Base Docker image for devcontainers
   - Dockerfile: https://raw.githubusercontent.com/ghostmind-dev/container/refs/heads/main/container/Dockerfile.base
   - Pre-configured development environment used by 95% of projects

2. **config** (https://github.com/ghostmind-dev/config)
   - Miscellaneous configuration files (.gitignore, vscode settings, etc.)
   - Devcontainer features that complement the main devcontainer
   - Initialization configurations

3. **init** (https://github.com/ghostmind-dev/init)
   - Initialization scripts that run on devcontainer startup
   - Performs maintenance tasks: login to GCP, install run CLI, login to vault, etc.
   - Devcontainer feature to enable/disable init actions

4. **play** (https://github.com/ghostmind-dev/play)
   - Collection of custom GitHub Actions
   - Currently used for deployment workflows

5. **run** (https://github.com/ghostmind-dev/run)
   - Core CLI tool and Deno TypeScript library
   - Orchestrates all system operations
   - meta.json schema: https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json

## Development Environment

### Devcontainer Workflow

**95% of projects are developed in VS Code Dev Containers**, providing:

- Pre-configured development environment from the container repository
- Consistent tooling across all team members
- Automatic integration with system utilities
- Access to critical environment variables
- Seamless Docker-in-Docker operations

**Exceptions:** Projects requiring native OS access are developed outside of devcontainers.

### Devcontainer Configuration

The devcontainer is configured through `.devcontainer/devcontainer.json` with special environment variables:

```json
{
  "containerEnv": {
    "LOCALHOST_SRC": "${localWorkspaceFolder}",
    "SRC": "${containerWorkspaceFolder}"
  }
}
```

**Features Integration:**
- Devcontainer features from the **config** repository provide additional tooling
- Devcontainer features from the **init** repository enable startup automation

### Critical Environment Variables: `SRC` and `LOCALHOST_SRC`

**These are fundamental to the entire system and used heavily throughout applications:**

**`SRC`** - Root path inside the dev container
- Example: `/workspaces/project-name/`
- Used for all operations within the dev container
- References to files and folders when working inside the container

**`LOCALHOST_SRC`** - Host machine path to the same location
- Example: `/Users/developer/projects/project-name/`
- **Critical for Docker-in-Docker operations**
- Required when mounting volumes from within the devcontainer

### Why Both Are Essential

When running **Docker from within the dev container** (Docker-in-Docker):
- Container paths (`SRC`) do NOT work for volume mounting
- Docker daemon runs on the host and needs **host paths** (`LOCALHOST_SRC`)
- This enables hot-reload in local development with Docker Compose

**Example scenario:**
```yaml
# In compose.yaml - CORRECT usage
services:
  app:
    volumes:
      - ${LOCALHOST_SRC}/ui/app:/app/app  # ✅ Host path for mounting
    environment:
      LOCALHOST_SRC: ${LOCALHOST_SRC}     # ✅ Pass to container
```

```bash
# Inside dev container - WRONG vs RIGHT
❌ docker run -v $SRC/data:/app/data image        # Container path - won't mount
✅ docker run -v $LOCALHOST_SRC/data:/app/data image  # Host path - works
```

This dual-path system enables seamless Docker operations while maintaining the dev container workflow.

## Environment Variables and Secrets Management

### Environment File Structure

Environment variables are managed through layered `.env` files:

**File Types:**
- **`.env.base`** (or `.env.common`) - Shared across all environments (local, dev, prod)
- **`.env.local`** - Local development specific
- **`.env.dev`** - Development environment specific (optional)
- **`.env.prod`** - Production specific (optional)

**Configurable Base Name:**
The base environment file extension can be configured in `meta.json`:
```json
{
  "secrets": {
    "base": "common"  // Uses .env.common instead of .env.base
  }
}
```

### Variable Substitution in .env Files

Environment files support **variable substitution**, allowing dynamic values:

**Example .env.base:**
```bash
PORT=5001
APP="ui"
```

**Example .env.local:**
```bash
ENVIRONMENT=local
SERVER_URL=http://localhost:${PORT}         # References PORT from .env.base
DB_ENDPOINT="http://host.docker.internal:5080/v1/graphql"
TUNNEL_NAME="ghostmind.app"
NEXTAUTH_URL="https://${TUNNEL_NAME}"       # Dynamic substitution
```

The `run` tool automatically resolves these references when loading environment variables.

### Automatic Variable Extraction from meta.json

Two special variables are **automatically extracted** from `meta.json` if not explicitly defined in `.env` files:

**`PROJECT`** - Extracted from the `name` property in the **root** meta.json
```json
// Root meta.json
{
  "name": "mtl",  // PROJECT = "mtl"
  ...
}
```

**`APP`** - Extracted from the `name` property in the meta.json **where the command is run**
```json
// /city/meta.json
{
  "name": "city",  // APP = "city" when run from /city/
  ...
}
```

**Behavior when run from root:**
If run from the root directory and neither PROJECT nor APP is defined in `.env` files, both will have the same value (the root project name).

### Vault Integration for Secrets

**Vault wrapper** (built into the `run` command) manages sensitive secrets:

**How it works:**
- Secrets are stored in Vault (HashiCorp Vault or similar)
- `.env` files are stored in Vault, NOT in version control
- The `run` tool provides import/export functionality

**Commands:**
```bash
# Import secrets from Vault to local .env files
run vault import

# Export local .env files to Vault
run vault export
```

**Workflow:**
1. Secrets stored centrally in Vault
2. Developers import secrets locally when needed
3. Never commit `.env` files to Git
4. Update Vault when secrets change

## The `run` Tool

The `run` tool is the **unified orchestrator** for all system operations.

### Dual Nature: CLI and Library

**Available in two forms:**
1. **CLI tool** - Command-line interface for terminal operations
2. **Deno TypeScript library** - Importable functions for custom scripts (`jsr:@ghostmind/run`)

**Example CLI usage:**
```bash
run docker build
run compose up
run terraform apply
run tmux init session-name
run routine dev_start
run custom dev build up
```

**Example library usage (in custom scripts):**
```typescript
import { dockerComposeBuild, dockerComposeUp } from 'jsr:@ghostmind/run';

await dockerComposeBuild({});
await dockerComposeUp({ forceRecreate: true });
```

### meta.json Dependency

**Most operations require `meta.json`:**
- The `run` tool reads `meta.json` to understand the application structure
- Commands should be executed from the directory containing the relevant `meta.json`
- For multi-meta.json projects, navigate to the appropriate directory before running commands

**Example:**
```bash
# For a project with multiple apps
/project/
  ├── meta.json           # Root project config
  ├── ui/
  │   └── meta.json       # UI app config
  └── api/
      └── meta.json       # API app config

# Run UI-specific commands from ui/
cd /project/ui
run custom dev up

# Run API-specific commands from api/
cd /project/api
run custom dev up
```

### Core Capabilities

The `run` tool provides utilities for:

- **Docker**: Build and push container images
- **Compose**: Manage local development environments
- **Terraform**: Deploy infrastructure to cloud
- **Tmux**: Initialize and manage terminal sessions
- **MCP**: Configure Model Context Protocol servers
- **Tunnel**: Set up Cloudflared tunnels
- **Vault**: Import/export secrets
- **Custom**: Execute custom TypeScript scripts
- **Routine**: Run named shell commands
- **Environment**: Automatic variable injection and substitution

## System Components

### 1. Application Code (`app/`)

**Purpose:** Contains the actual source code of your application

**What it can be:** Node.js, Go, Python, Rust, or any application type

**In meta.json:** Not explicitly configured - it's the default working directory where the application code lives

**Flexibility:** The `app/` directory is a convention, not a requirement. Application code can be in any structure.

### 2. Containerization (`docker/`)

**Purpose:** Defines how to package the application into Docker images for production deployment

**Contains:** Dockerfile(s) for building container images

**In meta.json:** Configured under the `docker` property:
```json
{
  "docker": {
    "default": {
      "root": "docker",
      "image": "gcr.io/ghostmind-core/my-app",
      "env_based": false,
      "context_dir": "app"
    }
  }
}
```

**Key features:**
- Multiple image definitions possible (default, dev, test, etc.)
- Build context typically points to `app/`
- Image name and registry configuration
- Tag modifiers for versioning

**Separation from Compose:**
- Docker config is for **production** images
- Compose config (below) is for **local development**
- They operate independently

### 3. Local Development (`local/` or `compose/`)

**Purpose:** Enables local development with Docker Compose and hot-reload

**Contains:** `compose.yaml` defining services, volumes, networks

**Critical:** Only used for **development**, never for production deployment

**In meta.json:** Configured under the `compose` property:
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

**Hot-reload pattern:**
```yaml
services:
  app:
    volumes:
      - ${LOCALHOST_SRC}/ui/app:/app/app  # Enables hot-reload
    environment:
      LOCALHOST_SRC: ${LOCALHOST_SRC}     # Pass host path to container
```

The `LOCALHOST_SRC` mounting is essential for hot-reload to work in the devcontainer workflow.

### 4. Infrastructure Deployment (`infra/`)

**Purpose:** Infrastructure-as-Code using Terraform for cloud deployment

**Target:** Currently optimized for **Google Cloud Run**

**Contains:** Terraform configuration files

**In meta.json:** Configured under the `terraform` property:
```json
{
  "terraform": {
    "run": {
      "path": "infra",
      "global": false,
      "containers": ["default"]
    }
  }
}
```

**Required file structure:**
- `backend.tf` - Terraform state backend
- `versions.tf` - Provider versions
- `main.tf` - Main infrastructure resources
- `variables.tf` - Variable definitions (auto-generated from .env files)

The `containers` array references Docker images defined in the `docker` section, enabling automated deployments with freshly built images.

### 5. Custom Scripts (`scripts/`)

**Purpose:** TypeScript/Deno scripts for complex, reusable workflows

**Contains:** `.ts` files that export a default function

**In meta.json:** Configured under the `custom` property:
```json
{
  "custom": {
    "root": "scripts"
  }
}
```

**Script structure:**
```typescript
import type { CustomArgs, CustomOptions } from 'jsr:@ghostmind/run';
import { dockerComposeBuild, dockerComposeUp } from 'jsr:@ghostmind/run';

export default async function (args: CustomArgs, opts: CustomOptions) {
  if (opts.has('build')) {
    await dockerComposeBuild({});
  }
  if (opts.has('up')) {
    await dockerComposeUp({ forceRecreate: true });
  }
}
```

**Execution:**
```bash
run custom dev build up  # Runs scripts/dev.ts with 'build' and 'up' flags
```

Custom scripts are the most powerful feature for creating project-specific workflows.

### 6. Routines (Named Shell Commands)

**Purpose:** Quick access to frequently used commands through memorable names

**In meta.json:** Configured under the `routines` property:
```json
{
  "routines": {
    "dev_start": "run custom dev build up",
    "tmux_init": "run tmux init mtl --all",
    "tunnel_run": "run tunnel run --all --name mtl"
  }
}
```

**Execution:**
```bash
run routine dev_start   # Executes "run custom dev build up"
run routine tmux_init   # Executes "run tmux init mtl --all"
```

Routines are simple shell command aliases stored in configuration.

### 7. MCP (Model Context Protocol)

**Purpose:** Configure project-specific MCP servers for AI agent integration

**In meta.json:** Configured under the `mcp` property:
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

**Workflow:**
1. Define MCP servers in `meta.json`
2. Run `run mcp set --all` to generate `.mcp.json`
3. The `.mcp.json` file is used by Claude Code or other MCP clients

MCP servers provide domain-specific tools and knowledge to AI agents.

### 8. Tunnel (Cloudflared Tunnels)

**Purpose:** Expose local development servers through public URLs via Cloudflare

**In meta.json:** Configured under the `tunnel` property:
```json
{
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app",
      "service": "http://localhost:5001"
    }
  }
}
```

**Execution:**
```bash
run tunnel run --name default  # Starts tunnel for local:5001 → ghostmind.app
```

Tunnels enable OAuth callbacks, webhook testing, and sharing local development environments.

### 9. Tmux (Terminal Multiplexer)

**Purpose:** Configure tmux session layouts with windows and panes for development workflows

**In meta.json:** Configured under the `tmux` property:
```json
{
  "tmux": {
    "sessions": [
      {
        "name": "mtl",
        "windows": [
          {
            "name": "server",
            "layout": "compact",
            "compact": {
              "type": "main-side",
              "panes": {
                "main": "run custom dev build up",
                "execution-shell": "echo 'Ready'"
              }
            }
          }
        ]
      }
    ]
  }
}
```

**Features:**
- Multiple sessions, windows, and panes
- Three layout modes: sections (hierarchical), grid (predefined), compact (key-value)
- Automatic command execution on pane creation
- Support for SSH targets and custom paths

**Execution:**
```bash
run tmux init mtl --all      # Initialize session with all windows
run tmux attach mtl          # Attach to session
run tmux terminate mtl       # Terminate session
```

Tmux configurations enable complex, reproducible development environments.

## How Components Connect

```
meta.json (Central Configuration)
    │
    ├── Application Architecture
    │   ├── app/ (Source Code)
    │   ├── docker/ (Production Images)
    │   ├── local/ (Dev Environment with Compose)
    │   └── infra/ (Cloud Infrastructure with Terraform)
    │
    ├── Development Tools
    │   ├── scripts/ (Custom TypeScript Scripts)
    │   ├── routines (Named Shell Commands)
    │   └── tmux (Terminal Session Layouts)
    │
    ├── Integration Services
    │   ├── mcp (AI Agent Tooling)
    │   └── tunnel (Public URL Exposure)
    │
    └── Configuration
        ├── secrets (.env files + Vault)
        ├── port (Application Port)
        └── tags (Metadata)
```

**Flow:**
1. `meta.json` defines what exists and how it's configured
2. Environment variables (`.env` + vault) provide runtime configuration
3. `run` tool orchestrates operations based on `meta.json`
4. Components operate independently but reference each other through configuration

## Project Structure Patterns

### Single-App Project

```
my-app/
├── meta.json              # Single configuration
├── app/                   # Application code
├── docker/
│   └── Dockerfile
├── local/
│   └── compose.yaml
├── infra/
│   └── *.tf
├── scripts/
│   └── dev.ts
├── .env.base
└── .env.local
```

### Multi-App Project

```
my-project/
├── meta.json              # Root project configuration
├── ui/
│   ├── meta.json          # UI app configuration
│   ├── app/
│   ├── docker/
│   ├── local/
│   ├── infra/
│   ├── scripts/
│   ├── .env.base
│   └── .env.local
├── api/
│   ├── meta.json          # API app configuration
│   ├── app/
│   ├── docker/
│   ├── local/
│   ├── infra/
│   ├── scripts/
│   ├── .env.base
│   └── .env.local
└── db/
    ├── meta.json          # DB configuration (no app code)
    ├── infra/
    ├── .env.base
    └── .env.local
```

**Flexibility:**
- Each app has its own `meta.json` and configuration
- Not all apps need all components (e.g., db might only have infra/)
- Run commands from the appropriate directory

### Config-Only Project

```
database/
├── meta.json              # Just configuration
├── infra/
│   └── *.tf
├── .env.base
└── .env.prod
```

Some projects (like managed databases) only need infrastructure configuration with no application code.

## Development Workflow

### Typical Development Lifecycle

1. **Initialize Environment**
   - Open project in VS Code Dev Container
   - Devcontainer auto-runs init scripts (GCP login, vault login, install tools)
   - Import secrets: `run vault import`

2. **Start Local Development**
   - Initialize tmux layout: `run routine tmux_init`
   - Start services: `run routine dev_start` (typically runs custom script)
   - Start tunnel: `run routine tunnel_run` (if needed for OAuth/webhooks)

3. **Development**
   - Code in `app/` directory
   - Changes hot-reload via Docker Compose volume mounts (`LOCALHOST_SRC`)
   - Use execution-shell panes in tmux for commands

4. **Build and Deploy**
   - Build Docker image: `run docker build`
   - Push to registry: `run docker push`
   - Deploy infrastructure: `run terraform apply`

5. **Shutdown**
   - Terminate tmux: `run routine tmux_terminate`
   - Services stop automatically

## Key Principles

### Configuration-Driven Development

The system is designed around **configuration over convention**:
- `meta.json` is the single source of truth
- Structure is flexible, not prescriptive
- Components are loosely coupled through configuration
- The `run` tool orchestrates everything based on configuration

### Incremental Modularity

Not all applications need all components:
- Start with just `meta.json`
- Add components as needed (Docker → Compose → Terraform)
- Each component is independent and optional
- Structure adapts to application needs

### Developer Experience

The system prioritizes developer productivity:
- Consistent tooling across all projects via devcontainers
- Hot-reload for rapid iteration
- Reusable workflows through custom scripts and routines
- Automated secrets management
- Terminal multiplexing for complex workflows

### Security

Secrets are never committed to version control:
- `.env` files managed through Vault
- Import/export workflow for local development
- Separation of base config (`.env.base`) and environment-specific secrets

## Next Steps

To dive deeper into specific components:

- **meta.json structure**: See `meta-json-guide.md`
- **run CLI tool**: See `run-cli-overview.md`
- **Custom scripts**: See `custom-scripts-guide.md`
- **Docker configuration**: See `docker-overview.md`
- **Compose setup**: See `compose-overview.md`
- **Terraform deployment**: See `terraform-overview.md`
- **Tmux layouts**: See `tmux-guide.md`
- **MCP configuration**: See `mcp-configuration.md`
- **Routines**: See `routines-guide.md`
- **Tunnel setup**: See `tunnel-configuration.md`

Each guide builds on the concepts introduced in this overview.
