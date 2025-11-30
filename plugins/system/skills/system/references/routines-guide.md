# Routines Guide

## Introduction

Routines are **named shell command aliases** defined in `meta.json`. They provide quick access to frequently used commands through memorable names, eliminating the need to type long command sequences repeatedly.

## What Are Routines?

Routines are:
- Simple key-value pairs mapping names to shell commands
- Defined in `meta.json` under the `routines` property
- Executed via `run routine <name>`
- Any valid shell command or combination of commands

**Key Difference from Custom Scripts:**
- **Routines** = Simple shell command aliases (no logic, no conditionals)
- **Custom Scripts** = Full TypeScript programs with logic, loops, error handling

## meta.json Configuration

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

### Basic Configuration

```json
{
  "routines": {
    "dev": "run custom dev build up",
    "deploy": "run docker build && run docker push && run terraform apply",
    "tmux_init": "run tmux init session-name --all",
    "logs": "run custom logs"
  }
}
```

**Structure:**

**`routines.<name>` (string)**
- `<name>`: Memorable routine name (e.g., `dev`, `deploy`, `tmux_init`)
- Value: Any shell command or command chain

**For complete `routines` property structure:** Fetch the schema

## Execution

```bash
# Execute routine by name
run routine <name>

# Examples
run routine dev
run routine deploy
run routine tmux_init
```

## Common Patterns

### Development Workflows

```json
{
  "routines": {
    "dev": "run custom dev build up",
    "dev_stop": "run compose down"
  }
}
```

### Tmux Management

```json
{
  "routines": {
    "tmux_init": "run tmux init session-name --all",
    "tmux_attach": "run tmux attach session-name",
    "tmux_start": "run tmux attach session-name --run-all",
    "tmux_terminate": "run tmux terminate session-name"
  }
}
```

### Deployment

```json
{
  "routines": {
    "deploy": "run docker build && run docker push && run terraform apply",
    "deploy_fast": "run docker push && run terraform apply"
  }
}
```

### Tunnels and MCP

```json
{
  "routines": {
    "tunnel_start": "run tunnel run --all --name project-tunnels",
    "mcp_set": "run mcp set --all"
  }
}
```

### Combined Commands

```json
{
  "routines": {
    "setup": "run vault import && run tmux init app --all && run routine dev"
  }
}
```

## Invoking Other run Commands

Routines can execute any `run` command:

```json
{
  "routines": {
    "dev": "run custom dev build up",           // Custom script
    "deploy": "run terraform apply",            // Direct command
    "tunnel": "run tunnel run --name default",  // Tunnel command
    "init": "run routine mcp_set && run routine dev"  // Other routines
  }
}
```

## Chaining Commands

Use shell operators to chain multiple commands:

**Sequential (&&) - Stop on error:**
```json
{
  "routines": {
    "deploy": "run docker build && run docker push && run terraform apply"
  }
}
```

**Sequential (;) - Continue on error:**
```json
{
  "routines": {
    "cleanup": "run compose down; run docker system prune -f"
  }
}
```

**Parallel (&) - Run simultaneously:**
```json
{
  "routines": {
    "dev_all": "run custom ui build up & run custom api build up"
  }
}
```

## When to Use Routines

**Use routines when:**
- Simple command aliases needed
- No logic or conditionals required
- Frequently used command combinations
- Quick access to common workflows

**Use custom scripts when:**
- Complex logic needed (if/else, loops)
- Error handling required
- Multiple steps with conditionals
- Need TypeScript/Deno capabilities

## Integration with Custom Scripts

Routines often invoke custom scripts for complex workflows:

```json
{
  "custom": {
    "root": "scripts"
  },
  "routines": {
    "dev": "run custom dev build up",
    "deploy": "run custom deploy deploy check",
    "migrate": "run custom migrate apply metadata"
  }
}
```

**Benefits:**
- **Routines** = Short, memorable names
- **Custom Scripts** = Complex implementation

## Real-World Examples

### Full Development Setup

```json
{
  "routines": {
    "dev": "run custom dev build up",
    "dev_stop": "run compose down",
    "dev_reset": "run compose down && run custom dev build up"
  }
}
```

### Complete Deployment Pipeline

```json
{
  "routines": {
    "deploy": "run docker build && run docker push && run terraform apply",
    "deploy_rollback": "run terraform destroy && run terraform apply"
  }
}
```

### Multi-App Project

```json
{
  "routines": {
    "tmux_init": "run tmux init project --all",
    "tmux_attach": "run tmux attach project",
    "tmux_terminate": "run tmux terminate project",
    "tunnels_start": "run tunnel run --all --name project",
    "mcp_set": "run mcp set --all"
  }
}
```

## Best Practices

### 1. Use Descriptive Names

```json
// ✅ Good - clear purpose
{
  "routines": {
    "dev_start": "run custom dev build up",
    "dev_stop": "run compose down"
  }
}

// ❌ Avoid - unclear
{
  "routines": {
    "d": "run custom dev build up",
    "x": "run compose down"
  }
}
```

### 2. Group Related Routines

```json
{
  "routines": {
    // Development
    "dev": "run custom dev build up",
    "dev_stop": "run compose down",

    // Tmux
    "tmux_init": "run tmux init app --all",
    "tmux_attach": "run tmux attach app",

    // Deployment
    "deploy": "run custom deploy",
    "deploy_logs": "run custom logs"
  }
}
```

### 3. Use && for Critical Sequences

```json
// ✅ Good - stops on error
{
  "routines": {
    "deploy": "run docker build && run docker push && run terraform apply"
  }
}

// ❌ Risky - continues on error
{
  "routines": {
    "deploy": "run docker build; run docker push; run terraform apply"
  }
}
```

### 4. Keep Routines Simple

```json
// ✅ Good - simple alias
{
  "routines": {
    "dev": "run custom dev build up"
  }
}

// ❌ Too complex - use custom script instead
{
  "routines": {
    "dev": "if [ -f .env ]; then run vault import; fi && run custom dev build up && run tunnel run --name default"
  }
}
```

### 5. Reference Other Routines When Useful

```json
{
  "routines": {
    "dev": "run custom dev build up",
    "tunnel": "run tunnel run --name default",
    "full_dev": "run routine dev && run routine tunnel"
  }
}
```

## Troubleshooting

### "Routine not found"

**Problem:** Running `run routine dev` but no `dev` routine exists

**Solution:** Check `meta.json` routines property for correct name

### Command fails silently

**Problem:** Routine executes but doesn't stop on error

**Solution:** Use `&&` instead of `;` to stop on first error

### Variable substitution not working

**Problem:** `${PORT}` in routine not expanding

**Solution:** Environment variables in routines are evaluated by the shell, ensure they're exported

## Next Steps

- **Understanding meta.json:** See `meta-json-guide.md`
- **Custom Scripts:** See `custom-scripts-guide.md`
- **run CLI:** See `run-cli-overview.md`
- **System overview:** See `system-overview.md`

**Remember:** Routines are for simple aliases. For complex workflows with logic, use custom scripts.
