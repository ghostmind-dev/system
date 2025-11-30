# Tunnel Configuration Guide

## Introduction

Tunnels expose local development servers through public URLs using Cloudflare tunnels. This is essential for testing OAuth callbacks, webhooks, and sharing local development environments without deploying to production.

## What Are Tunnels?

Cloudflared tunnels provide:
- **Public URLs** for local services (e.g., `https://app.example.com` → `http://localhost:5001`)
- **OAuth callback testing** - Required for authentication flows
- **Webhook development** - Test external services calling your local app
- **Local environment sharing** - Share work-in-progress with team

## meta.json Configuration

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

### Basic Configuration

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

**Structure:**

**`tunnel.<name>` (object)**
- `<name>`: Tunnel identifier (e.g., `default`, `api`, `webhooks`)
- Value: Tunnel configuration object

**For complete `tunnel` property structure:** Fetch the schema

## Tunnel Properties

### hostname (string)

Public domain name for the tunnel:

```json
{
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app"
    }
  }
}
```

Common patterns:
- `"app.example.com"` - Subdomain
- `"localhost.run"` - Development domain
- `"example.com"` - Root domain

### service (string)

Local service URL to expose:

```json
{
  "tunnel": {
    "default": {
      "service": "http://localhost:5001"
    }
  }
}
```

Format: `http://localhost:<port>`

### Using Variable Substitution

Reference port from `meta.json`:

```json
{
  "port": 5001,
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app",
      "service": "http://localhost:${PORT}"
    }
  }
}
```

## Execution

```bash
# Start specific tunnel
run tunnel run --name default

# Start all tunnels
run tunnel run --all

# Start all tunnels with custom session name
run tunnel run --all --name my-tunnels
```

## Multiple Tunnels

Configure multiple tunnels for different services:

```json
{
  "tunnel": {
    "ui": {
      "hostname": "app.example.com",
      "service": "http://localhost:5001"
    },
    "api": {
      "hostname": "api.example.com",
      "service": "http://localhost:3000"
    },
    "webhooks": {
      "hostname": "webhooks.example.com",
      "service": "http://localhost:8080"
    }
  }
}
```

**Start all:**
```bash
run tunnel run --all
```

## Integration with Routines

Common pattern for tunnel management:

```json
{
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app",
      "service": "http://localhost:5001"
    }
  },
  "routines": {
    "tunnel_start": "run tunnel run --all --name project-tunnels",
    "dev_full": "run routine dev && run routine tunnel_start"
  }
}
```

**Usage:**
```bash
run routine tunnel_start
```

## Integration with Environment Variables

Use tunnels in `.env` files:

**meta.json:**
```json
{
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app",
      "service": "http://localhost:${PORT}"
    }
  }
}
```

**.env.local:**
```bash
TUNNEL_NAME="ghostmind.app"
NEXTAUTH_URL="https://${TUNNEL_NAME}"
PUBLIC_URL="https://${TUNNEL_NAME}"
```

## Real-World Examples

### Single Application

```json
{
  "port": 5001,
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app",
      "service": "http://localhost:${PORT}"
    }
  }
}
```

### Multi-Service Application

```json
{
  "tunnel": {
    "frontend": {
      "hostname": "city.ghostmind.app",
      "service": "http://localhost:5001"
    },
    "api": {
      "hostname": "api-city.ghostmind.app",
      "service": "http://localhost:3000"
    }
  }
}
```

### Development + Staging

```json
{
  "tunnel": {
    "dev": {
      "hostname": "dev.ghostmind.app",
      "service": "http://localhost:5001"
    },
    "staging": {
      "hostname": "staging.ghostmind.app",
      "service": "http://localhost:5002"
    }
  }
}
```

## Use Cases

### OAuth Authentication

**Problem:** OAuth providers require public callback URLs

**Solution:**
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

**.env.local:**
```bash
NEXTAUTH_URL="https://app.example.com"
```

Now OAuth callbacks work with local development.

### Webhook Testing

**Problem:** External services need to call your local app

**Solution:**
```json
{
  "tunnel": {
    "webhooks": {
      "hostname": "webhooks.example.com",
      "service": "http://localhost:8080"
    }
  }
}
```

Configure webhook URL as `https://webhooks.example.com` in external service.

### Team Sharing

**Problem:** Need to share local work-in-progress

**Solution:**
```bash
run tunnel run --name default
```

Share `https://app.example.com` with team members.

## Integration with Tmux

Common pattern in tmux configurations:

```json
{
  "tunnel": {
    "default": {
      "hostname": "ghostmind.app",
      "service": "http://localhost:5001"
    }
  },
  "tmux": {
    "sessions": [
      {
        "name": "dev",
        "windows": [
          {
            "name": "services",
            "layout": "compact",
            "compact": {
              "type": "vertical",
              "panes": {
                "server": "run custom dev build up",
                "tunnel": "sleep 8 && run tunnel run --name default"
              }
            }
          }
        ]
      }
    ]
  }
}
```

The tunnel starts automatically when tmux session initializes.

## Best Practices

### 1. Use Variable Substitution for Ports

```json
// ✅ Good - DRY
{
  "port": 5001,
  "tunnel": {
    "default": {
      "service": "http://localhost:${PORT}"
    }
  }
}

// ❌ Avoid - hardcoded
{
  "port": 5001,
  "tunnel": {
    "default": {
      "service": "http://localhost:5001"
    }
  }
}
```

### 2. Use Descriptive Tunnel Names

```json
// ✅ Good - clear purpose
{
  "tunnel": {
    "frontend": { ... },
    "api": { ... },
    "webhooks": { ... }
  }
}

// ❌ Avoid - unclear
{
  "tunnel": {
    "tunnel1": { ... },
    "t2": { ... }
  }
}
```

### 3. Integrate with Routines

```json
{
  "tunnel": { ... },
  "routines": {
    "tunnel_start": "run tunnel run --all",
    "dev_with_tunnel": "run routine dev && run routine tunnel_start"
  }
}
```

### 4. Add Delay in Tmux

Allow service to start before tunnel:

```json
{
  "tmux": {
    "sessions": [{
      "windows": [{
        "panes": {
          "server": "run custom dev up",
          "tunnel": "sleep 8 && run tunnel run --name default"  // Wait 8s
        }
      }]
    }]
  }
}
```

## Troubleshooting

### Tunnel fails to connect

**Problem:** `run tunnel run --name default` fails

**Solution:**
- Verify hostname is correct
- Check local service is running on specified port
- Ensure Cloudflared is configured properly

### OAuth callbacks fail

**Problem:** OAuth redirect doesn't work

**Solution:**
- Verify `NEXTAUTH_URL` uses tunnel hostname
- Check OAuth provider callback URL matches tunnel hostname
- Ensure tunnel is running before testing OAuth

### Port already in use

**Problem:** Tunnel can't connect because port is occupied

**Solution:**
- Stop other services using the port
- Change port in `meta.json` and restart services

## Next Steps

- **Understanding meta.json:** See `meta-json-guide.md`
- **run CLI:** See `run-cli-overview.md`
- **Routines:** See `routines-guide.md`
- **Tmux integration:** See `tmux-guide.md`
- **System overview:** See `system-overview.md`

**Remember:** Tunnels are essential for OAuth, webhooks, and local environment sharing. Always start the tunnel after your local service is running.
