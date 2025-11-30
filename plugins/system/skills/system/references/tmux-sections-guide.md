# Tmux Layout Guide

## Introduction

Tmux layouts in the Ghostmind system are configured in `meta.json` and provide reproducible terminal session configurations for development workflows.

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

**For complete `tmux` property structure:** Fetch the schema

The **Tmux Layout System** provides three powerful ways to create tmux layouts:

1. **Compact Layout** - Minimal object-based configuration (recommended for most use cases)
2. **Grid Layout** - Simplified predefined arrangements
3. **Section Layout** - Hierarchical configuration for complex custom layouts

## Path Configuration

You can configure working directories at multiple levels with automatic inheritance and override:

### Path Resolution Rules

1. **Absolute paths** (starting with `/`) are used as-is
2. **Relative paths** are resolved relative to their parent:
   - Pane paths are relative to window path (or session root if no window path)
   - Window paths are relative to session root
3. **Child paths override parent paths** (pane path > window path > session root)

### Examples

```json
{
  "tmux": {
    "sessions": [{
      "name": "dev",
      "root": "projects/myapp",  // Session root
      "windows": [{
        "name": "backend",
        "path": "api",            // Relative to session root: projects/myapp/api
        "layout": "compact",
        "compact": {
          "type": "vertical",
          "panes": {
            "server": "npm start",     // Runs in: projects/myapp/api
            "tests": "npm test"        // Runs in: projects/myapp/api
          }
        }
      }, {
        "name": "frontend",
        "path": "/home/user/frontend",  // Absolute path
        "layout": "compact",
        "compact": {
          "type": "vertical",
          "panes": {
            "dev": "npm run dev",      // Runs in: /home/user/frontend
            "build": "npm run build"   // Runs in: /home/user/frontend
          }
        }
      }]
    }]
  }
}
```

## Compact Layout (Recommended)

Compact layouts provide the simplest, most readable configuration format. Define your panes as key-value pairs where the key is the pane name and the value is the command - that's it!

### Available Grid Types

- **`single`** - Single pane (1 pane)
- **`vertical`** - Two panes split left/right (2 panes)
- **`horizontal`** - Two panes split top/bottom (2 panes)
- **`two-by-two`** - Four panes in 2x2 grid (4 panes)
- **`main-side`** - One large pane (66%) on left, two stacked panes (34%) on right (3 panes)

### Basic Compact Structure

```json
{
  "layout": "compact",
  "compact": {
    "type": "vertical",
    "panes": {
      "editor": "nvim",
      "terminal": "npm run dev"
    }
  }
}
```

### Key Features

- **Ultra-minimal syntax**: Just name and command
- **Pane names become titles**: Automatically used as tmux pane titles
- **Auto-fill support**: Missing panes are auto-generated
- **Predictable order**: Panes fill from top-left to bottom-right
- **Window-level path support**: Set `path` at window level to control starting directory for all panes

**Note**: Compact layout doesn't support pane-level paths since panes are simple name:command pairs. Use Grid or Section layout if you need per-pane path control.

### Pane Ordering

Panes are created in this order for each grid type:

- **`two-by-two`**: Top-left → Top-right → Bottom-left → Bottom-right
- **`main-side`**: Main (left) → Top-right → Bottom-right
- **`vertical`**: Left → Right
- **`horizontal`**: Top → Bottom

### Auto-Fill Behavior

If you define fewer panes than the grid type expects:

- Missing panes are auto-created with names like `pane-0`, `pane-1`, etc.
- You'll see a warning showing how many panes were auto-filled

If you define more panes than the grid type expects:

- Only the first N panes are used (where N = expected count)
- You'll see a warning about extra panes being ignored

### Compact Layout Examples

#### Single Pane

```json
{
  "name": "main-window",
  "layout": "compact",
  "compact": {
    "type": "single",
    "panes": {
      "terminal": "bash"
    }
  }
}
```

#### Vertical Split (Side-by-Side)

```json
{
  "name": "dev-window",
  "layout": "compact",
  "compact": {
    "type": "vertical",
    "panes": {
      "editor": "nvim",
      "terminal": "npm run dev"
    }
  }
}
```

With window-level path:

```json
{
  "name": "dev-window",
  "path": "src",              // All panes start in src/
  "layout": "compact",
  "compact": {
    "type": "vertical",
    "panes": {
      "editor": "nvim",       // Runs in: src/
      "terminal": "npm run dev"  // Runs in: src/
    }
  }
}
```

#### Horizontal Split (Top/Bottom)

```json
{
  "name": "logs-window",
  "layout": "compact",
  "compact": {
    "type": "horizontal",
    "panes": {
      "app-logs": "tail -f logs/app.log",
      "error-logs": "tail -f logs/error.log"
    }
  }
}
```

#### Two-by-Two Grid

```json
{
  "name": "monitoring",
  "layout": "compact",
  "compact": {
    "type": "two-by-two",
    "panes": {
      "top-left": "htop",
      "top-right": "docker stats",
      "bottom-left": "tail -f logs/access.log",
      "bottom-right": "tail -f logs/error.log"
    }
  }
}
```

Layout:

```
┌─────────────┬─────────────┐
│  top-left   │  top-right  │
│             │             │
├─────────────┼─────────────┤
│ bottom-left │bottom-right │
│             │             │
└─────────────┴─────────────┘
```

#### Main-Side Layout

```json
{
  "name": "ide-window",
  "layout": "compact",
  "compact": {
    "type": "main-side",
    "panes": {
      "editor": "nvim",
      "terminal": "bash",
      "logs": "tail -f logs/dev.log"
    }
  }
}
```

Layout:

```
┌──────────────────┬──────────┐
│                  │ terminal │
│                  ├──────────┤
│     editor       │   logs   │
│                  │          │
└──────────────────┴──────────┘
```

#### Execution Shell Pattern (Common for AI Assistance)

```json
{
  "name": "server",
  "layout": "compact",
  "compact": {
    "type": "main-side",
    "panes": {
      "nodejs": "run custom dev build up",
      "tunnel": "run tunnel run",
      "execution-shell": "echo Ready for commands"
    }
  }
}
```

The `execution-shell` pane is left empty (just echoes a message) so AI assistants can use it for running commands without interrupting long-running processes.

#### Auto-Fill Example

```json
{
  "layout": "compact",
  "compact": {
    "type": "two-by-two",
    "panes": {
      "api": "npm start",
      "db": "docker-compose up"
      // Auto-fills pane-2 and pane-3
    }
  }
}
```

---

## Grid Layout

Grid layouts provide predefined, easy-to-use window arrangements with more control than compact layouts. Choose a grid type and define your panes with full pane objects - the system handles all the splitting logic automatically.

### Available Grid Types

- **`single`** - Single pane (1 pane)
- **`vertical`** - Two panes split left/right (2 panes)
- **`horizontal`** - Two panes split top/bottom (2 panes)
- **`two-by-two`** - Four panes in 2x2 grid (4 panes)
- **`main-side`** - One large pane (66%) on left, two stacked panes (34%) on right (3 panes)

### Basic Grid Structure

```json
{
  "layout": "grid",
  "grid": {
    "type": "vertical",
    "panes": [
      {
        "name": "left",
        "command": "nvim"
      },
      {
        "name": "right",
        "command": "npm run dev"
      }
    ]
  }
}
```

Grid layouts also support **window-level and pane-level paths**:

```json
{
  "name": "dev-window",
  "path": "src",              // All panes start in src/ by default
  "layout": "grid",
  "grid": {
    "type": "vertical",
    "panes": [
      {
        "name": "editor",
        "command": "nvim"       // Runs in: src/
      },
      {
        "name": "tests",
        "path": "tests",        // Overrides: src/tests/
        "command": "npm test"
      }
    ]
  }
}
```

### Auto-Fill Feature

Grid layouts support **auto-fill** - you don't need to define all panes. Missing panes are automatically created with default names (`pane-0`, `pane-1`, etc.).

```json
{
  "layout": "grid",
  "grid": {
    "type": "two-by-two",
    "panes": [
      {
        "name": "api",
        "command": "npm start"
      },
      {
        "name": "db",
        "command": "docker-compose up"
      }
      // Auto-fills pane-2 and pane-3
    ]
  }
}
```

### Grid Layout Examples

#### Single Pane

```json
{
  "name": "main-window",
  "layout": "grid",
  "grid": {
    "type": "single",
    "panes": [
      {
        "name": "terminal"
      }
    ]
  }
}
```

#### Vertical Split (Side-by-Side)

```json
{
  "name": "dev-window",
  "layout": "grid",
  "grid": {
    "type": "vertical",
    "panes": [
      {
        "name": "editor",
        "command": "nvim"
      },
      {
        "name": "terminal",
        "command": "npm run dev"
      }
    ]
  }
}
```

#### Horizontal Split (Top/Bottom)

```json
{
  "name": "logs-window",
  "layout": "grid",
  "grid": {
    "type": "horizontal",
    "panes": [
      {
        "name": "app-logs",
        "command": "tail -f logs/app.log"
      },
      {
        "name": "error-logs",
        "command": "tail -f logs/error.log"
      }
    ]
  }
}
```

#### Two-by-Two Grid

```json
{
  "name": "monitoring",
  "layout": "grid",
  "grid": {
    "type": "two-by-two",
    "panes": [
      {
        "name": "top-left",
        "command": "htop"
      },
      {
        "name": "top-right",
        "command": "docker stats"
      },
      {
        "name": "bottom-left",
        "command": "tail -f logs/access.log"
      },
      {
        "name": "bottom-right",
        "command": "tail -f logs/error.log"
      }
    ]
  }
}
```

Layout:

```
┌─────────────┬─────────────┐
│  top-left   │  top-right  │
│             │             │
├─────────────┼─────────────┤
│ bottom-left │bottom-right │
│             │             │
└─────────────┴─────────────┘
```

#### Main-Side Layout

```json
{
  "name": "ide-window",
  "layout": "grid",
  "grid": {
    "type": "main-side",
    "panes": [
      {
        "name": "editor",
        "command": "nvim"
      },
      {
        "name": "terminal",
        "command": "bash"
      },
      {
        "name": "logs",
        "command": "tail -f logs/dev.log"
      }
    ]
  }
}
```

Layout:

```
┌──────────────────┬──────────┐
│                  │ terminal │
│                  ├──────────┤
│     editor       │   logs   │
│                  │          │
└──────────────────┴──────────┘
```

---

## Section Layout (Advanced)

The **Section Layout System** provides an intuitive and powerful way to create complex custom tmux layouts using hierarchical configuration. Think of it as building blocks where you define how to split space and what goes in each section.

## Core Concepts

### Sections

A **section** defines how to split space and contains **items**. Every section has:

- `split`: Direction to split (`"horizontal"` or `"vertical"`)
- `items`: Array of panes or nested sections
- `size`: Optional size specification (e.g., `"50%"`, `"30"`)

### Items

**Items** are what go inside sections. They can be:

- **Panes**: Terminal windows with commands
- **Sections**: Nested sections with their own split and items

## Basic Structure

```json
{
  "layout": "sections",
  "section": {
    "split": "vertical",
    "items": [
      {
        "name": "left-pane",
        "command": "echo 'Left Side'",
        "size": "30%"
      },
      {
        "name": "right-pane",
        "command": "echo 'Right Side'",
        "size": "70%"
      }
    ]
  }
}
```

**Required Properties:**

- `layout`: Must be `"sections"`
- `section`: The root section defining your layout

## Split Directions

- **`"vertical"`**: Split left/right (creates columns)
- **`"horizontal"`**: Split top/bottom (creates rows)

## Pane Configuration

Each pane supports:

```json
{
  "name": "unique-pane-name",
  "command": "echo 'Hello World'",
  "path": "relative/path/or/absolute",
  "sshTarget": "user@hostname",
  "size": "50%"
}
```

### Properties

- **`name`** (required): Unique identifier for the pane
- **`command`**: Command to execute when pane starts
- **`path`**: Starting directory. If starts with `/`, treated as absolute. Otherwise, relative to window path (or session root if no window path). **Overrides window-level path.**
- **`sshTarget`**: SSH target for remote execution
- **`size`**: Size of this pane within its parent section

### Path Override Example

```json
{
  "tmux": {
    "sessions": [{
      "name": "dev",
      "root": "/workspace",
      "windows": [{
        "name": "mixed-paths",
        "path": "backend",           // Window default: /workspace/backend
        "layout": "sections",
        "section": {
          "split": "vertical",
          "items": [{
            "name": "api",
            "command": "npm start"   // Uses window path: /workspace/backend
          }, {
            "name": "scripts",
            "path": "scripts",       // Relative to window: /workspace/backend/scripts
            "command": "bash"
          }, {
            "name": "logs",
            "path": "/var/log/app", // Absolute path overrides everything
            "command": "tail -f app.log"
          }]
        }
      }]
    }]
  }
}
```

## Size Specifications

Sizes can be specified as:

- **Percentage**: `"50%"`, `"33%"`, `"25%"`
- **Absolute**: `"30"`, `"20"` (tmux units)

**Important**: Sizes should add up to 100% within each section for best results.

## Layout Examples

### Simple Two-Pane Split

```json
{
  "layout": "sections",
  "section": {
    "split": "vertical",
    "items": [
      {
        "name": "editor",
        "command": "nvim",
        "size": "70%"
      },
      {
        "name": "terminal",
        "command": "bash",
        "size": "30%"
      }
    ]
  }
}
```

### Three-Pane Horizontal Stack

```json
{
  "layout": "sections",
  "section": {
    "split": "horizontal",
    "items": [
      {
        "name": "top",
        "command": "htop",
        "size": "33%"
      },
      {
        "name": "middle",
        "command": "tail -f /var/log/app.log",
        "size": "33%"
      },
      {
        "name": "bottom",
        "command": "bash",
        "size": "34%"
      }
    ]
  }
}
```

### Nested Sections Example

```json
{
  "layout": "sections",
  "section": {
    "split": "vertical",
    "items": [
      {
        "name": "sidebar",
        "command": "ranger",
        "size": "25%"
      },
      {
        "split": "horizontal",
        "size": "75%",
        "items": [
          {
            "name": "editor",
            "command": "nvim",
            "size": "70%"
          },
          {
            "split": "vertical",
            "size": "30%",
            "items": [
              {
                "name": "terminal",
                "command": "bash",
                "size": "50%"
              },
              {
                "name": "logs",
                "command": "tail -f logs/app.log",
                "size": "50%"
              }
            ]
          }
        ]
      }
    ]
  }
}
```

This creates:

```
┌─────────┬───────────────────────────┐
│         │                           │
│ sidebar │         editor            │
│         │                           │
│         ├─────────────┬─────────────┤
│         │   terminal  │    logs     │
│         │             │             │
└─────────┴─────────────┴─────────────┘
```

### IDE-Style Layout

```json
{
  "layout": "sections",
  "section": {
    "split": "horizontal",
    "items": [
      {
        "split": "vertical",
        "size": "80%",
        "items": [
          {
            "name": "file-explorer",
            "command": "ranger",
            "size": "20%"
          },
          {
            "name": "editor",
            "command": "nvim .",
            "size": "60%"
          },
          {
            "name": "preview",
            "command": "echo 'Preview Pane'",
            "size": "20%"
          }
        ]
      },
      {
        "split": "vertical",
        "size": "20%",
        "items": [
          {
            "name": "terminal",
            "command": "bash",
            "size": "50%"
          },
          {
            "name": "logs",
            "command": "tail -f logs/development.log",
            "size": "50%"
          }
        ]
      }
    ]
  }
}
```

### Development Environment

```json
{
  "layout": "sections",
  "section": {
    "split": "vertical",
    "items": [
      {
        "split": "horizontal",
        "size": "70%",
        "items": [
          {
            "name": "editor",
            "command": "nvim",
            "path": "src",
            "size": "70%"
          },
          {
            "split": "vertical",
            "size": "30%",
            "items": [
              {
                "name": "server",
                "command": "npm run dev",
                "size": "50%"
              },
              {
                "name": "tests",
                "command": "npm run test:watch",
                "size": "50%"
              }
            ]
          }
        ]
      },
      {
        "split": "horizontal",
        "size": "30%",
        "items": [
          {
            "name": "git",
            "command": "git status",
            "size": "50%"
          },
          {
            "name": "terminal",
            "command": "bash",
            "size": "50%"
          }
        ]
      }
    ]
  }
}
```

## Remote Development with SSH

```json
{
  "layout": "sections",
  "section": {
    "split": "vertical",
    "items": [
      {
        "name": "local-terminal",
        "command": "bash",
        "size": "50%"
      },
      {
        "split": "horizontal",
        "size": "50%",
        "items": [
          {
            "name": "remote-editor",
            "command": "nvim",
            "sshTarget": "user@server.com",
            "path": "/var/www/app",
            "size": "70%"
          },
          {
            "name": "remote-logs",
            "command": "tail -f /var/log/nginx/access.log",
            "sshTarget": "user@server.com",
            "size": "30%"
          }
        ]
      }
    ]
  }
}
```

## Design Principles

### 1. Hierarchical Thinking

Structure your layout like a tree:

- Root section defines the main split
- Each item can be a pane (leaf) or another section (branch)
- Nest as deeply as needed

### 2. Size Planning

- Start with major sections (e.g., 70% editor, 30% tools)
- Then subdivide sections as needed
- Ensure sizes add up to 100% in each section

### 3. Logical Grouping

- Group related functionality in the same section
- Use nested sections to create zones
- Keep frequently used panes easily accessible

## Common Patterns

### Two-Column Layout

```json
{
  "split": "vertical",
  "items": [
    { "name": "left", "size": "50%" },
    { "name": "right", "size": "50%" }
  ]
}
```

### Three-Row Layout

```json
{
  "split": "horizontal",
  "items": [
    { "name": "top", "size": "33%" },
    { "name": "middle", "size": "33%" },
    { "name": "bottom", "size": "34%" }
  ]
}
```

### Sidebar + Main Area

```json
{
  "split": "vertical",
  "items": [
    { "name": "sidebar", "size": "25%" },
    { "name": "main", "size": "75%" }
  ]
}
```

### Header + Body + Footer

```json
{
  "split": "horizontal",
  "items": [
    { "name": "header", "size": "10%" },
    { "name": "body", "size": "80%" },
    { "name": "footer", "size": "10%" }
  ]
}
```

## Best Practices

1. **Start Simple**: Begin with basic splits, then add complexity
2. **Use Meaningful Names**: Make pane names descriptive
3. **Plan Your Sizes**: Sketch the layout before coding
4. **Test Iteratively**: Use `tmux init <session>` to test changes
5. **Consider Workflows**: Design around how you actually work
6. **Document Complex Layouts**: Add comments explaining the structure

## Troubleshooting

### Layout Not As Expected

- Check that splits are correct (`horizontal` vs `vertical`)
- Verify sizes add up to 100%
- Ensure proper nesting structure

### Panes Too Small

- Adjust size percentages
- Consider removing nested levels
- Test on target terminal size

### Commands Not Running

- Check `command` syntax
- Verify `path` exists
- Test `sshTarget` connectivity

## Complete Working Examples

The examples above demonstrate real-world configuration patterns for:

- Development environments
- System monitoring setups
- Remote administration layouts
- Multi-project workflows

---

## Choosing Between Compact, Grid, and Section Layouts

### Use Compact Layout When:

✅ You want the simplest, most readable configuration
✅ You need standard arrangements (1-4 panes)
✅ You don't need custom pane properties (path, sshTarget, etc.)
✅ You're defining common development workflows
✅ You want pane names to automatically become titles

**Example**: Most development workflows fit perfectly into compact layouts.

```json
{
  "layout": "compact",
  "compact": {
    "type": "main-side",
    "panes": {
      "editor": "nvim",
      "terminal": "bash",
      "logs": "tail -f app.log"
    }
  }
}
```

### Use Grid Layout When:

✅ You need standard arrangements (1-4 panes)
✅ You need pane properties like `path` or `sshTarget`
✅ You want more control than compact but don't need custom splits
✅ You need to define pane-specific starting directories

**Example**: Development with remote execution or specific working directories.

```json
{
  "layout": "grid",
  "grid": {
    "type": "vertical",
    "panes": [
      {
        "name": "local",
        "command": "nvim",
        "path": "src"
      },
      {
        "name": "remote",
        "command": "npm run dev",
        "sshTarget": "prod-server"
      }
    ]
  }
}
```

### Use Section Layout When:

✅ You need custom split ratios (e.g., 70/30, 25/75)
✅ You need more than 4 panes
✅ You need complex nested arrangements
✅ You need precise control over layout structure
✅ Standard grids don't match your workflow

**Example**: IDE-style layouts with file explorer, editor, terminal, and multiple monitoring panes.

```json
{
  "layout": "sections",
  "section": {
    "split": "vertical",
    "items": [
      { "name": "sidebar", "size": "20%" },
      {
        "split": "horizontal",
        "size": "80%",
        "items": [
          { "name": "editor", "size": "70%" },
          { "name": "terminal", "size": "30%" }
        ]
      }
    ]
  }
}
```

### Recommendation

**Start with Compact Layout** for 90% of use cases. It provides the cleanest, most maintainable configuration.

**Upgrade to Grid Layout** when you need:

- Pane-specific properties (`path`, `sshTarget`)
- More verbose configuration for clarity

**Use Section Layout** only when you need:

- Custom split ratios
- More than 4 panes
- Complex nested arrangements

---

## Complete Session Configuration Example

### Using Compact Layouts (Recommended)

```json
{
  "tmux": {
    "sessions": [
      {
        "name": "dev",
        "windows": [
          {
            "name": "editor",
            "layout": "compact",
            "compact": {
              "type": "vertical",
              "panes": {
                "nvim": "nvim",
                "terminal": "bash"
              }
            }
          },
          {
            "name": "servers",
            "layout": "compact",
            "compact": {
              "type": "two-by-two",
              "panes": {
                "api": "npm run dev:api",
                "web": "npm run dev:web",
                "db": "docker-compose up postgres",
                "redis": "docker-compose up redis"
              }
            }
          },
          {
            "name": "monitoring",
            "layout": "compact",
            "compact": {
              "type": "main-side",
              "panes": {
                "logs": "tail -f logs/development.log",
                "htop": "htop",
                "docker": "docker stats"
              }
            }
          }
        ]
      }
    ]
  }
}
```

### Using Grid Layouts

```json
{
  "tmux": {
    "sessions": [
      {
        "name": "dev",
        "windows": [
          {
            "name": "editor",
            "layout": "grid",
            "grid": {
              "type": "vertical",
              "panes": [
                {
                  "name": "nvim",
                  "command": "nvim"
                },
                {
                  "name": "terminal"
                }
              ]
            }
          },
          {
            "name": "servers",
            "layout": "grid",
            "grid": {
              "type": "two-by-two",
              "panes": [
                {
                  "name": "api",
                  "command": "npm run dev:api"
                },
                {
                  "name": "web",
                  "command": "npm run dev:web"
                },
                {
                  "name": "db",
                  "command": "docker-compose up postgres"
                },
                {
                  "name": "redis",
                  "command": "docker-compose up redis"
                }
              ]
            }
          },
          {
            "name": "monitoring",
            "layout": "grid",
            "grid": {
              "type": "main-side",
              "panes": [
                {
                  "name": "logs",
                  "command": "tail -f logs/development.log"
                },
                {
                  "name": "htop",
                  "command": "htop"
                },
                {
                  "name": "docker",
                  "command": "docker stats"
                }
              ]
            }
          }
        ]
      }
    ]
  }
}
```

### Mixing All Three Layout Types

You can use all layout types in the same session:

```json
{
  "tmux": {
    "sessions": [
      {
        "name": "mixed",
        "windows": [
          {
            "name": "simple",
            "layout": "compact",
            "compact": {
              "type": "vertical",
              "panes": {
                "left": "nvim",
                "right": "bash"
              }
            }
          },
          {
            "name": "moderate",
            "layout": "grid",
            "grid": {
              "type": "main-side",
              "panes": [
                { "name": "main", "path": "src" },
                { "name": "side-1" },
                { "name": "side-2" }
              ]
            }
          },
          {
            "name": "complex",
            "layout": "sections",
            "section": {
              "split": "vertical",
              "items": [
                {
                  "name": "sidebar",
                  "size": "20%"
                },
                {
                  "split": "horizontal",
                  "size": "80%",
                  "items": [
                    { "name": "main", "size": "70%" },
                    { "name": "footer", "size": "30%" }
                  ]
                }
              ]
            }
          }
        ]
      }
    ]
  }
}
```
