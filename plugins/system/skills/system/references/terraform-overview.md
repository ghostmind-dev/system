# Terraform Infrastructure Overview

## Introduction

This document explains how Terraform is configured and used within Ghostmind's development system for **production deployments**. Terraform handles Infrastructure-as-Code for Google Cloud Platform deployments, particularly Google Cloud Run services.

## Core Concept: Production Infrastructure-as-Code

Terraform in Ghostmind's system:
- **Production deployments** - Used for deploying to Google Cloud Platform
- **Google Cloud Run focused** - Optimized for serverless container deployments
- **Meta.json configured** - Infrastructure location and container references defined centrally
- **Standardized structure** - Consistent file organization across all projects

## Terraform Configuration in meta.json

**⚠️ ALWAYS fetch the schema first:**
```
https://raw.githubusercontent.com/ghostmind-dev/run/refs/heads/main/meta/schema.json
```

The Terraform configuration is defined under the `terraform` property in `meta.json`:

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

### Configuration Properties

#### `path` (required)
- **Purpose**: Specifies the directory where Terraform files are located
- **Example**: `"path": "infra"`
- **Result**: Terraform files are in `/path/to/project/infra/`
- **Common values**: `"infra"`, `"terraform"`, `"infrastructure"`

#### `global` (optional)
- **Purpose**: Flag to indicate if the configuration is global scope
- **Default**: `false`
- **Values**: `true` or `false`

#### `containers` (required)
- **Purpose**: List of Docker container configurations to deploy
- **Example**: `["default"]` references the "default" docker configuration from meta.json
- **Multiple containers**: `["api", "worker", "nginx"]` for multi-service deployments

**For complete `terraform` property structure:** Fetch the schema

## Required Terraform File Structure

Ghostmind's Terraform setup **always requires** these specific files:

### 1. `backend.tf` (Required)
**Purpose**: Defines Terraform state backend using Google Cloud Storage

```hcl
terraform {
  backend "gcs" {}
}
```

**Key points:**
- **Always use `backend "gcs"`** for Google Cloud Storage state management
- Configuration details provided via backend config during initialization
- Enables team collaboration and state locking

### 2. `versions.tf` (Required)
**Purpose**: Specifies Terraform and provider version requirements

```hcl
terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
    }
  }
  required_version = ">= 1.3.7"
}
```

**Current version**: `>= 1.3.7`
**Note**: This version requirement should be updated when Terraform versions change

### 3. `variables.tf` (Auto-generated)
**Purpose**: Defines input variables for the Terraform configuration
**Important**: This file is **automatically generated** by tooling - do not create manually

### 4. `main.tf` (Required)
**Purpose**: Contains the main infrastructure resources

## Standard main.tf Structure

Based on the current Google Cloud Run deployment pattern:

```hcl
provider "google" {
  project = var.GCP_PROJECT_ID
}

resource "google_cloud_run_v2_service" "default" {
  name     = "${var.PROJECT}-${var.ENVIRONMENT}-${var.APP}"
  location = "us-central1"

  deletion_protection = false

  template {
    scaling {
      min_instance_count = 0
      max_instance_count = 1
    }

    containers {
      image = var.IMAGE_DIGEST_DEFAULT

      resources {
        limits = {
          cpu    = "2000m"
          memory = "4Gi"
        }
        cpu_idle          = true
        startup_cpu_boost = false
      }

      ports {
        container_port = var.PORT
      }

      # Dynamic environment variables
      dynamic "env" {
        for_each = local.env_vars
        content {
          name  = env.value.name
          value = env.value.value
        }
      }
    }
  }
}

# IAM configuration for public access
data "google_iam_policy" "noauth" {
  binding {
    role    = "roles/run.invoker"
    members = ["allUsers"]
  }
}

resource "google_cloud_run_service_iam_policy" "noauth" {
  location = google_cloud_run_v2_service.default.location
  project  = google_cloud_run_v2_service.default.project
  service  = google_cloud_run_v2_service.default.name

  policy_data = data.google_iam_policy.noauth.policy_data
}
```

## Available Variables

The following variables are automatically available through the tooling:

### Core Variables
- **`GCP_PROJECT_ID`** - Google Cloud Project ID
- **`PROJECT`** - Project name from meta.json
- **`ENVIRONMENT`** - Deployment environment (dev, staging, prod)
- **`APP`** - Application name from meta.json

### Container Variables
- **`IMAGE_DIGEST_DEFAULT`** - Docker image digest for the "default" container
- **`PORT`** - Application port number

### Dynamic Environment Variables
- **`local.env_vars`** - Auto-generated from environment configuration

## Integration with Docker Configuration

Terraform deployments reference Docker images defined in meta.json:

```json
{
  "docker": {
    "default": {
      "image": "gcr.io/project/app"
    }
  },
  "terraform": {
    "run": {
      "containers": ["default"]
    }
  }
}
```

The `containers` array links to Docker configurations:
- `"default"` → uses `docker.default.image`
- `"api"` → uses `docker.api.image`

## Multi-Container Deployments

For applications with multiple services:

### meta.json Configuration
```json
{
  "docker": {
    "api": {
      "image": "gcr.io/project/api"
    },
    "worker": {
      "image": "gcr.io/project/worker"
    }
  },
  "terraform": {
    "run": {
      "containers": ["api", "worker"]
    }
  }
}
```

### Terraform Variables Available
- `var.IMAGE_DIGEST_API`
- `var.IMAGE_DIGEST_WORKER`

## File Organization Example

```
project/
├── meta.json
├── infra/                    # Terraform directory
│   ├── backend.tf           # ✅ Required: GCS backend
│   ├── versions.tf          # ✅ Required: Version constraints
│   ├── variables.tf         # ✅ Auto-generated by tooling
│   ├── main.tf              # ✅ Required: Main resources
│   └── .terraform.lock.hcl  # Generated by terraform init
```

## Current Status: Work in Progress

**Important Note**: The Terraform automation is currently **work in progress**. While the structure and patterns are established, the tooling for automation may evolve.

**Current approach**:
- Manual Terraform configuration based on templates
- Standardized file structure requirements
- Integration with Docker image references from meta.json

**Future considerations**:
- Enhanced automation through tooling
- Template generation based on meta.json configuration
- Simplified deployment workflows

## Best Practices

1. **Always include required files**: `backend.tf`, `versions.tf`, `main.tf`
2. **Use GCS backend** for state management
3. **Reference Docker containers** via meta.json `containers` array
4. **Follow naming conventions**: `${var.PROJECT}-${var.ENVIRONMENT}-${var.APP}`
5. **Keep versions up to date**: Currently using Terraform >= 1.3.7
6. **Let tooling generate variables.tf** - don't create manually

## Integration with Deployment Workflow

1. **Development**: Docker Compose (local development only)
2. **Production**: Terraform + Google Cloud Run
3. **Container Images**: Built from Docker configurations
4. **State Management**: Google Cloud Storage backend
5. **Environment Variables**: Injected via dynamic configuration

This infrastructure setup enables consistent, reproducible deployments while maintaining the flexibility to adapt to different application architectures within Ghostmind's development workflow.