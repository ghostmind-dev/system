# Custom Scripts Guide

## Introduction

Custom scripts are **TypeScript/Deno files** that provide reusable workflows for project-specific operations. They allow you to create complex, multi-step operations using the full power of TypeScript and access to `run` library utilities.

## What Are Custom Scripts?

Custom scripts are:
- TypeScript files (`.ts`) executed by Deno runtime
- Located in a directory defined in `meta.json`
- Reusable workflows for development, deployment, testing, and maintenance
- Composable operations combining `run` utilities with any Deno-compatible libraries

**Key Difference from Routines:**
- **Routines** = Simple shell command aliases
- **Custom Scripts** = Full TypeScript programs with logic, conditionals, loops, error handling

## meta.json Configuration

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

### Basic Configuration

```json
{
  "custom": {
    "root": "scripts"
  }
}
```

**Properties:**

**`custom.root` (string)**
- Directory containing `.ts` script files
- Common values: `"scripts"`, `"custom"`, `"workflows"`
- All `.ts` files in this directory become executable via `run custom <name>`

**For complete `custom` property structure:** Fetch the schema

## Script Structure

### Required Structure

Every custom script must:
1. Be a `.ts` file in the `custom.root` directory
2. Export a default function
3. Accept `CustomArgs` and `CustomOptions` parameters

**Minimal Example:**

```typescript
import type { CustomArgs, CustomOptions } from 'jsr:@ghostmind/run';

export default async function (args: CustomArgs, opts: CustomOptions) {
  console.log('Custom script executed!');
}
```

### Function Parameters

**CustomArgs** - Array of positional arguments
```typescript
// Execution: run custom myscript arg1 arg2
export default async function (args: CustomArgs, opts: CustomOptions) {
  console.log(args); // ['arg1', 'arg2']
}
```

**CustomOptions** - Named flags via `has()` method
```typescript
export default async function (args: CustomArgs, opts: CustomOptions) {
  const { has } = opts;

  if (has('build')) {
    // Build logic
  }

  if (has('deploy')) {
    // Deploy logic
  }
}
```

**Usage with flags:**
```bash
run custom dev build deploy
# has('build') = true
# has('deploy') = true
```

## Available Utilities

Custom scripts can import utilities from `jsr:@ghostmind/run`:

```typescript
import {
  dockerBuild,
  dockerPush,
  dockerComposeBuild,
  dockerComposeUp,
  terraformApply,
} from 'jsr:@ghostmind/run';
```

**Note:** For the complete list of available functions, check the `@ghostmind/run` package or source code.

## External Libraries

Custom scripts can use any Deno-compatible library:

**Shell commands with zx:**
```typescript
import { $ } from 'npm:zx@8.1.3';

export default async function (args: CustomArgs, opts: CustomOptions) {
  $.verbose = true;
  await $`npm install`;
  await $`npm run build`;
}
```

**Node.js modules:**
```typescript
import { readFile } from 'node:fs/promises';
```

**npm packages:**
```typescript
import chalk from 'npm:chalk@5';
```

## Execution

```bash
# Execute script by name (without .ts extension)
run custom script-name

# Execute with flags
run custom dev build up
```

The script name matches the filename:
- `scripts/dev.ts` → `run custom dev`
- `scripts/deploy.ts` → `run custom deploy`
- `scripts/migrate.ts` → `run custom migrate`

## Simple Example

**File:** `scripts/dev.ts`

```typescript
import type { CustomArgs, CustomOptions } from 'jsr:@ghostmind/run';
import { dockerComposeBuild, dockerComposeUp } from 'jsr:@ghostmind/run';

export default async function (args: CustomArgs, opts: CustomOptions) {
  const { has } = opts;

  if (has('build')) {
    await dockerComposeBuild({});
  }

  if (has('up')) {
    await dockerComposeUp({ forceRecreate: true });
  }
}
```

**Usage:**
```bash
run custom dev build up
```

## Integration with Routines

Custom scripts work well with routines for frequently used workflows:

**meta.json:**
```json
{
  "custom": {
    "root": "scripts"
  },
  "routines": {
    "dev": "run custom dev build up",
    "deploy": "run custom deploy"
  }
}
```

**Usage:**
```bash
# Via routine (short)
run routine dev

# Direct custom script (explicit)
run custom dev build up
```

## When to Use Custom Scripts

**Use custom scripts when:**
- Complex multi-step workflows
- Conditional logic needed (if/else, loops)
- Error handling required
- Combining multiple operations
- Need full TypeScript/Deno capabilities

**Use routines when:**
- Simple command aliases
- No logic needed
- Just executing shell commands

## Best Practices

1. **Use type imports** for CustomArgs/CustomOptions
2. **Use meaningful script names** (dev.ts, deploy.ts, migrate.ts)
3. **Handle errors gracefully** with try/catch
4. **Use flags** for optional steps (`has('build')`, `has('deploy')`)
5. **Document complex scripts** with comments

## Troubleshooting

**Script not found:**
```bash
# Error: Script 'mysc' not found
# Solution: Check spelling and file exists in custom.root directory
```

**Import errors:**
```typescript
// ❌ Wrong
import { something } from '@ghostmind/run';

// ✅ Correct
import { something } from 'jsr:@ghostmind/run';
```

## Next Steps

- **Understanding meta.json:** See `meta-json-guide.md`
- **run CLI commands:** See `run-cli-overview.md`
- **Routines vs Custom Scripts:** See `routines-guide.md`
- **System overview:** See `system-overview.md`

**Remember:** The majority of the time, you don't need to know the internal implementation of custom functions. Focus on understanding:
1. How to configure `custom` in meta.json
2. Basic script structure
3. How to execute scripts with `run custom`
