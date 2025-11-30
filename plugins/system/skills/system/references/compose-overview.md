# Docker Compose Configuration Overview

## Introduction

This document explains how Docker Compose is configured and used within Ghostmind's development system. Docker Compose is **exclusively used for local development** and provides a consistent way to run applications in development environments.

## Core Concept: Development-Only Containerization

Docker Compose in Ghostmind's system:
- **Development only** - Never used for production deployments
- **Environment variable driven** - Uses `SRC` and `LOCALHOST_SRC` extensively
- **Meta.json configured** - Location and settings defined in meta configuration
- **Hot reload enabled** - Source code mounted for live development

## Compose Configuration in meta.json

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

The Compose configuration is defined under the `compose` property in `meta.json`:

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

### Configuration Properties

#### `root` (required)
- **Purpose**: Specifies the directory where compose files are located
- **Example**: `"root": "local"`
- **Result**: Compose files are in `/path/to/project/local/`
- **Common values**: `"local"`, `"compose"`, `"dev"`

#### `filename` (optional)
- **Purpose**: Custom compose filename
- **Default**: `docker-compose.yaml` if not specified
- **Example**: `"filename": "compose.yaml"`
- **Result**: Uses `/path/to/project/local/compose.yaml`

**For complete `compose` property structure:** Fetch the schema

## Critical Environment Variables Usage

### File and Directory References

**All paths in compose files MUST use the `SRC` environment variable:**

```yaml
services:
  app:
    build:
      context: ${SRC}/app                    # ✅ Build context
      dockerfile: ${SRC}/docker/Dockerfile.dev  # ✅ Dockerfile location
    env_file:
      - ${SRC}/.env.base                     # ✅ Environment files
      - ${SRC}/.env.local
```

### Volume Mounting

**Volume mounting MUST use `LOCALHOST_SRC` for host paths:**

```yaml
services:
  app:
    volumes:
      - ${LOCALHOST_SRC}/app:/app/app        # ✅ Host path uses LOCALHOST_SRC
      - ${LOCALHOST_SRC}/data:/app/data      # ✅ Correct for dev container
```

**Why this is critical:**
- Dev containers run inside Docker
- Volume mounts need **host machine paths**, not container paths
- `SRC` = container path, `LOCALHOST_SRC` = host path

### Environment Variable Injection

```yaml
services:
  app:
    environment:
      LOCALHOST_SRC: ${LOCALHOST_SRC}        # ✅ Pass to container
      SRC: ${SRC}                           # ✅ Container operations
```

## Standard Environment Files

Compose configurations reference two environment files:

### `.env.base`
- **Purpose**: Shared environment variables across all environments
- **Contains**: Common configuration, defaults
- **Usage**: `env_file: - ${SRC}/.env.base`

### `.env.local`
- **Purpose**: Local development specific variables
- **Contains**: Development overrides, local secrets
- **Usage**: `env_file: - ${SRC}/.env.local`

## Complete Example

Based on the current project structure:

### meta.json Configuration
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

### compose.yaml Example
```yaml
services:
  app:
    container_name: doc-mcp
    build:
      context: ${SRC}/app
      dockerfile: ${SRC}/docker/Dockerfile.dev
      args:
        LOCAL: 'true'
    env_file:
      - ${SRC}/.env.base
      - ${SRC}/.env.local
    ports:
      - ${PORT}:${PORT}
    environment:
      APP: ${APP}
      LOCALHOST_SRC: ${LOCALHOST_SRC}
      DENO_ENV: development
    volumes:
      - ${LOCALHOST_SRC}/app:/app/app
    command: ['npm', 'run', 'dev']
```

## Multiple Compose Configurations

You can define multiple compose setups for different purposes:

```json
{
  "compose": {
    "app": {
      "root": "local/app",
      "filename": "compose.yaml"
    },
    "database": {
      "root": "local/db",
      "filename": "db-compose.yaml"
    },
    "full": {
      "root": "local",
      "filename": "full-stack.yaml"
    }
  }
}
```

## Integration with Docker Configuration

Compose files reference Docker configurations from meta.json:

```yaml
# Compose references Docker image built from meta.json docker config
services:
  app:
    build:
      context: ${SRC}/app                    # References docker.context_dir
      dockerfile: ${SRC}/docker/Dockerfile.dev  # References docker.root + env file
```

## Common Patterns

### Single Service Development
```yaml
services:
  app:
    build:
      context: ${SRC}/app
      dockerfile: ${SRC}/docker/Dockerfile.dev
    volumes:
      - ${LOCALHOST_SRC}/app:/app/app
    env_file:
      - ${SRC}/.env.base
      - ${SRC}/.env.local
```

### Multi-Service Development
```yaml
services:
  api:
    build:
      context: ${SRC}/services/api
      dockerfile: ${SRC}/docker/api/Dockerfile.dev
    volumes:
      - ${LOCALHOST_SRC}/services/api:/app/api

  worker:
    build:
      context: ${SRC}/services/worker
      dockerfile: ${SRC}/docker/worker/Dockerfile.dev
    volumes:
      - ${LOCALHOST_SRC}/services/worker:/app/worker
```

### External Services Integration
```yaml
services:
  app:
    build:
      context: ${SRC}/app
      dockerfile: ${SRC}/docker/Dockerfile.dev
    depends_on:
      - postgres
      - redis

  postgres:
    image: postgres:15
    environment:
      POSTGRES_DB: ${DB_NAME}
    volumes:
      - ${LOCALHOST_SRC}/data/postgres:/var/lib/postgresql/data

  redis:
    image: redis:7-alpine
```

## Best Practices

1. **Always use environment variables** for paths (`SRC`, `LOCALHOST_SRC`)
2. **Use LOCALHOST_SRC for volume mounts** to ensure proper dev container operation
3. **Reference environment files** with `${SRC}` prefix
4. **Keep compose files in dedicated directories** (usually `local/`)
5. **Use development-specific Dockerfiles** (e.g., `Dockerfile.dev`)
6. **Mount source code for hot reload** during development

## Integration with `run` Tool

The `run` tool uses compose configuration to:

1. **Locate compose files**: Uses `root` property from meta.json
2. **Set environment context**: Injects `SRC` and `LOCALHOST_SRC`
3. **Load environment files**: Automatically references `.env.base` and `.env.local`
4. **Orchestrate development**: Provides commands for dev environment management

## Key Differences from Production

| Aspect | Development (Compose) | Production (Terraform) |
|--------|----------------------|------------------------|
| **Purpose** | Local development | Cloud deployment |
| **Environment** | Dev container | Google Cloud Run |
| **Files** | `compose.yaml` | Terraform configs |
| **Volumes** | Source code mounting | No direct mounting |
| **Hot reload** | Enabled | Not applicable |

This development-focused approach enables rapid iteration while maintaining consistency with the production deployment architecture defined in Terraform configurations.