# run CLI Overview

## What is `run`?

The `run` CLI is the **unified orchestrator** for all Ghostmind system operations. It reads `meta.json` to understand your application and provides commands for managing the entire development and deployment lifecycle.

## Dual Nature

**`run` is available in two forms:**

**1. CLI Tool**
```bash
run docker build
run compose up
run terraform apply
run custom dev build up
```

**2. Deno TypeScript Library**
```typescript
import { dockerBuild, dockerComposeUp } from 'jsr:@ghostmind/run';

await dockerBuild({ name: 'default' });
await dockerComposeUp({ forceRecreate: true });
```

## Critical Requirement: meta.json

**⚠️ Most `run` operations require `meta.json`:**
- Commands must be executed from the directory containing the relevant `meta.json`
- The tool reads `meta.json` to understand your application structure
- For multi-meta.json projects, navigate to the appropriate directory first

## Command Categories

The `run` tool provides commands for:

| Category    | Purpose                                    | Example                    |
|-------------|--------------------------------------------|----------------------------|
| **docker**  | Build and push production images           | `run docker build`         |
| **compose** | Manage local development with Docker Compose | `run compose up`          |
| **terraform** | Deploy infrastructure to cloud            | `run terraform apply`      |
| **tmux**    | Initialize terminal session layouts        | `run tmux init session`    |
| **mcp**     | Configure MCP servers                      | `run mcp set --all`        |
| **tunnel**  | Expose local servers via Cloudflared       | `run tunnel run --name default` |
| **vault**   | Import/export secrets from Vault           | `run vault import`         |
| **custom**  | Execute TypeScript/Deno scripts            | `run custom dev build up`  |
| **routine** | Execute named shell command aliases        | `run routine dev_start`    |

## How It Works

**1. Reads meta.json**
```json
{
  "name": "my-app",
  "docker": { ... },
  "compose": { ... },
  "routines": { ... }
}
```

**2. Executes Operations**
- `run docker build` → Reads `docker` config from meta.json
- `run compose up` → Reads `compose` config from meta.json
- `run routine dev` → Executes shell command from `routines` config

**3. Manages Environment**
- Loads `.env.base` and environment-specific `.env` files
- Resolves variable substitution (`${PORT}`, `${PROJECT}`)
- Extracts `PROJECT` and `APP` from meta.json

## Common Workflows

**Development:**
```bash
run vault import              # Get secrets
run tmux init app --all       # Setup terminal
run routine dev_start         # Start services
run tunnel run --name default # Expose locally
```

**Deployment:**
```bash
run docker build    # Build image
run docker push     # Push to registry
run terraform apply # Deploy infrastructure
```

**Custom Workflows:**
```bash
run custom dev build up        # Custom development script
run custom deploy deploy check # Custom deployment script
run custom migrate apply       # Custom migration script
```

## When to Use What

**Custom Scripts** - Complex workflows with logic, loops, error handling

**Routines** - Simple shell command aliases

**Direct Commands** - One-off operations

## Environment Variables

The `run` tool automatically:
- Loads `.env` files based on environment
- Resolves variable substitution in .env files
- Extracts `PROJECT` from root meta.json `name`
- Extracts `APP` from current directory meta.json `name`

## Best Practices

1. **Navigate to correct directory** before running commands
2. **Use routines** for frequently used command combinations
3. **Use custom scripts** for complex multi-step workflows
4. **Check meta.json** has required configuration before running commands

## Next Steps

**Understanding the system:**
- `system-overview.md` - System architecture and concepts
- `meta-json-guide.md` - Complete meta.json documentation

**Using specific features:**
- `custom-scripts-guide.md` - TypeScript/Deno workflows
- `docker-overview.md` - Docker configuration
- `compose-overview.md` - Local development
- `terraform-overview.md` - Infrastructure deployment
- `tmux-guide.md` - Terminal layouts
- `routines-guide.md` - Command aliases
- `mcp-configuration.md` - MCP servers
- `tunnel-configuration.md` - Cloudflared tunnels
